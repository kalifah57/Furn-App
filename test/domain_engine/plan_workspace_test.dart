import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/plan/plan.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/shared/models/models.dart';

/// Spec for the confidence loop's core. Pure domain — no Flutter widgets.
void main() {
  const catalog = <CatalogProduct>[
    CatalogProduct(
        productId: 'bed_a',
        title: 'سرير أ',
        category: RecommendationCategory.bed,
        widthCm: 90,
        depthCm: 200,
        price: 450),
    CatalogProduct(
        productId: 'bed_b',
        title: 'سرير ب',
        category: RecommendationCategory.bed,
        widthCm: 140,
        depthCm: 200,
        price: 780),
    CatalogProduct(
        productId: 'ward_a',
        title: 'دولاب أ',
        category: RecommendationCategory.storage,
        widthCm: 80,
        depthCm: 50,
        price: 540),
  ];

  final project = FurnishingProject(
    projectId: 't',
    room: const Room(widthM: 3, lengthM: 3.5, roomType: RoomType.bedroom),
    budget: const Budget(maxTotal: 1800),
    items: const RequestedItems(
      essential: [RequestedItem(type: 'سرير'), RequestedItem(type: 'دولاب')],
    ),
  );

  PlanWorkspace ws() => PlanWorkspace(project: project, catalog: catalog);

  test('seed plan covers the requested essentials', () {
    final plan = ws().build();
    expect(plan.missingCategories, isEmpty);
    expect(plan.assurances.essentialsComplete, isTrue);
    expect(plan.items, isNotEmpty);
  });

  test('reject removes a product from the plan', () {
    final w = ws();
    w.reject('bed_b');
    final plan = w.build();
    expect(plan.items.every((i) => i.item.productId != 'bed_b'), isTrue);
  });

  test('pin forces a product in and marks ownership', () {
    final w = ws();
    w.pin('bed_b');
    final plan = w.build();
    expect(
        plan.items.any((i) => i.item.productId == 'bed_b' && i.isPinned), isTrue);
    expect(plan.pinnedCount, greaterThan(0));
  });

  test('engagement nudges confidence upward, capped at 100', () {
    final w = ws();
    final base = w.build();
    w.pin('bed_a');
    final engaged = w.build();
    expect(engaged.confidence, greaterThanOrEqualTo(base.confidence));
    expect(engaged.confidence, lessThanOrEqualTo(100));
  });

  test('a pinned item over budget flags withinBudget', () {
    final w = ws();
    w.pin('bed_b'); // 780
    w.setBudget(500);
    final plan = w.build();
    expect(plan.assurances.withinBudget, isFalse);
  });

  test('diff reports the change and the price delta', () {
    final w = ws();
    final before = w.build();
    w.pin('bed_b');
    final after = w.build();
    final d = PlanWorkspace.diff(before, after);
    expect(d.deltaTotal, isNot(0));
  });

  test('snapshot + restore reproduces a saved plan (revert)', () {
    final w = ws();
    w.pin('bed_b');
    final saved = w.snapshot();
    final savedPlan = w.build();

    // drift away from the saved state
    w.unpin('bed_b');
    w.reject('bed_b');
    w.setBudget(9000);

    // revert
    w.restore(saved);
    final restored = w.build();

    expect(restored.total, savedPlan.total);
    expect(restored.items.any((i) => i.item.productId == 'bed_b'), isTrue);
  });
}
