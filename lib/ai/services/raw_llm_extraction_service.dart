import '../../core/errors/failure.dart';
import '../../core/errors/result.dart';
import '../../shared/models/furnishing_project.dart';
import '../contracts/llm_extraction_service.dart';
import '../models/normalized_input.dart';
import '../parsing/structured_response_parser.dart';

/// دالة الإكمال الخام — تأخذ prompt وتعيد نصّ المزوّد كما هو.
///
/// تُحقن كي يبقى هذا الصنف قابلًا للاختبار بلا شبكة، وكي يعيش استدعاء الشبكة
/// الفعلي (`dart:html` / `package:http`) خلف حقنٍ في طبقة التركيب — نفس نمط
/// `AnalyticsPost` في `http_analytics.dart`.
typedef LlmComplete = Future<String> Function(String prompt);

/// المسار الحقيقي لاستخراج الـ LLM — **جاهز للاستخدام، خامد حتى يُحقن مزوّد**.
///
/// يربط ثلاث قطع كانت متفرّقة: بناء الـ prompt، نداء المزوّد، وتحليل المخرجات
/// عبر [StructuredResponseParser]. الافتراضي في التطبيق يبقى
/// `MockLlmExtractionService`؛ يوم يتوفّر مزوّد حقيقي، يُحقن [complete] ويُبدَّل
/// المزوّد عبر `override` دون لمس أي نقطة نداء (نفس عقد [LlmExtractionService]).
///
/// **يحافظ على القاعدة الجوهرية:** يستخرج بيانات منظمة فقط؛ حقول التوصيات تبقى
/// فارغة ويملؤها محرّك التوصيات الحتمي لاحقًا.
class RawLlmExtractionService implements LlmExtractionService {
  const RawLlmExtractionService({
    required this.complete,
    this.buildPrompt = defaultPromptBuilder,
    this.parser = const StructuredResponseParser(),
  });

  final LlmComplete complete;
  final String Function(NormalizedInput) buildPrompt;
  final StructuredResponseParser parser;

  @override
  Future<Result<FurnishingProject>> extract(NormalizedInput input) async {
    final String raw;
    try {
      raw = await complete(buildPrompt(input));
    } catch (e) {
      // سقوط الشبكة/المزوّد فشلٌ واضح ينتقل به المستدعي إلى fallback، لا استثناء
      // يخترق الطبقات.
      return Err(AiParsingFailure('تعذّر الوصول إلى مزوّد التحليل.', e));
    }
    return parser.parse(raw);
  }

  /// باني prompt افتراضي بسيط — يُستبدل بـ`prompt_engineering.md` الكامل لاحقًا.
  /// يضع نصّ المستخدم وإشارات الرؤية، ويطلب JSON مطابقًا لـ`json_schema.md`.
  static String defaultPromptBuilder(NormalizedInput input) {
    final vision =
        input.hasVision ? '\n[Vision Signals]\n${input.visionSummary}' : '';
    return 'استخرج بيانات منظمة (room/budget/style/items/analysis) من الطلب '
        'التالي، وأعد JSON فقط مطابقًا لـ json_schema.md دون أي توصيات.\n'
        '[Request]\n${input.rawText}$vision';
  }
}
