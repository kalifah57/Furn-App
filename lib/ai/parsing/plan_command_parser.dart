import '../../domain_engine/recommendation/category_mapper.dart';
import '../../shared/models/enums.dart';
import 'plan_command.dart';

/// يحوّل جملة المستخدم داخل «غرفتي» إلى [PlanCommand] منظّم — **حتميًّا**، بلا
/// نموذج، بمطابقة مفرداتٍ عربية شائعة.
///
/// هذا بديلٌ mock-first لمسار الـ LLM (نفس فلسفة `RawLlmExtractionService`):
/// يُبدَّل لاحقًا بمزوّدٍ حقيقي عبر نفس العقد دون لمس نقاط النداء. ومخرجاته
/// **أوامر لا قرارات** — المحرّك ينفّذها ويملك نتيجتها.
///
/// الترتيب مقصود: إضافة/إزالة فئة (الأصرح) ← تحديد ميزانية برقم ← إزاحة
/// أوفر/أعلى ← اعتماد ← وإلا **مجهول**. لا نخمّن: المجهول يُعلَن ليعيد المستخدم
/// الصياغة، ولا يُترجَم إلى فعلٍ لم يطلبه.
class PlanCommandParser {
  const PlanCommandParser();

  PlanCommand parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return const UnknownCommand('');
    final t = _normalize(raw);

    // الفئة تُستخرَج من النصّ الأصلي عبر خريطة المحرّك نفسها (تعرف مفرداتها،
    // بأشكال الهمزة التي يوحّدها تطبيعُنا).
    RecommendationCategory? categoryIn() => mapTypeToCategoryOrNull(raw);

    if (_hasAny(t, _addWords)) {
      final c = categoryIn();
      if (c != null) return AddCategoryCommand(c);
    }
    if (_hasAny(t, _removeWords)) {
      final c = categoryIn();
      if (c != null) return RemoveCategoryCommand(c);
    }

    final number = _firstNumber(t);
    if (number != null && (_hasAny(t, _budgetWords) || _isBareNumber(t))) {
      return SetBudgetCommand(number);
    }

    if (_hasAny(t, _cheaperWords)) return const NudgeBudgetCommand(-1);
    if (_hasAny(t, _raiseWords)) return const NudgeBudgetCommand(1);
    if (_hasAny(t, _finalizeWords)) return const FinalizeCommand();

    return UnknownCommand(raw);
  }

  // ---- المفردات (بالصيغة الموحّدة: بلا همزة/تطويل/حركات، أرقام غربية) --------

  static const _addWords = [
    'اضف', 'ضيف', 'زودني', 'زد لي', 'ابي', 'ابغي', 'اريد', 'حاب', 'ودي',
    'ناقص', 'ناقصني', 'محتاج',
  ];
  static const _removeWords = [
    'احذف', 'امسح', 'شيل', 'ازل', 'الغ', 'بدون', 'ما ابي', 'ما ابغي',
    'لا اريد', 'ما احتاج',
  ];
  static const _cheaperWords = ['اوفر', 'ارخص', 'رخيص', 'خفض', 'قلل', 'غالي'];
  static const _raiseWords = ['زد', 'زيد', 'ارفع'];
  static const _finalizeWords = [
    'جاهز', 'خلصت', 'خلاص', 'اعتمد', 'انهي', 'ثبت الخطه', 'خطتي جاهزه',
  ];
  static const _budgetWords = [
    'ميزاني', 'خلها', 'خليها', 'اجعلها', 'حدد', 'ريال', 'sar',
  ];

  bool _hasAny(String t, List<String> keys) => keys.any(t.contains);

  /// يوحّد النصّ: حروف صغيرة، أرقام عربية/فارسية→غربية، حذف فاصل الآلاف العربي،
  /// ألف بأشكالها→ا، ى→ي، حذف التطويل والحركات، وضغط الفراغات. المفردات مكتوبة
  /// بهذه الصيغة نفسها فتُطابَق بلا تكرار كل شكلٍ همزيّ.
  String _normalize(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + (r - 0x0660)); // ٠-٩
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + (r - 0x06F0)); // ۰-۹
      } else {
        b.writeCharCode(r);
      }
    }
    var t = b.toString().toLowerCase();
    t = t.replaceAll('٬', ''); // فاصل الآلاف العربي ٬
    t = t.replaceAll(RegExp('[أإآ]'), 'ا');
    t = t.replaceAll('ى', 'ي');
    t = t.replaceAll('ـ', '');
    t = t.replaceAll(RegExp('[ً-ْ]'), ''); // الحركات
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// أوّل عددٍ صحيح في النصّ الموحّد، متجاهلًا فواصل الآلاف. `null` إن لم يوجد.
  double? _firstNumber(String t) {
    final m = RegExp(r'\d[\d,]*').firstMatch(t);
    if (m == null) return null;
    return double.tryParse(m[0]!.replaceAll(',', ''));
  }

  /// النصّ رقمٌ صرف (لا شيء غير الأرقام والفراغات والفواصل) — عندها هو ميزانية.
  bool _isBareNumber(String t) =>
      t.isNotEmpty && RegExp(r'^[\d\s,]+$').hasMatch(t);
}
