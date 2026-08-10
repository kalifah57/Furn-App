import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/result.dart';
import '../../../domain_engine/spatial/ar_spatial_engine.dart';
import '../../../domain_engine/spatial/placement_solver.dart';
import '../../../domain_engine/spatial/replacement_finder.dart';
import '../../../shared/models/models.dart';
import '../domain/room_scanner_service.dart';
import 'sandbox_providers.dart';

/// حالة الصندوق التفاعلي: الغرفة الممسوحة، ما فيها من قطع بمواضعها، ما هو
/// مُحدَّد الآن، والميزانية. كائن قيمة ثابت — كل تعديل يُنتج حالة جديدة.
class SandboxState {
  const SandboxState({
    required this.room,
    required this.plan,
    required this.totalBudget,
    required this.catalog,
    this.selectedProductId,
    this.textureRef = '',
  });

  final ScannedRoom room;
  final PlacementPlan plan;
  final double totalBudget;

  /// الكتالوج المحمّل — يُحتفظ به لأن الاستبدال يبحث فيه.
  final List<CatalogProduct> catalog;

  final String? selectedProductId;

  /// كساء الغرفة النظيف بعد إزالة الأثاث (فارغ = لم يُطلب/تعذّر).
  final String textureRef;

  RoomSpace get space => RoomSpace(
        widthCm: room.widthCm,
        lengthCm: room.lengthCm,
        ceilingCm: room.ceilingCm,
      );

  List<Placement> get items => plan.placements;
  double get spent => plan.totalPrice;
  double get remaining => totalBudget - spent;
  bool get isOverBudget => remaining < 0;

  Placement? get selected =>
      selectedProductId == null ? null : plan.byProductId(selectedProductId!);

  SandboxState copyWith({
    PlacementPlan? plan,
    double? totalBudget,
    Object? selectedProductId = _unset,
    String? textureRef,
  }) =>
      SandboxState(
        room: room,
        plan: plan ?? this.plan,
        totalBudget: totalBudget ?? this.totalBudget,
        catalog: catalog,
        // حارس يميّز «لم يُمرَّر» عن «ألغِ التحديد» — نفس الفخّ الذي وقع فيه
        // Project.copyWith مع approvedAt.
        selectedProductId: identical(selectedProductId, _unset)
            ? this.selectedProductId
            : selectedProductId as String?,
        textureRef: textureRef ?? this.textureRef,
      );
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// يقود المشهد ثلاثي الأبعاد: يمسح الغرفة، يؤلّف الباقة، يحسب المواضع، ويطبّق
/// الاستبدال مع إعادة حساب الميزانية فورًا.
///
/// كل المنطق الفعلي في `domain_engine/spatial` (نقي وحتمي)؛ هذا المتحكّم يوصّل
/// فقط — وهو ما يجعل قواعد المكان والاستبدال قابلة للاختبار بلا Flutter.
class SandboxController extends AsyncNotifier<SandboxState> {
  @override
  Future<SandboxState> build() async {
    final scan = await ref.read(roomScannerServiceProvider).scan();
    final room = scan.valueOrNull ??
        const ScannedRoom(widthCm: 380, lengthCm: 420, ceilingCm: 280);

    final loaded = await ref.read(catalogRepositoryProvider).loadProducts();
    final catalog = loaded.valueOrNull ?? const <CatalogProduct>[];

    final brief = ref.read(sandboxBriefProvider);
    final budget = brief.budget.maxTotal;

    final package = ref.read(packageComposerProvider).compose(
          catalog: catalog,
          roomType: brief.room.roomType,
          budget: budget,
        );

    final space = RoomSpace(
      widthCm: room.widthCm,
      lengthCm: room.lengthCm,
      ceilingCm: room.ceilingCm,
    );
    final plan = ref.read(placementSolverProvider).solve(package.items, space);

    return SandboxState(
      room: room,
      plan: plan,
      totalBudget: budget,
      catalog: catalog,
    );
  }

  // ---- إعادة المسح (تسليم إلى الجوال) ------------------------------------

  /// يعيد بناء المشهد على غرفة جديدة قادمة من الماسح.
  ///
  /// المسح ليس جزءًا من [build]: الصندوق يجب أن يفتح فورًا بغرفة المشروع حتى بلا
  /// جوال، و«امسح غرفتي» فعل صريح يبدّل الغرفة تحت نفس الباقة.
  Future<Result<ScannedRoom>> rescan() async {
    final previous = state.valueOrNull;
    final result = await ref.read(roomScannerServiceProvider).scan();
    final room = result.valueOrNull;
    if (room == null) return result; // نُبقي المشهد الحالي كما هو

    final catalog = previous?.catalog ?? const <CatalogProduct>[];
    final brief = ref.read(sandboxBriefProvider);
    final budget = previous?.totalBudget ?? brief.budget.maxTotal;

    final package = ref.read(packageComposerProvider).compose(
          catalog: catalog,
          roomType: brief.room.roomType,
          budget: budget,
        );
    final space = RoomSpace(
      widthCm: room.widthCm,
      lengthCm: room.lengthCm,
      ceilingCm: room.ceilingCm,
    );

    state = AsyncData(SandboxState(
      room: room,
      plan: ref.read(placementSolverProvider).solve(package.items, space),
      totalBudget: budget,
      catalog: catalog,
    ));
    return result;
  }

  // ---- التفاعل مع المشهد -------------------------------------------------

  /// نتيجة نقر المستخدم على مجسّم (raycast hit) — يفتح ورقة التفاصيل.
  void selectItem(String productId) {
    final s = state.valueOrNull;
    if (s == null) return;
    if (s.plan.byProductId(productId) == null) return; // نقرة خارج المشهد
    state = AsyncData(s.copyWith(selectedProductId: productId));
  }

  void clearSelection() {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(selectedProductId: null));
  }

  // ---- الاستبدال ---------------------------------------------------------

  /// البدائل الصالحة لقطعة في المشهد: تدخل في خانتها، وضمن الميزانية المُحرَّرة،
  /// ومرتّبة بقرب النمط.
  ///
  /// استعلام خالص — لا يغيّر الحالة. الاستبدال الفعلي في [replaceItem].
  List<ReplacementCandidate> alternativesFor(String productId) {
    final s = state.valueOrNull;
    if (s == null) return const [];
    final slot = s.plan.byProductId(productId);
    if (slot == null) return const [];

    return ref.read(replacementFinderProvider).alternativesFor(
          slot: slot,
          catalog: s.catalog,
          room: s.space,
          others: s.items,
          remainingBudget: s.remaining,
          style: ref.read(sandboxBriefProvider).style,
        );
  }

  /// يبدّل قطعة بأخرى **في مكانها نفسه** (نفس المركز والدوران)، فيتغيّر المجسّم
  /// والسعر الإجمالي في نفس اللحظة دون إعادة حلّ المشهد كاملًا.
  ///
  /// يعيد false إن لم يكن البديل ضمن قائمة البدائل الصالحة — فلا يمكن للواجهة
  /// أن تُدخل المشهد في حالة غير صالحة.
  bool replaceItem({
    required String productId,
    required String replacementProductId,
  }) {
    final s = state.valueOrNull;
    if (s == null) return false;
    final slot = s.plan.byProductId(productId);
    if (slot == null) return false;

    final allowed = alternativesFor(productId);
    CatalogProduct? replacement;
    for (final c in allowed) {
      if (c.product.productId == replacementProductId) {
        replacement = c.product;
        break;
      }
    }
    if (replacement == null) return false;

    final swapped = [
      for (final p in s.items)
        if (p.product.productId == productId)
          slot.copyWith(product: replacement)
        else
          p,
    ];

    state = AsyncData(s.copyWith(
      plan: PlacementPlan(placements: swapped, unplaced: s.plan.unplaced),
      selectedProductId: replacementProductId,
    ));
    return true;
  }

  /// يزيل قطعة من المشهد ويعيد ميزانيتها إلى المتبقّي.
  void removeItem(String productId) {
    final s = state.valueOrNull;
    if (s == null) return;
    final remaining = [
      for (final p in s.items)
        if (p.product.productId != productId) p,
    ];
    if (remaining.length == s.items.length) return;

    state = AsyncData(s.copyWith(
      plan: PlacementPlan(placements: remaining, unplaced: s.plan.unplaced),
      selectedProductId: s.selectedProductId == productId ? null : s.selectedProductId,
    ));
  }
}

final sandboxControllerProvider =
    AsyncNotifierProvider<SandboxController, SandboxState>(
        SandboxController.new);
