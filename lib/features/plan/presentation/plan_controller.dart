import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../domain_engine/plan/plan.dart';
import '../../../domain_engine/plan/plan_workspace.dart';
import '../../../shared/models/models.dart';
import '../../room_input/presentation/flow_controller.dart';

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

/// المشروع الذي تُبنى عليه الخطة: مشروع التدفّق (input → analysis) إن اكتمل،
/// وإلا المشروع التجريبي — دون تغيير الشاشة.
final planProjectProvider = Provider<FurnishingProject>((ref) {
  final flowProject = ref.watch(furnishingFlowControllerProvider).project;
  return flowProject ?? _demoProject;
});

/// يحمّل الكتالوج ثم يبني [PlanController] فوق [PlanWorkspace] (نواة حلقة الثقة).
final planControllerProvider = FutureProvider<PlanController>((ref) async {
  final res = await ref.read(catalogRepositoryProvider).loadProducts();
  final catalog = res.valueOrNull ?? const <CatalogProduct>[];
  final controller = PlanController(
    PlanWorkspace(project: ref.read(planProjectProvider), catalog: catalog),
    analytics: ref.read(analyticsProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// يترجم نيّة المستخدم (تثبيت/رفض/تبديل/ميزانية) إلى إعادة بناء للخطة،
/// ويحتفظ بآخر تغيير لعرض «ما الذي تغيّر».
class PlanController extends ChangeNotifier {
  PlanController(this._ws, {Analytics analytics = const NoopAnalytics()})
      : _analytics = analytics {
    plan = _ws.build();
    _analytics.track(PlanSeeded(
      confidence: plan.confidence,
      itemCount: plan.itemCount,
      missingCount: plan.missingCategories.length,
      total: plan.total,
      withinBudget: plan.assurances.withinBudget,
    ));
  }

  final PlanWorkspace _ws;
  final Analytics _analytics;
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
    notifyListeners();
  }

  /// How the current plan differs from a saved version.
  PlanDiff compareWith(int index) => PlanWorkspace.diff(_snapshots[index], plan);

  void _apply(void Function() op) {
    final before = plan;
    op();
    plan = _ws.build();
    lastChange = PlanWorkspace.diff(before, plan);
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
