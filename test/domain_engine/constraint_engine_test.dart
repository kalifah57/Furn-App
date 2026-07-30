import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/budget/budget_allocator.dart';
import 'package:furn_app/domain_engine/constraint/constraint_engine.dart';
import 'package:furn_app/domain_engine/recommendation/scoring.dart';
import 'package:furn_app/shared/models/models.dart';

CatalogProduct prod(
  String id,
  RecommendationCategory cat,
  double price, {
  String availability = 'in_stock',
  double w = 90,
  double d = 190,
}) =>
    CatalogProduct(
      productId: id,
      title: id,
      category: cat,
      price: price,
      widthCm: w,
      depthCm: d,
      heightCm: 50,
      availabilityStatus: availability,
      styleTags: const ['modern'],
    );

void main() {
  const engine = ConstraintEngine();
  const scorer = RecommendationScorer();
  const allocator = BudgetAllocator();

  final room = const Room(widthM: 4, lengthM: 6, roomType: RoomType.bedroom);
  final budget = const Budget(maxTotal: 1800);

  ScoringContext ctx() {
    final alloc = allocator.allocate(room, budget);
    return ScoringContext(
      room: room,
      budget: budget,
      style: const StylePreferences(preferred: ['modern']),
      categoryCeilings: alloc.ceilings,
    );
  }

  const requested = {RecommendationCategory.bed, RecommendationCategory.sofa};

  test('excludes out-of-stock, wrong category, oversized, over-ceiling', () {
    final catalog = [
      prod('bed_ok', RecommendationCategory.bed, 500),
      prod('bed_oos', RecommendationCategory.bed, 500, availability: 'out_of_stock'),
      prod('lamp_x', RecommendationCategory.lamp, 100), // not requested
      prod('sofa_giant', RecommendationCategory.sofa, 900, w: 700, d: 300), // no fit
      prod('bed_pricey', RecommendationCategory.bed, 5000), // > 2.5x ceiling
    ];
    final eligible = engine.selectEligible(catalog, ctx(), requested, scorer);
    final ids = eligible.map((s) => s.product.productId).toSet();

    expect(ids, contains('bed_ok'));
    expect(ids, isNot(contains('bed_oos')));
    expect(ids, isNot(contains('lamp_x')));
    expect(ids, isNot(contains('sofa_giant')));
    expect(ids, isNot(contains('bed_pricey')));
  });

  test('result is sorted by score descending', () {
    final catalog = [
      prod('a', RecommendationCategory.bed, 400),
      prod('b', RecommendationCategory.sofa, 400, w: 70, d: 75),
      prod('c', RecommendationCategory.bed, 700, w: 140, d: 200),
    ];
    final eligible = engine.selectEligible(catalog, ctx(), requested, scorer);
    for (var i = 1; i < eligible.length; i++) {
      expect(eligible[i - 1].breakdown.total,
          greaterThanOrEqualTo(eligible[i].breakdown.total));
    }
  });

  test('empty requested categories keeps all fitting/available products', () {
    final catalog = [prod('bed_ok', RecommendationCategory.bed, 500)];
    final eligible = engine.selectEligible(catalog, ctx(), const {}, scorer);
    expect(eligible.map((s) => s.product.productId), contains('bed_ok'));
  });
}
