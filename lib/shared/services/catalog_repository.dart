import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/errors/failure.dart';
import '../../core/errors/result.dart';
import '../models/catalog_product.dart';

/// واجهة مصدر الكتالوج (catalog_strategy.md).
abstract interface class CatalogRepository {
  Future<Result<List<CatalogProduct>>> loadProducts();
}

/// تنفيذ الـ MVP: كتالوج ثابت من ملف JSON داخل الأصول (القرار G2).
/// يُستبدل لاحقًا بـ Firestore دون تغيير المستدعي (ADR-0001 §7).
class AssetCatalogRepository implements CatalogRepository {
  const AssetCatalogRepository({this.assetPath = 'assets/catalog/catalog.json'});

  final String assetPath;

  @override
  Future<Result<List<CatalogProduct>>> loadProducts() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      final list = decoded is List
          ? decoded
          : (decoded is Map ? decoded['products'] as List? ?? const [] : const []);
      final products = list
          .whereType<Map>()
          .map((e) => CatalogProduct.fromJson(e.cast<String, dynamic>()))
          .toList();
      return Ok(products);
    } catch (e) {
      return Err(UnknownFailure('تعذّر تحميل الكتالوج.', e));
    }
  }
}

/// تنفيذ في الذاكرة (للاختبارات والمعاينة السريعة).
class InMemoryCatalogRepository implements CatalogRepository {
  const InMemoryCatalogRepository(this.products);
  final List<CatalogProduct> products;

  @override
  Future<Result<List<CatalogProduct>>> loadProducts() async => Ok(products);
}
