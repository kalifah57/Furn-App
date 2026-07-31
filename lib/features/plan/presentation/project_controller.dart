import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../domain_engine/plan/plan.dart';
import '../../../domain_engine/plan/plan_workspace.dart';
import '../../../domain_engine/project/decision.dart';
import '../../../domain_engine/project/project.dart';
import '../../../shared/models/models.dart';
import 'plan_controller.dart' show planProjectProvider;

/// يقود دورة حياة الـ **Project** (Draft → Active → Approved) فوق محرّك
/// [PlanWorkspace] القائم: يسجّل كل نيّة كـ [Decision] على مسار القرارات، يُعيد
/// اشتقاق الخطة، ويُطلق **نفس أحداث قِمع الثقة**. الـ Aggregate هو المكان الوحيد
/// الذي تتغيّر فيه الحالة (`record`/`approve`/`reopen`) — لا نلمس حقوله مباشرة.
///
/// T2/T3 — يتعايش مع [PlanController] حتى تربطه الشاشة في T4 عبر
/// `projectControllerProvider.when(...)`.
class ProjectController extends AsyncNotifier<Project> {
  late PlanWorkspace _ws;
  bool _abandonLogged = false;

  Analytics get _analytics => ref.read(analyticsProvider);

  @override
  Future<Project> build() async {
    final res = await ref.read(catalogRepositoryProvider).loadProducts();
    final catalog = res.valueOrNull ?? const <CatalogProduct>[];
    _ws = PlanWorkspace(project: ref.read(planProjectProvider), catalog: catalog);
    final seeded = _ws.build();
    _analytics.track(PlanSeeded(
      confidence: seeded.confidence,
      itemCount: seeded.itemCount,
      missingCount: seeded.missingCategories.length,
      total: seeded.total,
      withinBudget: seeded.assurances.withinBudget,
    ));
    return Project(
      id: ref.read(uuidProvider).v4(),
      brief: _ws.project,
      plan: seeded,
    );
  }

  // ---- intents (كلها تمرّ عبر الـ Aggregate) -----------------------------

  void pin(String id) => _record(
        DecisionKind.pinned,
        () => _ws.pin(id),
        productId: id,
        category: _categoryOf(id),
        event: (_) => ItemPinned(_wireOf(id)),
      );

  void reject(String id) => _record(
        DecisionKind.rejected,
        () => _ws.reject(id),
        productId: id,
        category: _categoryOf(id),
        event: (_) => ItemRejected(_wireOf(id)),
      );

  void swap(String outId, String inId) => _record(
        DecisionKind.swapped,
        () => _ws.swap(outProductId: outId, inProductId: inId),
        productId: inId,
        category: _categoryOf(inId),
        event: (_) => ItemSwapped(_wireOf(inId)),
      );

  void setBudget(double v) {
    final before = state.valueOrNull?.confidence ?? 0;
    _record(
      DecisionKind.budgetSet,
      () => _ws.setBudget(v),
      value: v,
      event: (rebuilt) =>
          BudgetChanged(newMax: v, deltaConfidence: rebuilt.confidence - before),
    );
  }

  void addCheapestOf(RecommendationCategory category) {
    final alts = _ws.alternativesFor(category);
    if (alts.isNotEmpty) pin(alts.first.productId);
  }

  /// إلغاء التثبيت: يُعيد الاشتقاق دون قرار على المسار ودون حدث (مطابقة السلوك الحالي).
  void unpin(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    _ws.unpin(id);
    state = AsyncData(current.copyWith(plan: _ws.build()));
  }

  /// اعتماد المشروع → Approved، ثم الحفظ عبر [ProjectRepository]، ثم plan_finalized.
  Future<void> approve() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final approved = current.approve(DateTime.now());
    state = AsyncData(approved);
    // TODO(persist): احفظ الـ Project الكامل (مع المسار) لاحقًا؛ الآن نحفظ المُلخّص.
    await ref.read(projectRepositoryProvider).save(approved.brief);
    _analytics.track(PlanFinalized(
      confidence: approved.confidence,
      itemCount: approved.plan.itemCount,
      pinnedCount: approved.plan.pinnedCount,
      edits: approved.timeline.edits,
    ));
  }

  void reopen() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.reopen(DateTime.now()));
  }

  // ---- reads جاهزة للشاشة (T4) --------------------------------------------

  Project get project => state.requireValue;

  List<CatalogProduct> alternativesFor(RecommendationCategory c) =>
      _ws.alternativesFor(c);

  CatalogProduct? productById(String? id) {
    if (id == null) return null;
    for (final p in _ws.catalog) {
      if (p.productId == id) return p;
    }
    return null;
  }

  // ---- ملاحظة (analytics فقط) ---------------------------------------------

  void logOptionsOpened(RecommendationCategory category, int count) =>
      _analytics.track(OptionsOpened(category: category.wire, optionCount: count));

  void logShared() {
    final current = state.valueOrNull;
    if (current == null) return;
    _analytics.track(PlanShared(current.confidence));
  }

  void logAbandonedIfUnfinished() {
    final current = state.valueOrNull;
    if (current == null || _abandonLogged || current.isApproved) return;
    _abandonLogged = true;
    _analytics.track(
        SessionAbandoned(lastStep: 'plan', lastConfidence: current.confidence));
  }

  // ---- internals ----------------------------------------------------------

  void _record(
    DecisionKind kind,
    void Function() intent, {
    String? productId,
    RecommendationCategory? category,
    double? value,
    AnalyticsEvent Function(Plan rebuilt)? event,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    intent();
    final rebuilt = _ws.build();
    final decision = Decision(
      kind: kind,
      at: DateTime.now(),
      productId: productId,
      category: category,
      value: value,
      confidenceAfter: rebuilt.confidence,
    );
    // الخطة/المسار/الحالة تتغيّر عبر record فقط؛ نُزامن المُلخّص من المحرّك لأن
    // الميزانية جزء منه وقد تتغيّر عبر setBudget.
    state = AsyncData(current.record(decision, rebuilt).copyWith(brief: _ws.project));
    if (event != null) _analytics.track(event(rebuilt));
  }

  RecommendationCategory? _categoryOf(String id) => productById(id)?.category;
  String _wireOf(String id) => _categoryOf(id)?.wire ?? 'unknown';
}

/// نفس بذرة [planControllerProvider] لكن حول الـ Aggregate — الشاشة تربطه في T4.
final projectControllerProvider =
    AsyncNotifierProvider<ProjectController, Project>(ProjectController.new);
