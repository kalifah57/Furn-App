import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/shared/models/models.dart';

/// "Replace" must be a decision, not a list: the current piece plus up to three
/// genuinely better ones — highest-scored within the budget and the room — each
/// carrying why it's preferable and what it costs. These tests hold that
/// contract, and pin the pros/cons arithmetic on a controlled catalogue.
void main() {
  FurnishingProject bedroom({double budget = 5000}) => FurnishingProject(
        projectId: 'p',
        room: const Room(widthM: 5, lengthM: 5, roomType: RoomType.bedroom),
        budget: Budget(maxTotal: budget),
        items: const RequestedItems(
          essential: [RequestedItem(type: 'أريكة')],
        ),
      );

  group('the pros and cons vs the current piece', () {
    const catalog = <CatalogProduct>[
      CatalogProduct(
          productId: 'cur',
          title: 'أريكة حالية',
          category: RecommendationCategory.sofa,
          widthCm: 200,
          depthCm: 90,
          heightCm: 85,
          price: 1000,
          ratingOptional: 4.0),
      CatalogProduct(
          productId: 'cheap',
          title: 'أريكة أوفر',
          category: RecommendationCategory.sofa,
          widthCm: 190,
          depthCm: 85,
          heightCm: 80,
          price: 700,
          ratingOptional: 4.5),
      CatalogProduct(
          productId: 'pricey',
          title: 'أريكة أغلى',
          category: RecommendationCategory.sofa,
          widthCm: 210,
          depthCm: 90,
          heightCm: 85,
          price: 1300,
          ratingOptional: 3.5),
    ];

    PlanWorkspace ws() =>
        PlanWorkspace(project: bedroom(), catalog: catalog);

    test('a cheaper alternative is flagged as saving money', () {
      final alts = ws().betterAlternatives(RecommendationCategory.sofa, 'cur');
      final cheap = alts.firstWhere((o) => o.product.productId == 'cheap');
      expect(cheap.pros, contains('أوفر بـ 300 ريال'));
      expect(cheap.pros, contains('تقييم أعلى (4.5)'));
    });

    test('a pricier alternative names the extra cost as a con', () {
      final alts = ws().betterAlternatives(RecommendationCategory.sofa, 'cur');
      final pricey = alts.firstWhere((o) => o.product.productId == 'pricey');
      expect(pricey.cons, contains('أغلى بـ 300 ريال'));
      expect(pricey.cons, contains('تقييم أقل'));
    });

    test('the current piece is never offered as its own alternative', () {
      final alts = ws().betterAlternatives(RecommendationCategory.sofa, 'cur');
      expect(alts.any((o) => o.product.productId == 'cur'), isFalse);
    });
  });

  group('the contract, against the real catalogue', () {
    late List<CatalogProduct> catalog;
    setUpAll(() {
      catalog =
          (jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>()
              .map(CatalogProduct.fromJson)
              .toList();
    });

    String aSofaId() => catalog
        .firstWhere((p) => p.category == RecommendationCategory.sofa)
        .productId;

    test('at most three, all in-category, available, and room-fitting', () {
      final ws = PlanWorkspace(project: bedroom(), catalog: catalog);
      final alts = ws.betterAlternatives(RecommendationCategory.sofa, aSofaId());
      expect(alts.length, lessThanOrEqualTo(3));
      for (final o in alts) {
        expect(o.product.category, RecommendationCategory.sofa);
        expect(o.product.isAvailable, isTrue);
        expect(o.product.productId, isNot(aSofaId()));
      }
    });

    test('a piece that cannot be afforded alone is excluded', () {
      final ws = PlanWorkspace(project: bedroom(budget: 300), catalog: catalog);
      final alts = ws.betterAlternatives(RecommendationCategory.sofa, aSofaId());
      expect(alts.every((o) => o.product.price <= 300), isTrue);
    });

    test('the ranking is deterministic', () {
      final ws = PlanWorkspace(project: bedroom(), catalog: catalog);
      List<String> ids() => ws
          .betterAlternatives(RecommendationCategory.sofa, aSofaId())
          .map((o) => o.product.productId)
          .toList();
      expect(ids(), ids());
    });
  });
}
