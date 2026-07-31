import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// يترجم نيّة المستخدم (تثبيت/رفض/تبديل/ميزانية) إلى إعادة بناء للخطة،
/// ويحتفظ بآخر تغيير لعرض «ما الذي تغيّر».
class PlanController extends ChangeNotifier {
  PlanController(this._ws) {
    plan = _ws.build();
  }

  final PlanWorkspace _ws;
  late Plan plan;
  PlanDiff? lastChange;

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

  void pin(String id) => _apply(() => _ws.pin(id));
  void unpin(String id) => _apply(() => _ws.unpin(id));
  void reject(String id) => _apply(() => _ws.reject(id));
  void swap(String outId, String inId) =>
      _apply(() => _ws.swap(outProductId: outId, inProductId: inId));
  void setBudget(double v) => _apply(() => _ws.setBudget(v));
  void addCheapestOf(RecommendationCategory category) {
    final alts = _ws.alternativesFor(category);
    if (alts.isNotEmpty) pin(alts.first.productId);
  }

  void finalizePlan() => _apply(_ws.finalizePlan);
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
}
