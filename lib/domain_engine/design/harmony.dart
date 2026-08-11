/// تناغم الغرفة — المُقيّم **v0** (docs/design/02 · docs/design/09).
///
/// Dart صرف · بلا Flutter · بلا تتبّع. **v0 مقصود ناقص:** يستخدم البدائيّتين المنفَّذتين
/// فقط — تقارب الستايل وحرارة اللون — فيقيس D4 خطَّ الأساس، ثم يضيف D5 قواعد الخامة
/// والمقياس وعبر-المحاور تكرارًا حتى الإتقان. كل قاعدة تبقى مشروحة بجملة.
library;

import 'color_system.dart';
import 'style_taxonomy.dart';

/// حكم التناغم الثنائي (على غرار `ArFitVerdict`: قرار يُعرض لا درجة غامضة).
enum HarmonyVerdict { harmonious, dissonant }

/// قطعة في المشهد — الحقول التصميمية فقط (لا ضجيج `CatalogProduct`). مُهايئ يحوّل
/// `CatalogProduct → HarmonyPiece` لاحقًا (D9)؛ في D4 يملؤها الـ corpus.
class HarmonyPiece {
  const HarmonyPiece({
    required this.category,
    this.styles = const [],
    this.colors = const [],
    this.materials = const [],
    this.woodTone,
    this.widthCm = 0,
    this.depthCm = 0,
    this.heightCm = 0,
    this.subcategory = '',
  });

  final String category;
  final List<String> styles; // أسماء الستايلات
  final List<String> colors; // معرّفات رموز اللون
  final List<String> materials; // عائلات الخامة
  final String? woodTone;
  final double widthCm;
  final double depthCm;
  final double heightCm;
  final String subcategory;
}

/// مشهد غرفة: نوعها وأبعادها وقطعها.
class HarmonyScene {
  const HarmonyScene({
    required this.roomType,
    this.widthM = 0,
    this.lengthM = 0,
    this.pieces = const [],
  });

  final String roomType;
  final double widthM;
  final double lengthM;
  final List<HarmonyPiece> pieces;
}

/// نتيجة التقييم: الحكم والقواعد التي أطلقت التنافر (للشفافية).
class HarmonyResult {
  const HarmonyResult({required this.verdict, required this.firedRules});

  final HarmonyVerdict verdict;

  /// معرّفات القواعد التي رصدت تنافرًا (`styleAffinity`, `C2`…) — مرتّبة أبجديًّا (حتمية).
  final List<String> firedRules;

  bool get isHarmonious => verdict == HarmonyVerdict.harmonious;
}

FurnitureStyle? _styleFromName(String name) {
  for (final s in FurnitureStyle.values) {
    if (s.name == name) return s;
  }
  return null; // ستايل خارج التصنيف يُتجاهَل لا يُخمَّن
}

/// **المُقيّم v0.** يُطلق التنافر من قاعدتين منفَّذتين فقط:
///
/// - `styleAffinity`: أي زوج ستايلين متمايزين تقاربه `< 55` — «ستايلان متنافران يكسران
///   لهجة الغرفة الواحدة».
/// - `C2`: اجتماع لونٍ دافئ وآخر بارد — «الدافئ والبارد يتجاذبان فتفقد الغرفة تماسك حرارتها».
///
/// اللون خارج المعجم يُتخطّى لا يُخمَّن (نفس مبدأ الكتالوج الحقيقي: Turquoise/Chrome تُتجاهَل).
HarmonyResult evaluateHarmony(HarmonyScene scene) {
  final fired = <String>[];

  // ترتيب أسماء الستايلات أبجديًّا — عناصر فريدة، لا حاجة لفاصل تعادل إضافي.
  final styleNames = <String>{for (final p in scene.pieces) ...p.styles}.toList()
    ..sort();
  final styles = <FurnitureStyle>[
    for (final n in styleNames)
      if (_styleFromName(n) != null) _styleFromName(n)!,
  ];
  var styleClash = false;
  for (var i = 0; i < styles.length; i++) {
    for (var j = i + 1; j < styles.length; j++) {
      if (styleAffinity(styles[i], styles[j]) < 55) styleClash = true;
    }
  }
  if (styleClash) fired.add('styleAffinity');

  final temps = <Temperature>{};
  for (final p in scene.pieces) {
    for (final c in p.colors) {
      final tok = kColorTokens[c];
      if (tok != null) temps.add(tok.temperature);
    }
  }
  if (temps.contains(Temperature.warm) && temps.contains(Temperature.cool)) {
    fired.add('C2');
  }

  fired.sort(); // معرّفات فريدة — ترتيب حتميّ
  return HarmonyResult(
    verdict: fired.isEmpty ? HarmonyVerdict.harmonious : HarmonyVerdict.dissonant,
    firedRules: fired,
  );
}
