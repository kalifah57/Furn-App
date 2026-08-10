import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/recommendation/scoring.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  group('ScoringWeights.forContext', () {
    test('small room boosts room compatibility weight', () {
      final w = ScoringWeights.forContext(
        const Room(widthM: 3, lengthM: 3),
        const Budget(maxTotal: 1000),
      );
      expect(w.roomCompatibility, 0.45);
    });

    test('tight (non-flexible) budget boosts budget weight', () {
      final w = ScoringWeights.forContext(
        const Room(widthM: 4, lengthM: 6),
        const Budget(maxTotal: 1000, flexible: false),
      );
      expect(w.budgetFit, 0.40);
    });

    test('flexible budget in a large room uses defaults', () {
      final w = ScoringWeights.forContext(
        const Room(widthM: 4, lengthM: 6),
        const Budget(maxTotal: 1000, flexible: true),
      );
      expect(w.roomCompatibility, 0.35);
      expect(w.budgetFit, 0.30);
    });
  });

  group('RecommendationScorer', () {
    const scorer = RecommendationScorer();
    final ctx = ScoringContext(
      room: const Room(widthM: 4, lengthM: 6, roomType: RoomType.bedroom),
      budget: const Budget(maxTotal: 1800),
      style: const StylePreferences(preferred: ['modern']),
      categoryCeilings: const {RecommendationCategory.bed: 720},
    );

    CatalogProduct bed({required double w, required double d, double price = 500}) =>
        CatalogProduct(
          productId: 'b',
          title: 'bed',
          category: RecommendationCategory.bed,
          price: price,
          widthCm: w,
          depthCm: d,
          styleTags: const ['modern'],
        );

    test('a fitting, in-budget, in-style product scores well', () {
      final b = scorer.score(bed(w: 90, d: 190), ctx);
      expect(b.room, greaterThan(0.5));
      expect(b.total, greaterThan(50));
    });

    test('an oversized product gets zero room compatibility', () {
      final b = scorer.score(bed(w: 700, d: 700), ctx);
      expect(b.room, 0.0);
    });

    test('a product over the category ceiling loses budget fit', () {
      final cheap = scorer.score(bed(w: 90, d: 190, price: 300), ctx);
      final pricey = scorer.score(bed(w: 90, d: 190, price: 1600), ctx);
      expect(cheap.budget, greaterThan(pricey.budget));
    });
  });
}
