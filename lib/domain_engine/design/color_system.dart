import 'dart:math' as math;

/// لغة التصميم — محور اللون (docs/design/01-design-language.md §2).
///
/// كل رمز **مُسنَد إلى قيمة CIELAB محسوبة** (docs/design/06 §هـ): الحرارة والإضاءة
/// والتشبّع مشتقّة من معيار لوني لا مُدخلة يدويًّا. Dart صرف · بلا Flutter.
///
/// لماذا CIELAB: «Beige» اسمٌ لا يُحسب منه تناغم؛ أما `b*` فقطبٌ فيزيائي — الأصفر
/// دافئ والأزرق بارد — فيصير «الجوز والرمادي البارد يتجاذبان» قاعدةً لا انطباعًا.

enum ColorFamily {
  achromatic,
  red,
  orange,
  yellow,
  green,
  blue,
  violet,
  brown,
  metal,
}

/// الحرارة اللونية — محور «التجاذب» (§2.2).
enum Temperature {
  warm,
  neutral,
  cool;

  String get arabicLabel => switch (this) {
        Temperature.warm => 'دافئ',
        Temperature.neutral => 'محايد',
        Temperature.cool => 'بارد',
      };
}

/// أقصى دور يصلح له اللون في نسبة 60/30/10 (§2.2 · roleCap).
enum ColorRole { dominant, secondary, accent }

/// رمز لون — القيمة الأساس هي **CIELAB (D65)**، والباقي مشتقّ منها بعتبات ثابتة،
/// فلا رقم يدويّ يتسلّل.
class ColorToken {
  const ColorToken({
    required this.id,
    required this.arabicLabel,
    required this.family,
    required this.roleCap,
    required this.lStar,
    required this.aStar,
    required this.bStar,
  });

  final String id;
  final String arabicLabel;
  final ColorFamily family;
  final ColorRole roleCap;

  /// إحداثيات CIELAB (D65) — الأساس المحسوب.
  final double lStar;
  final double aStar;
  final double bStar;

  /// الحرارة من قطب `b*`: الأصفر دافئ، الأزرق بارد (§2.2). عتبة `±3` تترك حيّزًا
  /// محايدًا للرماديّ الخالص فلا يُصنَّف قسرًا.
  Temperature get temperature => bStar > 3
      ? Temperature.warm
      : (bStar < -3 ? Temperature.cool : Temperature.neutral);

  /// شريحة إضاءة `0..4` من `L*` بعتبات ثابتة — لا تقريب لغويّ يختلف بين اللغات.
  int get lightnessBand => lStar < 12.5
      ? 0
      : lStar < 37.5
          ? 1
          : lStar < 62.5
              ? 2
              : lStar < 87.5
                  ? 3
                  : 4;

  /// شريحة تشبّع `0..4` من `C* = √(a*² + b*²)`.
  int get chromaBand {
    final c = math.sqrt(aStar * aStar + bStar * bStar);
    return c < 8
        ? 0
        : c < 18
            ? 1
            : c < 32
                ? 2
                : c < 50
                    ? 3
                    : 4;
  }
}

/// المعجم الأساسي (§2.3) — مفاتيحه معرّفات الرموز، وقيمه مُسنَدة لـCIELAB محسوب
/// (docs/design/06 §هـ). الرماديّ مفصولٌ دافئًا/باردًا لأن الرماديّ بلا حرارة
/// هو ما جعل مثال المؤسّس غير قابل للتمثيل.
const Map<String, ColorToken> kColorTokens = {
  'white': ColorToken(
      id: 'white', arabicLabel: 'أبيض', family: ColorFamily.achromatic,
      roleCap: ColorRole.dominant, lStar: 100.0, aStar: 0.0, bStar: 0.0),
  'off_white': ColorToken(
      id: 'off_white', arabicLabel: 'أوف وايت', family: ColorFamily.achromatic,
      roleCap: ColorRole.dominant, lStar: 94.7, aStar: 0.5, bStar: 5.0),
  'gray_cool': ColorToken(
      id: 'gray_cool', arabicLabel: 'رمادي بارد', family: ColorFamily.achromatic,
      roleCap: ColorRole.dominant, lStar: 59.8, aStar: -0.9, bStar: -5.1),
  'gray_warm': ColorToken(
      id: 'gray_warm', arabicLabel: 'رمادي دافئ', family: ColorFamily.achromatic,
      roleCap: ColorRole.dominant, lStar: 66.6, aStar: 1.1, bStar: 5.1),
  'beige': ColorToken(
      id: 'beige', arabicLabel: 'بيج', family: ColorFamily.achromatic,
      roleCap: ColorRole.dominant, lStar: 88.2, aStar: 0.8, bStar: 11.3),
  'black': ColorToken(
      id: 'black', arabicLabel: 'أسود', family: ColorFamily.achromatic,
      roleCap: ColorRole.accent, lStar: 5.1, aStar: 0.0, bStar: 0.0),
  'brown': ColorToken(
      id: 'brown', arabicLabel: 'بنّي', family: ColorFamily.brown,
      roleCap: ColorRole.secondary, lStar: 36.2, aStar: 10.9, bStar: 19.1),
  'blue': ColorToken(
      id: 'blue', arabicLabel: 'أزرق', family: ColorFamily.blue,
      roleCap: ColorRole.accent, lStar: 40.6, aStar: 8.1, bStar: -39.2),
  'gold': ColorToken(
      id: 'gold', arabicLabel: 'ذهبي', family: ColorFamily.metal,
      roleCap: ColorRole.accent, lStar: 68.6, aStar: 4.7, bStar: 49.6),
  'red': ColorToken(
      id: 'red', arabicLabel: 'أحمر', family: ColorFamily.red,
      roleCap: ColorRole.accent, lStar: 42.3, aStar: 48.0, bStar: 34.2),
};

/// يخرط **وسم لون من الكتالوج** إلى رمز. الغامض يعود `null` عمدًا لا تخمينًا:
/// `gray` يحتاج حرارة السطح الحامل له (يحسمه المُفسِّر لكل منتج §د٣)، و`walnut`
/// نغمة خشب لا لون. تقديرٌ بلا مصدر أسوأ من لا تقدير.
ColorToken? colorTokenForTag(String tag) => kColorTokens[tag.toLowerCase()];

/// تعارض حراري — **أساس قاعدة C2**: الدافئ والبارد يتجاذبان فيسحب كلٌّ الغرفة لجهة.
bool temperaturesClash(Temperature a, Temperature b) =>
    (a == Temperature.warm && b == Temperature.cool) ||
    (a == Temperature.cool && b == Temperature.warm);
