import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../shared/models/catalog_product.dart';
import '../../../shared/services/catalog_repository.dart';
import 'ikea_catalog_ingest.dart';

/// مصدر الكتالوج الحقيقي: أصل `ikea_ksa.json` (بيانات مصدرٍ خام، بمخطط آيكيا)
/// مُمرَّرًا عبر [IkeaCatalogIngest] المتحقِّق — لا يصل المحرّك سجلٌّ لم يُفحص.
///
/// هذا غير [AssetCatalogRepository]: ذاك يقرأ ملفًا بصيغة المحرّك نفسها
/// (كتالوج المحاكاة)، وهذا يقرأ صيغة المصدر ويحوّلها. الاستبدال بينهما سطرٌ
/// واحد في `catalogRepositoryProvider`.
class IkeaAssetCatalogRepository implements CatalogRepository {
  const IkeaAssetCatalogRepository({
    this.assetPath = 'assets/catalog/ikea_ksa.json',
    this.ingest = const IkeaCatalogIngest(),
  });

  final String assetPath;
  final IkeaCatalogIngest ingest;

  @override
  Future<Result<List<CatalogProduct>>> loadProducts() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      final records = decoded is List ? decoded : const <dynamic>[];
      final result = ingest.run(records);

      // مصدرٌ موجود أُسقط بالكامل ≠ كتالوج فارغ مشروع — هذا ملف معطوب أو مخطط
      // تغيّر، والفشل الصريح خيرٌ من تطبيقٍ «يعمل» بلا قطعة واحدة.
      if (records.isNotEmpty && result.products.isEmpty) {
        return Err(UnknownFailure(
            'كتالوج آيكيا موجود لكن لم ينجُ منه سجلّ واحد '
            '(${result.dropHistogram}).'));
      }
      return Ok(result.products);
    } catch (e) {
      return Err(UnknownFailure('تعذّر تحميل كتالوج آيكيا.', e));
    }
  }
}
