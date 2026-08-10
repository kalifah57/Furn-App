import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/recommendation/recommendation_engine.dart';
import 'package:furn_app/shared/models/models.dart';

CatalogProduct product({
  required String id,
  required RecommendationCategory category,
  required double price,
  double w = 100,
  double d = 100,
  String availability = 'in_stock',
  double? rating,
  List<String> style = const ['modern'],
}) =>
    CatalogProduct(
      productId: id,
      title: id,
      category: category,
      price: price,
      widthCm: w,
      depthCm: d,
      heightCm: 50,
      availabilityStatus: availability,
      ratingOptional: rating,
      styleTags: style,
      roomSuitabilityTags: const ['bedroom'],
    );

void main() {
  const engine = RecommendationEngine();

  final catalog = <CatalogProduct>[
    product(id: 'bed_cheap', category: RecommendationCategory.bed, price: 320, w: 90, d: 190, rating: 3.9),
    product(id: 'bed_mid', category: RecommendationCategory.bed, price: 780, w: 140, d: 200, rating: 4.4),
    product(id: 'bed_premium', category: RecommendationCategory.bed, price: 1250, w: 160, d: 210, rating: 4.8),
    product(id: 'bed_oos', category: RecommendationCategory.bed, price: 300, w: 90, d: 190, availability: 'out_of_stock'),
    product(id: 'sofa_cheap', category: RecommendationCategory.sofa, price: 290, w: 70, d: 75, rating: 4.0),
    product(id: 'sofa_mid', category: RecommendationCategory.sofa, price: 520, w: 120, d: 70, rating: 4.1),
    product(id: 'sofa_giant', category: RecommendationCategory.sofa, price: 1900, w: 700, d: 300, rating: 4.7),
    product(id: 'rug_small', category: RecommendationCategory.rug, price: 140, w: 120, d: 180, rating: 4.0),
    product(id: 'lamp_x', category: RecommendationCategory.lamp, price: 160, w: 30, d: 30, rating: 4.1),
  ];

  final project = FurnishingProject(
    projectId: 't',
    room: const Room(widthM: 4, lengthM: 6, roomType: RoomType.bedroom),
    budget: const Budget(maxTotal: 1800),
    style: const StylePreferences(preferred: ['modern']),
    items: const RequestedItems(
      essential: [RequestedItem(type: 'bed'), RequestedItem(type: 'sofa')],
      optional: [RequestedItem(type: 'rug')],
    ),
  );

  test('produces individual items and three bundles', () {
    final recs = engine.generate(project, catalog);
    expect(recs.individualItems, isNotEmpty);
    expect(recs.bundles.length, 3);
    expect(recs.bundles.map((b) => b.tier),
        containsAll([BundleTier.budget, BundleTier.balanced, BundleTier.premium]));
  });

  test('excludes out-of-stock, oversized, and non-requested products', () {
    final recs = engine.generate(project, catalog);
    final ids = <String>{
      ...recs.individualItems.map((i) => i.productId ?? ''),
      for (final b in recs.bundles) ...b.items.map((i) => i.productId ?? ''),
    };
    expect(ids, isNot(contains('bed_oos'))); // غير متوفر
    expect(ids, isNot(contains('sofa_giant'))); // لا يدخل المساحة
    expect(ids, isNot(contains('lamp_x'))); // فئة غير مطلوبة
  });

  test('budget bundle picks cheapest essentials within budget', () {
    final recs = engine.generate(project, catalog);
    final budget = recs.bundles.firstWhere((b) => b.tier == BundleTier.budget);
    expect(budget.totalPrice, lessThanOrEqualTo(1800));
    expect(budget.exceedsBudget, isFalse);
    final ids = budget.items.map((i) => i.productId).toSet();
    expect(ids, containsAll(['bed_cheap', 'sofa_cheap']));
  });

  test('individual recommendations cover requested categories', () {
    final recs = engine.generate(project, catalog);
    final cats = recs.individualItems.map((i) => i.category).toSet();
    expect(cats, contains(RecommendationCategory.bed));
    expect(cats, contains(RecommendationCategory.sofa));
  });

  test('empty catalog yields no bundles (fallback territory)', () {
    final recs = engine.generate(project, const []);
    expect(recs.isEmpty, isTrue);
  });
}
