import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/spatial/ar_spatial_engine.dart';
import 'package:furn_app/shared/models/models.dart';

/// Evals for the AR spatial gate: only products that genuinely fit the scanned
/// room may reach the camera. Pure domain — deterministic, no Flutter bindings.
///
/// Precise numeric assertions run on hand-built fixtures so they stay stable as
/// the catalog evolves; the real 48-product catalog is then run through the same
/// engine as a coverage/integrity sweep.
void main() {
  const engine = ArSpatialEngine();

  // The scanned room from the brief: 400 x 400 cm, standard 280 cm ceiling.
  const room = RoomSpace(widthCm: 400, lengthCm: 400);

  CatalogProduct product({
    required String id,
    required RecommendationCategory category,
    String subcategory = '',
    required double w,
    required double d,
    required double h,
    bool arReady = true,
  }) =>
      CatalogProduct(
        productId: id,
        title: id,
        category: category,
        subcategory: subcategory,
        widthCm: w,
        depthCm: d,
        heightCm: h,
        modelGlbUrl: arReady ? 'models/glb/$id.glb' : '',
        arReady: arReady,
      );

  group('single-product gate', () {
    test('a normally-sized sofa fits a 400x400 room', () {
      final sofa = product(
          id: 'sofa_ok', category: RecommendationCategory.sofa,
          w: 200, d: 90, h: 85);
      final r = engine.evaluate(sofa, room);
      expect(r.verdict, ArFitVerdict.fits);
      expect(r.canPlace, isTrue);
      expect(r.footprintCm2, 200 * 90);
    });

    test('a product wider than the room is rejected as tooLarge', () {
      final huge = product(
          id: 'sofa_huge', category: RecommendationCategory.sofa,
          w: 420, d: 90, h: 85);
      expect(engine.evaluate(huge, room).verdict, ArFitVerdict.tooLarge);
    });

    test('a product fits when rotated 90 degrees', () {
      // 380 deep would not fit "direct" against a 400x400 room only if the other
      // axis blew past it; rotation must be considered, not just direct fit.
      final narrowRoom = const RoomSpace(widthCm: 200, lengthCm: 400);
      final long = product(
          id: 'table_long', category: RecommendationCategory.table,
          w: 380, d: 90, h: 75);
      expect(engine.fitsFootprint(long, narrowRoom), isTrue,
          reason: 'rotating 380x90 into a 200x400 room must be allowed');
      expect(engine.evaluate(long, narrowRoom).verdict, ArFitVerdict.fits);
    });

    test('a product taller than the ceiling is rejected as tooTall', () {
      final tower = product(
          id: 'ward_tall', category: RecommendationCategory.storage,
          w: 100, d: 60, h: 300);
      expect(engine.evaluate(tower, room).verdict, ArFitVerdict.tooTall);
    });

    test('a product without a 3D model never reaches AR', () {
      final noModel = product(
          id: 'sofa_nomodel', category: RecommendationCategory.sofa,
          w: 200, d: 90, h: 85, arReady: false);
      expect(engine.evaluate(noModel, room).verdict, ArFitVerdict.noModel);
    });

    test('an unmeasured room blocks everything', () {
      final sofa = product(
          id: 'sofa_ok', category: RecommendationCategory.sofa,
          w: 200, d: 90, h: 85);
      const unmeasured = RoomSpace(widthCm: 0, lengthCm: 0);
      expect(engine.evaluate(sofa, unmeasured).verdict, ArFitVerdict.roomUnknown);
    });
  });

  group('walkway clearance', () {
    // A long room (400 x 800) keeps the occupancy rule out of the way so the
    // walkway boundary can be probed on its own: short side is 400cm, and the
    // 65% floor budget (208000 cm2) is far above these footprints.
    const longRoom = RoomSpace(widthCm: 400, lengthCm: 800);

    test('walkway is measured against the piece\'s minor side', () {
      // Minor side 330 in a 400cm short side -> 70cm clear, under the minimum.
      final deep = product(
          id: 'sect_deep', category: RecommendationCategory.sofa,
          w: 400, d: 330, h: 85);
      final r = engine.evaluate(deep, longRoom);
      expect(r.clearSpanCm, 400 - 330);
      expect(r.verdict, ArFitVerdict.blocksWalkway);
    });

    test('exactly 75cm of clearance is accepted (boundary is inclusive)', () {
      final exact = product(
          id: 'sect_exact', category: RecommendationCategory.sofa,
          w: 400, d: 325, h: 85);
      final r = engine.evaluate(exact, longRoom);
      expect(r.clearSpanCm, kWalkwayCm);
      expect(r.verdict, ArFitVerdict.fits);
    });
  });

  group('cumulative remaining space', () {
    final bed = product(
        id: 'bed_king', category: RecommendationCategory.bed,
        w: 200, d: 210, h: 120);
    final wardrobe = product(
        id: 'ward_big', category: RecommendationCategory.storage,
        w: 200, d: 60, h: 220);
    final desk = product(
        id: 'desk', category: RecommendationCategory.table,
        w: 120, d: 60, h: 75);

    test('an empty room offers the full placeable area', () {
      final r = engine.evaluate(desk, room);
      // 400x400 = 160000 cm2; 65% placeable = 104000; minus the desk footprint.
      expect(r.remainingAreaCm2, 400 * 400 * kMaxFloorOccupancy - 120 * 60);
    });

    test('already-placed pieces shrink what still fits', () {
      final withBed = engine.evaluate(desk, room, placed: [bed]);
      final empty = engine.evaluate(desk, room);
      expect(withBed.remainingAreaCm2, lessThan(empty.remainingAreaCm2));
      expect(withBed.verdict, ArFitVerdict.fits);
    });

    test('filling the room past 65% occupancy rejects the next piece', () {
      // bed 42000 + wardrobe 12000 = 54000. Placeable is 104000, so a second
      // bed (42000) still fits at 96000 but a third (138000) cannot.
      final placed = [bed, wardrobe, bed];
      final r = engine.evaluate(bed, room, placed: placed);
      expect(r.verdict, ArFitVerdict.noRemainingSpace);
      expect(r.remainingAreaCm2, lessThan(0));
    });

    test('viewableInAr shrinks as the room fills up', () {
      final catalog = [bed, wardrobe, desk];
      final empty = engine.viewableInAr(catalog, room);
      final crowded = engine.viewableInAr(catalog, room, placed: [bed, bed]);
      expect(empty.length, 3);
      expect(crowded.length, lessThan(empty.length));
    });
  });

  group('mounting: not everything stands on the floor', () {
    test('a rug does not consume circulation space', () {
      final rug = product(
          id: 'rug_big', category: RecommendationCategory.rug,
          w: 300, d: 400, h: 2);
      // Minor side 300 would leave only 100cm... but a rug is walked on.
      expect(engine.evaluate(rug, room).verdict, ArFitVerdict.fits);
    });

    test('a rug placed in the room does not reduce remaining area', () {
      final rug = product(
          id: 'rug_big', category: RecommendationCategory.rug,
          w: 300, d: 400, h: 2);
      final desk = product(
          id: 'desk', category: RecommendationCategory.table,
          w: 120, d: 60, h: 75);
      expect(engine.evaluate(desk, room, placed: [rug]).remainingAreaCm2,
          engine.evaluate(desk, room).remainingAreaCm2);
    });

    test('a ceiling fixture consumes no floor and ignores the walkway', () {
      final pendant = product(
          id: 'lamp_pendant', category: RecommendationCategory.lamp,
          subcategory: 'pendant', w: 40, d: 40, h: 30);
      expect(engine.evaluate(pendant, room).verdict, ArFitVerdict.fits);
      expect(mountOf(pendant), ArMount.ceiling);
    });

    test('a ceiling fixture hanging below head height is rejected', () {
      final lowChandelier = product(
          id: 'chandelier_low', category: RecommendationCategory.lamp,
          subcategory: 'chandelier', w: 60, d: 60, h: 120);
      // 280 ceiling - 120 drop = 160cm clear, under the 200cm headroom minimum.
      expect(engine.evaluate(lowChandelier, room).verdict,
          ArFitVerdict.lowHeadroom);
    });

    test('a table lamp sits on furniture, not the floor', () {
      final tableLamp = product(
          id: 'lamp_table', category: RecommendationCategory.lamp,
          subcategory: 'table_lamp', w: 20, d: 20, h: 45);
      expect(mountOf(tableLamp), ArMount.tabletop);
      final bed = product(
          id: 'bed_king', category: RecommendationCategory.bed,
          w: 200, d: 210, h: 120);
      // Placing it must not eat into the floor budget.
      final desk = product(
          id: 'desk', category: RecommendationCategory.table,
          w: 120, d: 60, h: 75);
      expect(engine.evaluate(desk, room, placed: [bed, tableLamp]).remainingAreaCm2,
          engine.evaluate(desk, room, placed: [bed]).remainingAreaCm2);
    });

    test('a floor lamp does stand on the floor', () {
      final floorLamp = product(
          id: 'lamp_floor', category: RecommendationCategory.lamp,
          subcategory: 'floor_lamp', w: 30, d: 30, h: 150);
      expect(mountOf(floorLamp), ArMount.floor);
    });
  });

  group('determinism', () {
    test('the same inputs always produce the same verdicts', () {
      final catalog = [
        product(id: 'a', category: RecommendationCategory.sofa, w: 200, d: 90, h: 85),
        product(id: 'b', category: RecommendationCategory.bed, w: 200, d: 210, h: 120),
        product(id: 'c', category: RecommendationCategory.rug, w: 300, d: 400, h: 2),
      ];
      final first = engine.evaluateAll(catalog, room).map((e) => e.verdict).toList();
      final second = engine.evaluateAll(catalog, room).map((e) => e.verdict).toList();
      expect(first, second);
    });

    test('input order is preserved in the output', () {
      final catalog = [
        product(id: 'x', category: RecommendationCategory.sofa, w: 200, d: 90, h: 85),
        product(id: 'y', category: RecommendationCategory.bed, w: 200, d: 210, h: 120),
      ];
      expect(engine.evaluateAll(catalog, room).map((e) => e.product.productId),
          ['x', 'y']);
    });
  });

  group('real catalog sweep (48 products)', () {
    late List<CatalogProduct> catalog;

    setUpAll(() {
      final raw = File('assets/catalog/catalog.json').readAsStringSync();
      catalog = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(CatalogProduct.fromJson)
          .toList();
    });

    test('the catalog parses and is non-trivial', () {
      expect(catalog.length, greaterThanOrEqualTo(30));
    });

    test('every product has real dimensions', () {
      final bad = catalog.where(
          (p) => p.widthCm <= 0 || p.depthCm <= 0 || p.heightCm <= 0);
      expect(bad, isEmpty,
          reason: 'zero dims silently break every room-fit decision');
    });

    test('every product carries an AR model and is flagged ready', () {
      final missing = catalog.where((p) => !p.hasArModel).map((p) => p.productId);
      expect(missing, isEmpty);
    });

    test('every referenced GLB file actually exists on disk', () {
      final missing = <String>[];
      for (final p in catalog) {
        final path = 'web/${p.modelGlbUrl}';
        if (!File(path).existsSync()) missing.add('${p.productId} -> $path');
      }
      expect(missing, isEmpty,
          reason: 'ar_ready must never point at a 404 in the deployed app');
    });

    test('an empty 4x4m room admits the whole catalog', () {
      // Baseline worth pinning: every single product is individually placeable
      // in an empty 16m2 room. Any future product that fails here is either
      // oversized by mistake or missing its model.
      final results = engine.evaluateAll(catalog, room);
      expect(results.where((r) => r.canPlace).length, catalog.length);
    });

    test('a tiny 150x150 room rejects roughly half the catalog', () {
      const tiny = RoomSpace(widthCm: 150, lengthCm: 150);
      final small = engine.viewableInAr(catalog, tiny);
      expect(small.length, lessThan(catalog.length));
      expect(small, isNotEmpty, reason: 'small pieces must still be offered');
      // Everything rejected here is rejected on size, not on missing data.
      for (final r in engine.evaluateAll(catalog, tiny).where((e) => !e.canPlace)) {
        expect(r.verdict,
            anyOf(ArFitVerdict.tooLarge, ArFitVerdict.blocksWalkway,
                ArFitVerdict.noRemainingSpace));
      }
    });

    test('filling the room progressively closes the AR gate', () {
      // The gate is cumulative: the same 4x4m room that admits everything when
      // empty starts refusing pieces once real furniture occupies the floor.
      final beds = catalog.where((p) => p.subcategory == 'king_bed').toList();
      final wardrobes =
          catalog.where((p) => p.subcategory == 'wardrobe').toList();
      expect(beds, isNotEmpty);
      expect(wardrobes, isNotEmpty);

      final placed = [beds.first, wardrobes.first, beds.first];
      final after = engine.evaluateAll(catalog, room, placed: placed);
      final blocked = after.where((r) => !r.canPlace).toList();

      expect(blocked, isNotEmpty,
          reason: 'a floor this full must refuse the largest pieces');
      for (final r in blocked) {
        expect(r.verdict, ArFitVerdict.noRemainingSpace);
        expect(r.remainingAreaCm2, lessThan(0));
      }
      expect(after.where((r) => r.canPlace).length, lessThan(catalog.length));
    });

    test('every blocked product reports a non-empty Arabic reason', () {
      for (final r in engine.evaluateAll(catalog, room)) {
        expect(r.reasonAr, isNotEmpty, reason: r.product.productId);
      }
    });

    test('only products cleared by the engine are handed to the AR view', () {
      final viewable = engine.viewableInAr(catalog, room);
      for (final p in viewable) {
        expect(engine.evaluate(p, room).canPlace, isTrue);
        expect(p.hasArModel, isTrue);
      }
    });
  });
}
