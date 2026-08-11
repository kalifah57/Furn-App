import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/spatial/ar_spatial_engine.dart';
import 'package:furn_app/domain_engine/spatial/furniture_package.dart';
import 'package:furn_app/domain_engine/spatial/placement_solver.dart';
import 'package:furn_app/domain_engine/spatial/replacement_finder.dart';
import 'package:furn_app/shared/models/models.dart';

/// The sandbox domain must be a pure function of its inputs: same catalog, same
/// room, same scene — every run, or a saved design would not reopen the same way.
void main() {
  const composer = PackageComposer();
  const solver = PlacementSolver();
  const finder = ReplacementFinder();
  const room = RoomSpace(widthCm: 380, lengthCm: 420);

  CatalogProduct p({
    required String id,
    required RecommendationCategory category,
    String subcategory = '',
    required double w,
    required double d,
    required double h,
    double price = 500,
    List<String> style = const [],
    List<String> colors = const [],
  }) =>
      CatalogProduct(
        productId: id,
        title: id,
        category: category,
        subcategory: subcategory,
        styleTags: style,
        colorTags: colors,
        widthCm: w,
        depthCm: d,
        heightCm: h,
        price: price,
        modelGlbUrl: 'models/glb/$id.glb',
        arReady: true,
      );

  final bed = p(id: 'bed', category: RecommendationCategory.bed, w: 160, d: 210, h: 110);
  final wardrobe =
      p(id: 'ward', category: RecommendationCategory.storage, w: 120, d: 60, h: 220);
  final rug = p(id: 'rug', category: RecommendationCategory.rug, w: 200, d: 300, h: 2);
  final pendant = p(
      id: 'pend', category: RecommendationCategory.lamp,
      subcategory: 'pendant', w: 40, d: 40, h: 30);

  group('placement solver', () {
    test('places every piece of a normal package', () {
      final plan = solver.solve([bed, wardrobe, rug, pendant], room);
      expect(plan.isComplete, isTrue);
      expect(plan.placements.length, 4);
    });

    test('no two floor pieces overlap', () {
      final plan = solver.solve([bed, wardrobe], room);
      final a = plan.byProductId('bed')!;
      final b = plan.byProductId('ward')!;
      expect(a.overlaps(b), isFalse);
    });

    test('every piece stays inside the room', () {
      final plan = solver.solve([bed, wardrobe, rug], room);
      for (final e in plan.placements) {
        expect(e.minX, greaterThanOrEqualTo(-room.widthCm / 2 - 0.01));
        expect(e.maxX, lessThanOrEqualTo(room.widthCm / 2 + 0.01));
        expect(e.minZ, greaterThanOrEqualTo(-room.lengthCm / 2 - 0.01));
        expect(e.maxZ, lessThanOrEqualTo(room.lengthCm / 2 + 0.01));
      }
    });

    test('a ceiling fixture sits at the room centre and blocks nothing', () {
      final plan = solver.solve([pendant, bed], room);
      final lamp = plan.byProductId('pend')!;
      expect(lamp.xCm, 0);
      expect(lamp.zCm, 0);
      expect(plan.isComplete, isTrue);
    });

    test('a piece too large for the room is reported, never dropped silently', () {
      final huge =
          p(id: 'huge', category: RecommendationCategory.sofa, w: 500, d: 300, h: 90);
      final plan = solver.solve([huge], room);
      expect(plan.placements, isEmpty);
      expect(plan.unplaced.map((e) => e.productId), ['huge']);
    });

    test('identical inputs give byte-identical layouts', () {
      final a = solver.solve([bed, wardrobe, rug, pendant], room);
      final b = solver.solve([bed, wardrobe, rug, pendant], room);
      expect(a.placements.map((e) => '${e.product.productId}:${e.xCm}:${e.zCm}:${e.rotationDeg}'),
          b.placements.map((e) => '${e.product.productId}:${e.xCm}:${e.zCm}:${e.rotationDeg}'));
    });

    test('input order does not change the layout', () {
      final a = solver.solve([bed, wardrobe, rug, pendant], room);
      final b = solver.solve([pendant, rug, wardrobe, bed], room);
      expect(a.placements.map((e) => '${e.product.productId}:${e.xCm}:${e.zCm}'),
          b.placements.map((e) => '${e.product.productId}:${e.xCm}:${e.zCm}'));
    });
  });

  group('package composer', () {
    final catalog = [bed, wardrobe, rug, pendant];

    test('covers the bedroom template', () {
      final pkg = composer.compose(
          catalog: catalog, roomType: RoomType.bedroom, budget: 5000);
      expect(pkg.items.map((e) => e.category),
          containsAll([RecommendationCategory.bed, RecommendationCategory.storage]));
    });

    test('never exceeds the budget', () {
      final pkg = composer.compose(
          catalog: catalog, roomType: RoomType.bedroom, budget: 1200);
      expect(pkg.totalPrice, lessThanOrEqualTo(1200));
    });

    test('is deterministic across runs', () {
      final a = composer.compose(
          catalog: catalog, roomType: RoomType.bedroom, budget: 3000);
      final b = composer.compose(
          catalog: catalog, roomType: RoomType.bedroom, budget: 3000);
      expect(a.items.map((e) => e.productId), b.items.map((e) => e.productId));
    });

    test('a product without a 3D model still enters the 2D scene', () {
      // المعاينة مسقط علوي: شرطها المقاسات لا النموذج. اشتراط النموذج كان
      // سيُفرغها بالكامل على الكتالوج الحقيقي (arReady: false في مُدخِل آيكيا).
      const noModel = CatalogProduct(
        productId: 'real_no_model',
        title: 'real_no_model',
        category: RecommendationCategory.bed,
        widthCm: 100,
        depthCm: 200,
        heightCm: 100,
        price: 1,
      );
      final pkg = composer.compose(
          catalog: [noModel, bed], roomType: RoomType.bedroom, budget: 5000);
      expect(pkg.items.map((e) => e.productId), contains('real_no_model'));
    });

    test('a product without dimensions is skipped — nothing to draw', () {
      const ghost = CatalogProduct(
        productId: 'dimensionless',
        title: 'dimensionless',
        category: RecommendationCategory.bed,
        widthCm: 0,
        depthCm: 0,
        heightCm: 0,
        price: 1,
      );
      final pkg = composer.compose(
          catalog: [ghost, bed], roomType: RoomType.bedroom, budget: 5000);
      expect(pkg.items.map((e) => e.productId), isNot(contains('dimensionless')));
    });
  });

  group('replacement finder', () {
    final cheapBed = p(
        id: 'bed_cheap', category: RecommendationCategory.bed,
        w: 150, d: 200, h: 100, price: 300, style: ['modern']);
    final richBed = p(
        id: 'bed_rich', category: RecommendationCategory.bed,
        w: 155, d: 205, h: 105, price: 5000, style: ['modern']);
    final hugeBed = p(
        id: 'bed_huge', category: RecommendationCategory.bed,
        w: 220, d: 260, h: 120, price: 400);
    final sofa = p(id: 'sofa', category: RecommendationCategory.sofa,
        w: 150, d: 90, h: 85, price: 300);

    late Placement slot;
    setUp(() => slot = solver.solve([bed], room).byProductId('bed')!);

    List<ReplacementCandidate> find({
      required double remaining,
      StylePreferences style = const StylePreferences(),
      List<CatalogProduct>? catalog,
    }) =>
        finder.alternativesFor(
          slot: slot,
          catalog: catalog ?? [bed, cheapBed, richBed, hugeBed, sofa],
          room: room,
          others: [slot],
          remainingBudget: remaining,
          style: style,
        );

    test('offers a same-category alternative that fits the slot', () {
      final out = find(remaining: 0);
      expect(out.map((e) => e.product.productId), contains('bed_cheap'));
    });

    test('never offers a different category', () {
      expect(find(remaining: 5000).map((e) => e.product.category),
          everyElement(RecommendationCategory.bed));
    });

    test('rejects anything larger than the slot', () {
      expect(find(remaining: 5000).map((e) => e.product.productId),
          isNot(contains('bed_huge')));
    });

    test('the freed budget counts: removing a 500 bed funds a 500 replacement', () {
      // Remaining is 0, but the removed bed returns its 500 to the pot.
      final out = find(remaining: 0);
      expect(out.map((e) => e.product.productId), contains('bed_cheap'));
      // 5000 is still out of reach on a 0 + 500 ceiling.
      expect(out.map((e) => e.product.productId), isNot(contains('bed_rich')));
    });

    test('a bigger remaining budget unlocks pricier options', () {
      expect(find(remaining: 4600).map((e) => e.product.productId),
          contains('bed_rich'));
    });

    test('style matches rank above cheaper mismatches', () {
      const style = StylePreferences(preferred: ['modern']);
      final out = find(remaining: 5000, style: style);
      expect(out.first.product.styleTags, contains('modern'));
    });

    test('is deterministic across runs', () {
      final a = find(remaining: 5000).map((e) => e.product.productId).toList();
      final b = find(remaining: 5000).map((e) => e.product.productId).toList();
      expect(a, b);
    });

    test('price delta is reported against the removed item', () {
      final c = find(remaining: 5000)
          .firstWhere((e) => e.product.productId == 'bed_cheap');
      expect(c.priceDelta, 300 - 500);
      expect(c.isCheaper, isTrue);
    });
  });

  group('real catalog end to end', () {
    late List<CatalogProduct> catalog;

    setUpAll(() {
      catalog = (jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>()
          .map(CatalogProduct.fromJson)
          .toList();
    });

    test('a real bedroom package places completely in a real room', () {
      final pkg = composer.compose(
          catalog: catalog, roomType: RoomType.bedroom, budget: 4000);
      expect(pkg.items, isNotEmpty);
      final plan = solver.solve(pkg.items, room);
      expect(plan.unplaced, isEmpty);
      expect(plan.totalPrice, lessThanOrEqualTo(4000));
    });

    test('a real living-room package places completely', () {
      final pkg = composer.compose(
          catalog: catalog, roomType: RoomType.livingRoom, budget: 6000);
      final plan = solver.solve(pkg.items, room);
      expect(plan.unplaced, isEmpty);
    });

    test('no two floor pieces of a real package overlap', () {
      final pkg = composer.compose(
          catalog: catalog, roomType: RoomType.livingRoom, budget: 6000);
      final placed = solver.solve(pkg.items, room).placements
          .where((e) =>
              mountOf(e.product) == ArMount.floor &&
              e.product.category != RecommendationCategory.rug)
          .toList();
      for (var i = 0; i < placed.length; i++) {
        for (var j = i + 1; j < placed.length; j++) {
          expect(placed[i].overlaps(placed[j]), isFalse,
              reason: '${placed[i].product.productId} overlaps '
                  '${placed[j].product.productId}');
        }
      }
    });

    test('the whole pipeline is reproducible', () {
      String render(RoomType t) {
        final pkg = composer.compose(catalog: catalog, roomType: t, budget: 6000);
        return solver
            .solve(pkg.items, room)
            .placements
            .map((e) => '${e.product.productId}@${e.xCm},${e.zCm},${e.rotationDeg}')
            .join('|');
      }

      expect(render(RoomType.livingRoom), render(RoomType.livingRoom));
      expect(render(RoomType.bedroom), render(RoomType.bedroom));
    });
  });
}
