import '../../shared/models/models.dart';

/// **باقة أثاث** — مجموعة القطع التي تُفرش في المشهد دفعة واحدة («طقم الصالة»).
/// كيان قيمة نقي: لا يعرف شيئًا عن المواضع، وهي مسؤولية [PlacementSolver].
class FurniturePackage {
  const FurniturePackage({required this.items, required this.roomType});

  final List<CatalogProduct> items;
  final RoomType roomType;

  double get totalPrice => items.fold<double>(0, (s, p) => s + p.price);
  bool get isEmpty => items.isEmpty;
}

/// يؤلّف الباقة من الكتالوج بقواعد حتمية — لا عشوائية ولا اعتماد على ترتيب
/// المدخل: نفس (الكتالوج، نوع الغرفة، الميزانية) يعطي نفس الباقة دائمًا.
class PackageComposer {
  const PackageComposer();

  /// القطع المتوقّعة لكل نوع غرفة، بترتيب الأهمية.
  static List<RecommendationCategory> templateFor(RoomType type) =>
      switch (type) {
        RoomType.bedroom => const [
            RecommendationCategory.bed,
            RecommendationCategory.storage,
            RecommendationCategory.rug,
            RecommendationCategory.lamp,
          ],
        RoomType.livingRoom || RoomType.guestRoom => const [
            RecommendationCategory.sofa,
            RecommendationCategory.table,
            RecommendationCategory.rug,
            RecommendationCategory.storage,
            RecommendationCategory.lamp,
          ],
        RoomType.other => const [
            RecommendationCategory.sofa,
            RecommendationCategory.table,
            RecommendationCategory.lamp,
          ],
      };

  /// يختار قطعة واحدة لكل فئة ضمن الميزانية، بالأولوية أوّلًا.
  ///
  /// الفئات تُستهلك بالترتيب، وكل فئة تأخذ أرخص قطعة صالحة تُبقي المجموع ضمن
  /// الميزانية — بذلك تحصل القطع الأهم على نصيبها قبل نفادها.
  FurniturePackage compose({
    required List<CatalogProduct> catalog,
    required RoomType roomType,
    required double budget,
  }) {
    final chosen = <CatalogProduct>[];
    var spent = 0.0;

    for (final category in templateFor(roomType)) {
      final options = catalog
          .where((p) =>
              p.category == category &&
              p.isAvailable &&
              // المسقط العلوي يحتاج مقاسات لا نموذجًا — اشتراط النموذج كان
              // سيُفرغ المعاينة على الكتالوج الحقيقي (arReady: false).
              p.hasFootprint &&
              (budget <= 0 || spent + p.price <= budget))
          .toList()
        // ترتيب كلّي: السعر ثم المعرّف — فرز Dart غير مضمون الاستقرار.
        ..sort((a, b) {
          final byPrice = a.price.compareTo(b.price);
          return byPrice != 0 ? byPrice : a.productId.compareTo(b.productId);
        });

      if (options.isEmpty) continue;
      chosen.add(options.first);
      spent += options.first.price;
    }

    return FurniturePackage(items: chosen, roomType: roomType);
  }
}
