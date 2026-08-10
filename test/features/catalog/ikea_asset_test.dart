import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/features/catalog/data/ikea_catalog_ingest.dart';

/// When the real IKEA asset is present (synced by `sync-catalog.yml`), run it
/// through the same ingestion the app uses — so a bad sync fails CI instead of
/// reaching users. Skips cleanly until the asset lands; the inline-fixture
/// tests in `ikea_catalog_ingest_test` cover the logic meanwhile.
void main() {
  final file = File('assets/catalog/ikea_ksa.json');

  test(
    'the real catalogue survives ingestion with usable rows',
    () {
      final records = jsonDecode(file.readAsStringSync()) as List;
      final result = const IkeaCatalogIngest().run(records);

      // Something usable must survive — a sync that drops everything is a
      // broken sync, not an empty catalogue.
      expect(result.keptCount, greaterThan(0),
          reason: 'ingestion dropped every record: ${result.dropHistogram}');

      // Every kept product is engine-ready: a real footprint and an id.
      for (final p in result.products) {
        expect(p.productId, isNotEmpty);
        expect(p.widthCm, greaterThan(0));
        expect(p.depthCm, greaterThan(0));
        expect(p.heightCm, greaterThan(0));
      }

      // The catalogue as a whole is priced (null-price rows were dropped).
      final total = result.products.fold<double>(0, (s, p) => s + p.price);
      expect(total, greaterThan(0));
    },
    skip: file.existsSync()
        ? false
        : 'assets/catalog/ikea_ksa.json not synced yet',
  );
}
