/// لغة التصميم — محور الستايل (docs/design/01-design-language.md §1).
///
/// Dart صرف · بلا Flutter · بلا تتبّع. **حساب صحيح بالكامل** (لا فاصلة عائمة):
/// التقارب يبقى حتميًّا ويصلح فاصلَ تعادلٍ للترتيب، لأن فرز Dart غير مستقرّ.
///
/// المبدأ: لا نُخزّن جدول تقارب مكتوبًا باليد (n² قيمة لا تُشرح)، بل نُخزّن **سمات**
/// كل ستايل ونشتقّ التقارب حسابيًّا — فكل رقم له سبب يُنطق بجملة.

enum FurnitureStyle {
  modern,
  minimal,
  classic,
  industrial,
  boho,
  majlis;

  String get arabicLabel => switch (this) {
        FurnitureStyle.modern => 'مودرن',
        FurnitureStyle.minimal => 'مينيمال',
        FurnitureStyle.classic => 'كلاسيك',
        FurnitureStyle.industrial => 'إندَستريال',
        FurnitureStyle.boho => 'بوهو',
        FurnitureStyle.majlis => 'مجلس خليجي',
      };
}

/// سمات الستايل الخمس، كلٌّ `0..4` (§1.1). ترتيبية لا كمّية — «كم عنصرًا يقع عليه
/// النظر؟» لا «كم بالضبط؟».
class StyleProfile {
  const StyleProfile({
    required this.ornament,
    required this.lineGeometry,
    required this.visualWeight,
    required this.materialRawness,
    required this.chromaLevel,
  });

  /// الزخرفة: 0 سطح أملس · 4 نقش وحفر.
  final int ornament;

  /// هندسة الخط: 0 مستقيم حادّ · 4 منحنٍ منحوت.
  final int lineGeometry;

  /// الكتلة البصرية: 0 خفيف مرفوع · 4 ثقيل ملامس للأرض.
  final int visualWeight;

  /// خشونة الخامة: 0 مصقول · 4 خام ظاهر النسيج.
  final int materialRawness;

  /// تشبّع اللون: 0 محايد باهت · 4 مشبّع جريء.
  final int chromaLevel;

  /// السمات بترتيب ثابت — عليه يُحسب التباعد.
  List<int> get traits =>
      [ornament, lineGeometry, visualWeight, materialRawness, chromaLevel];
}

/// جدول السمات (§1.2) — **مصدر الحقيقة الوحيد** للتقارب.
const Map<FurnitureStyle, StyleProfile> kStyleProfiles = {
  FurnitureStyle.modern: StyleProfile(
      ornament: 1, lineGeometry: 1, visualWeight: 2, materialRawness: 1, chromaLevel: 2),
  FurnitureStyle.minimal: StyleProfile(
      ornament: 0, lineGeometry: 0, visualWeight: 1, materialRawness: 1, chromaLevel: 1),
  FurnitureStyle.classic: StyleProfile(
      ornament: 4, lineGeometry: 4, visualWeight: 4, materialRawness: 0, chromaLevel: 3),
  FurnitureStyle.industrial: StyleProfile(
      ornament: 1, lineGeometry: 1, visualWeight: 3, materialRawness: 4, chromaLevel: 1),
  FurnitureStyle.boho: StyleProfile(
      ornament: 3, lineGeometry: 2, visualWeight: 2, materialRawness: 3, chromaLevel: 4),
  FurnitureStyle.majlis: StyleProfile(
      ornament: 4, lineGeometry: 2, visualWeight: 3, materialRawness: 0, chromaLevel: 4),
};

/// حكم التقارب الثلاثي (§1.3).
enum StyleRelation {
  /// `≥ 70` — متقاربان: يجتمعان بلا نيّة خاصة.
  high,

  /// `55..69` — محايدان: يجتمعان بنيّة (انتقالي).
  medium,

  /// `≤ 54` — متنافران: اجتماعهما يحتاج مبرّرًا.
  low,
}

/// تقارب ستايلين `0..100` = `(20 − مسافة مانهاتن) × 5` (§1.3). عدد صحيح، متناظر،
/// و`100` للستايل مع نفسه.
int styleAffinity(FurnitureStyle a, FurnitureStyle b) {
  final pa = kStyleProfiles[a]!.traits;
  final pb = kStyleProfiles[b]!.traits;
  var distance = 0;
  for (var i = 0; i < pa.length; i++) {
    distance += (pa[i] - pb[i]).abs();
  }
  final value = (20 - distance) * 5;
  return value < 0 ? 0 : (value > 100 ? 100 : value);
}

/// يحوّل الدرجة إلى حكم (§1.3).
StyleRelation styleRelation(FurnitureStyle a, FurnitureStyle b) {
  final s = styleAffinity(a, b);
  if (s >= 70) return StyleRelation.high;
  if (s <= 54) return StyleRelation.low;
  return StyleRelation.medium;
}

const List<String> _traitNamesAr = [
  'الزخرفة',
  'هندسة الخط',
  'الكتلة البصرية',
  'خشونة الخامة',
  'تشبّع اللون',
];

/// **الشرح بجملة واحدة** (§1.5): يُنطق الحكم من أكبر سمّتين متباعدتين (للتنافر)
/// أو أقرب سمّتين (للتقارب). ترتيب السمات حتميّ: الفرق ثم الفهرس.
String explainAffinity(FurnitureStyle a, FurnitureStyle b) {
  final pa = kStyleProfiles[a]!.traits;
  final pb = kStyleProfiles[b]!.traits;
  int diff(int i) => (pa[i] - pb[i]).abs();
  final la = a.arabicLabel;
  final lb = b.arabicLabel;

  if (styleRelation(a, b) == StyleRelation.low) {
    // الأكثر تباعدًا أولًا؛ عند التعادل الفهرس الأصغر — لا اعتماد على استقرار الفرز.
    final order = [for (var i = 0; i < 5; i++) i]
      ..sort((x, y) {
        final byDiff = diff(y).compareTo(diff(x));
        return byDiff != 0 ? byDiff : x.compareTo(y);
      });
    final i0 = order[0];
    final i1 = order[1];
    return '$la و$lb متنافران: '
        '${_traitNamesAr[i0]} تفصلهما بـ${diff(i0)}، و${_traitNamesAr[i1]} بـ${diff(i1)}.';
  }

  final order = [for (var i = 0; i < 5; i++) i]
    ..sort((x, y) {
      final byDiff = diff(x).compareTo(diff(y));
      return byDiff != 0 ? byDiff : x.compareTo(y);
    });
  final relWord =
      styleRelation(a, b) == StyleRelation.high ? 'متقاربان' : 'محايدان';
  return '$la و$lb $relWord: '
      'يشتركان في ${_traitNamesAr[order[0]]} و${_traitNamesAr[order[1]]}.';
}
