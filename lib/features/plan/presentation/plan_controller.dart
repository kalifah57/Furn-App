import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../domain_engine/plan/plan.dart';
import '../../../domain_engine/plan/plan_workspace.dart';
import '../../../shared/models/models.dart';
import '../../room_input/presentation/flow_controller.dart';
import '../data/plan_draft_store.dart';

/// مشروع تجريبي للدخول المباشر إلى مساحة الخطة (من شاشة البداية).
const _demoProject = FurnishingProject(
  projectId: 'demo',
  room: Room(
      name: 'غرفة النوم', widthM: 3, lengthM: 3.5, roomType: RoomType.bedroom),
  budget: Budget(maxTotal: 1800),
  style: StylePreferences(preferred: ['modern'], colors: ['gray', 'white']),
  items: RequestedItems(
    essential: [RequestedItem(type: 'سرير'), RequestedItem(type: 'دولاب')],
    optional: [RequestedItem(type: 'إضاءة'), RequestedItem(type: 'طاولة')],
  ),
);

/// مخزن مسوّدة الخطة — يُستبدَل في الاختبارات بمخزن في الذاكرة.
final planDraftStoreProvider =
    Provider<PlanDraftStore>((ref) => const PlanDraftStore());

/// المشروع الذي تُبنى عليه الخطة، بهذا الترتيب:
/// مشروع التدفّق (input → analysis) إن اكتمل، ثم **المُلخّص المحفوظ** إن وُجد،
/// وإلا المشروع التجريبي.
///
/// المسوّدة قبل التجريبي عمدًا: من حدّث الصفحة بعد أن شكّل خطته يجب أن يرى غرفته
/// هو، لا غرفة عرض. المشروع التجريبي آخر الخيارات لا أوّلها.
final planProjectProvider = Provider<FurnishingProject>((ref) {
  final flowProject = ref.watch(furnishingFlowControllerProvider).project;
  if (flowProject != null) return flowProject;
  return ref.read(planDraftStoreProvider).load()?.brief ?? _demoProject;
});

/// يحمّل الكتالوج، يستعيد المسوّدة إن كانت لنفس المشروع، ثم يبني [PlanController]
/// فوق [PlanWorkspace] (نواة حلقة الثقة).
final planControllerProvider = FutureProvider<PlanController>((ref) async {
  final res = await ref.read(catalogRepositoryProvider).loadProducts();
  final catalog = res.valueOrNull ?? const <CatalogProduct>[];
  final project = ref.read(planProjectProvider);
  final store = ref.read(planDraftStoreProvider);
  final ws = PlanWorkspace(project: project, catalog: catalog);

  // القرارات تُستعاد لنفس المشروع فقط: تثبيتات مشروع سابق فوق مُلخّص جديد ليست
  // استعادة بل تلويث — قد تشير إلى منتجات لا علاقة لها بهذه الغرفة.
  final draft = store.load();
  var restored = false;
  if (draft != null && draft.brief.projectId == project.projectId) {
    ws.restore(draft.state);
    restored = true;
  }

  final controller = PlanController(
    ws,
    analytics: ref.read(analyticsProvider),
    store: store,
    restored: restored,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// يترجم نيّة المستخدم (تثبيت/رفض/تبديل/ميزانية) إلى إعادة بناء للخطة،
/// ويحتفظ بآخر تغيير لعرض «ما الذي تغيّر».
class PlanController extends ChangeNotifier {
  PlanController(
    this._ws, {
    Analytics analytics = const NoopAnalytics(),
    PlanDraftStore? store,
    bool restored = false,
  })  : _analytics = analytics,
        _store = store {
    plan = _ws.build();
    if (restored) {
      final s = _ws.snapshot();
      _analytics.track(PlanRestored(
        confidence: plan.confidence,
        itemCount: plan.itemCount,
        decisions: s.pinned.length + s.rejected.length,
      ));
    } else {
      _analytics.track(PlanSeeded(
        confidence: plan.confidence,
        itemCount: plan.itemCount,
        missingCount: plan.missingCategories.length,
        total: plan.total,
        withinBudget: plan.assurances.withinBudget,
      ));
      // نحفظ البذرة فورًا: من أكمل التدفّق ثم أغلق المتصفّح دون أن يعدّل شيئًا
      // كان سيعود إلى المشروع التجريبي، أي يفقد غرفته لأنه لم يضغط زرًّا.
      _persist();
    }
  }

  final PlanWorkspace _ws;
  final Analytics _analytics;
  final PlanDraftStore? _store;
  late Plan plan;
  PlanDiff? lastChange;

  /// عدد تعديلات المستخدم قبل الإنهاء (تثبيت/رفض/تبديل/ميزانية) — يعكس التفاعل.
  int _edits = 0;
  bool _abandonLogged = false;

  final List<Plan> _snapshots = [];
  final List<WorkspaceState> _states = [];

  FurnishingProject get project => _ws.project;

  /// Saved versions, newest last (for compare + revert).
  List<Plan> get snapshots => List.unmodifiable(_snapshots);

  void saveSnapshot() {
    _snapshots.add(plan);
    _states.add(_ws.snapshot());
    notifyListeners();
  }

  void revertTo(int index) {
    if (index < 0 || index >= _states.length) return;
    _ws.restore(_states[index]);
    plan = _ws.build();
    lastChange = null;
    _persist();
    notifyListeners();
  }

  /// How the current plan differs from a saved version.
  PlanDiff compareWith(int index) => PlanWorkspace.diff(_snapshots[index], plan);

  /// يكتب المُلخّص + القرارات بعد كل تغيير. المُلخّص يُحفظ أيضًا لأن
  /// [PlanWorkspace.setBudget] يغيّره، فحفظ القرارات وحدها كان سيفقد الميزانية.
  void _persist() => _store?.save(_ws.project, _ws.snapshot());

  void _apply(void Function() op) {
    final before = plan;
    op();
    plan = _ws.build();
    lastChange = PlanWorkspace.diff(before, plan);
    _persist();
    notifyListeners();
  }

  void pin(String id) {
    _apply(() => _ws.pin(id));
    _edits++;
    _analytics.track(ItemPinned(_categoryOf(id)));
  }

  void unpin(String id) => _apply(() => _ws.unpin(id));

  void reject(String id) {
    final category = _categoryOf(id);
    _apply(() => _ws.reject(id));
    _edits++;
    _analytics.track(ItemRejected(category));
  }

  void swap(String outId, String inId) {
    _apply(() => _ws.swap(outProductId: outId, inProductId: inId));
    _edits++;
    _analytics.track(ItemSwapped(_categoryOf(inId)));
  }

  void setBudget(double v) {
    final before = plan.confidence;
    _apply(() => _ws.setBudget(v));
    _edits++;
    _analytics
        .track(BudgetChanged(newMax: v, deltaConfidence: plan.confidence - before));
  }

  void addCheapestOf(RecommendationCategory category) {
    final alts = _ws.alternativesFor(category);
    if (alts.isNotEmpty) pin(alts.first.productId);
  }

  void finalizePlan() {
    _apply(_ws.finalizePlan);
    _analytics.track(PlanFinalized(
      confidence: plan.confidence,
      itemCount: plan.itemCount,
      pinnedCount: plan.pinnedCount,
      edits: _edits,
    ));
  }

  void reopen() => _apply(_ws.reopen);

  List<CatalogProduct> alternativesFor(RecommendationCategory c) =>
      _ws.alternativesFor(c);

  /// منتج الكتالوج المصدر لعنصر في الخطة (للوصول إلى نموذج الـ AR ومقاسه).
  CatalogProduct? productById(String? id) {
    if (id == null) return null;
    for (final p in _ws.catalog) {
      if (p.productId == id) return p;
    }
    return null;
  }

  // ---- ملاحظة (analytics فقط — لا تغيّر الحالة) --------------------------
  void logOptionsOpened(RecommendationCategory category, int count) =>
      _analytics.track(OptionsOpened(category: category.wire, optionCount: count));

  void logShared() => _analytics.track(PlanShared(plan.confidence));

  /// يُستدعى عند مغادرة شاشة الخطة دون إنهاء (يُرسَل مرّة واحدة).
  void logAbandonedIfUnfinished() {
    if (_abandonLogged || plan.isFinalized) return;
    _abandonLogged = true;
    _analytics.track(
        SessionAbandoned(lastStep: 'plan', lastConfidence: plan.confidence));
  }

  String _categoryOf(String? id) =>
      productById(id)?.category.wire ?? 'unknown';
}
