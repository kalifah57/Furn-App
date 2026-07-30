import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/budget/budget_allocator.dart';
import 'package:furn_app/domain_engine/recommendation/bundle_composer.dart';
import 'package:furn_app/domain_engine/recommendation/scored_candidate.dart';
import 'package:furn_app/domain_engine/recommendation/scoring.dart';
import 'package:furn_app/shared/models/models.dart';

CatalogProduct prod(
  String id,
  RecommendationCategory cat,
  double price, {
  double rating = 4.0,
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
      ratingOptional: rating,
      styleTags: const ['modern'],
    );

void main() {
  const composer = BundleComposer();
  const scorer = RecommendationScorer();
  const allocator = BudgetAllocator();

  final project = FurnishingProject(
    projectId: 't',
    room: const Room(widthM: 4, lengthM: 6, roomType: RoomType.bedroom),
    budget: const Budget(maxTotal: 1800),
    style: const StylePreferences(preferred: ['modern']),
    items: const RequestedItems(
      essential: [RequestedItem(type: 'bed'), RequestedItem(type: 'sofa')],
    ),
  );

  List<ScoredCandidate> scoreAll(List<CatalogProduct> items) {
    final alloc = allocator.allocate(project.room, project.budget);
    final ctx = ScoringContext(
      room: project.room,
      budget: project.budget,
      style: project.style,
      categoryCeilings: alloc.ceilings,
    );
    return items.map((p) => ScoredCandidate(p, scorer.score(p, ctx))).toList()
      ..sort((a, b) => b.breakdown.total.compareTo(a.breakdown.total));
  }

  const cats = {RecommendationCategory.bed, RecommendationCategory.sofa};

  test('composes three tiers; budget bundle picks cheapest, within budget', () {
    final viable = scoreAll([
      prod('bed_cheap', RecommendationCategory.bed, 320, rating: 3.9),
      prod('bed_mid', RecommendationCategory.bed, 780, rating: 4.4, w: 140, d: 200),
      prod('sofa_cheap', RecommendationCategory.sofa, 290, rating: 4.0, w: 70, d: 75),
      prod('sofa_mid', RecommendationCategory.sofa, 520, rating: 4.1, w: 120, d: 70),
    ]);
    final bundles = composer.compose(project, viable, cats);

    expect(bundles.length, 3);
    expect(bundles.map((b) => b.tier),
        containsAll([BundleTier.budget, BundleTier.balanced, BundleTier.premium]));

    final budget = bundles.firstWhere((b) => b.tier == BundleTier.budget);
    expect(budget.items.map((i) => i.productId), containsAll(['bed_cheap', 'sofa_cheap']));
    expect(budget.totalPrice, lessThanOrEqualTo(1800));
    expect(budget.exceedsBudget, isFalse);
  });

  test('premium prefers highest rating per category', () {
    final viable = scoreAll([
      prod('bed_ok', RecommendationCategory.bed, 700, rating: 4.0, w: 140, d: 200),
      prod('bed_best', RecommendationCategory.bed, 900, rating: 4.9, w: 150, d: 200),
      prod('sofa_only', RecommendationCategory.sofa, 400, rating: 4.2, w: 120, d: 70),
    ]);
    final premium =
        composer.compose(project, viable, cats).firstWhere((b) => b.tier == BundleTier.premium);
    expect(premium.items.map((i) => i.productId), contains('bed_best'));
  });

  test('empty viable yields no bundles', () {
    expect(composer.compose(project, const [], cats), isEmpty);
  });
}
