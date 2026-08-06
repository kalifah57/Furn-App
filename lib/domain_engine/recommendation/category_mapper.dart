import '../../shared/models/enums.dart';

/// يحوّل نص نوع العنصر المطلوب (من الإدخال/الاستخراج) إلى فئة كتالوج.
/// حتمي، ويدعم مفردات عربية وإنجليزية شائعة.
///
/// يسقط على [RecommendationCategory.other] للمجهول — وهو سلوك مقصود للمستدعين
/// القدامى، لكنه يخفي الفرق بين «فئة أخرى» و«لا أفهم هذا الطلب». من يحتاج ذلك
/// الفرق يستعمل [mapTypeToCategoryOrNull].
RecommendationCategory mapTypeToCategory(String rawType) =>
    mapTypeToCategoryOrNull(rawType) ?? RecommendationCategory.other;

/// مثل [mapTypeToCategory] لكن يُرجع `null` للنوع المجهول بدل ابتلاعه في
/// `other` — فيستطيع المستدعي أن يعلنه فجوة بدل أن يعرضه «ناقص: أخرى».
RecommendationCategory? mapTypeToCategoryOrNull(String rawType) {
  final t = rawType.trim().toLowerCase();
  bool has(List<String> keys) => keys.any(t.contains);

  if (has(['bed', 'سرير'])) return RecommendationCategory.bed;
  if (has(['sofa', 'couch', 'armchair', 'chair', 'كنب', 'كرسي', 'أريكة'])) {
    return RecommendationCategory.sofa;
  }
  if (has(['rug', 'carpet', 'سجاد', 'سجادة'])) return RecommendationCategory.rug;
  if (has(['table', 'desk', 'طاولة', 'مكتب'])) return RecommendationCategory.table;
  if (has(['lamp', 'light', 'إضاء', 'مصباح', 'ثريا'])) {
    return RecommendationCategory.lamp;
  }
  if (has(['storage', 'wardrobe', 'dresser', 'closet', 'تخزين', 'خزانة', 'دولاب'])) {
    return RecommendationCategory.storage;
  }
  return null;
}
