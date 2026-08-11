import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/features/catalog/data/ikea_catalog_ingest.dart';
import 'package:furn_app/shared/models/models.dart';

/// الكتالوج الحقيقي (`ikea_ksa.json`) عبر نفس الابتلاع الذي يستعمله التطبيق —
/// مزامنة فاسدة تُفشل CI قبل أن تصل مستخدمًا. الأرقام المثبّتة هنا محسوبة من
/// الملف الفعلي (دفعة ٢٠٢٦-٠٨-١٠، sha256 83e17aa4…): تغيّر الدفعة يغيّرها معها
/// **عن قصد** — راجعها مع المانيفست، لا تُرخِ الاختبار.
void main() {
  final file = File('assets/catalog/ikea_ksa.json');

  group(
    'the real catalogue through the real ingest',
    () {
      late IngestResult result;
      setUpAll(() {
        final records = jsonDecode(file.readAsStringSync()) as List;
        result = const IkeaCatalogIngest().run(records);
      });

      test('47 of 50 survive; the 3 drops are category-floor hygiene', () {
        expect(result.keptCount, 47,
            reason: 'histogram: ${result.dropHistogram}');
        expect(result.dropHistogram, {DropReason.belowCategoryFloor: 3});
      });

      test('every kept product lands in a real engine category — never other',
          () {
        // side_table/shelving كانتا تسقطان إلى «أخرى» فتختفي 9 قطع من كل خطة.
        final others = result.products
            .where((p) => p.category == RecommendationCategory.other)
            .map((p) => '${p.productId}:${p.subcategory}');
        expect(others, isEmpty);
      });

      test('side_table folds into table, shelving into storage', () {
        CatalogProduct by(String id) =>
            result.products.firstWhere((p) => p.productId == id);
        expect(by('90388978').category, RecommendationCategory.table);
        expect(by('00278578').category, RecommendationCategory.storage);
      });

      test('the axis contract holds on real data: length_cm is depth', () {
        // STRANDMON: آيكيا تنشر width 82 / length (Depth) 96 — قلبهما يدوّر كل
        // قطعة 90° ويكذب فحص «تدخل غرفتك».
        final strandmon =
            result.products.firstWhere((p) => p.productId == '50613163');
        expect(strandmon.widthCm, 82);
        expect(strandmon.depthCm, 96);
      });

      test('every kept product is engine-ready, KSA-linked, and pictured', () {
        for (final p in result.products) {
          expect(p.productId, isNotEmpty);
          expect(p.widthCm, greaterThan(0));
          expect(p.depthCm, greaterThan(0));
          expect(p.heightCm, greaterThan(0));
          expect(p.price, greaterThan(0));
          expect(p.productUrl, startsWith('https://www.ikea.com/sa/en/'));
          expect(p.imageUrl, isNotEmpty,
              reason: '${p.productId} بلا صورة — بطاقات X5 تعتمد عليها');
        }
      });

      test('the composition gap is known: exactly one bed, no rug, no lamp',
          () {
        // ليست رغبة بل واقع الدفعة — يوثّقها الاختبار كي يحتفل CI يوم تسدّها
        // دفعة توريد جديدة (يكسر هذا الاختبار عمدًا فتُحدَّث أرقامه).
        Iterable<CatalogProduct> of(RecommendationCategory c) =>
            result.products.where((p) => p.category == c);
        expect(of(RecommendationCategory.bed).length, 1);
        expect(of(RecommendationCategory.rug), isEmpty);
        expect(of(RecommendationCategory.lamp), isEmpty);
      });
    },
    skip: file.existsSync()
        ? false
        : 'assets/catalog/ikea_ksa.json not synced yet',
  );
}
