import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/mock/mock_llm_extraction_service.dart';
import 'package:furn_app/ai/models/normalized_input.dart';
import 'package:furn_app/core/errors/result.dart';
import 'package:furn_app/core/utils/text_normalizer.dart';
import 'package:furn_app/domain_engine/business_rules/business_rules_engine.dart';
import 'package:furn_app/shared/models/models.dart';

/// اختبار عقد الحارس (G-14 · U5): **«لا تُسأل عمّا أُجيب».**
///
/// يشبك مخرَج الاستخراج (mock) بمولّد أسئلة المتابعة الحتمي (`BusinessRulesEngine`)
/// — كما في `AnalysisRepositoryImpl` — ويثبت أن سؤال المتابعة لا يُطرح إلا عن
/// حقلٍ **غاب فعلًا** عن ناتج الاستخراج. حادثة المؤسّس (أعطى كل شيء فسُئل عن
/// الميزانية والألوان) لا يجوز أن تتكرّر.
void main() {
  const engine = BusinessRulesEngine();
  final service = MockLlmExtractionService(uuidFactory: () => 'proj_test');

  // بصمات نصوص الأسئلة كما يولّدها المحرّك — نتحقّق أنها لا تظهر لحقلٍ مُعطى.
  const qDims = 'عرض وطول';        // سؤال الأبعاد
  const qBudget = 'ميزانيتك';       // سؤال الميزانية
  const qEssential = 'القطع الأساسية'; // سؤال العناصر
  const qStyle = 'نمط مفضّل';        // سؤال النمط/الألوان

  Future<FurnishingProject> analyze(String text) async {
    final res = await service
        .extract(NormalizedInput(rawText: normalizeInput(text)));
    return engine.apply((res as Ok<FurnishingProject>).value);
  }

  bool asksAbout(FurnishingProject p, String needle) =>
      p.nextActions.followUpQuestions.any((q) => q.contains(needle));

  test('جملة المؤسّس الحرفية: أعطى كل شيء ⟶ لا سؤال متابعة إطلاقًا', () async {
    final p = await analyze(
      'غرفة نوم ٤×٣٫٥، أبي سرير معدني أسود ١٢٠×٢٠٠ ومرتبة، كومدينو خشب جوز، '
      'علاقة ملابس، سجادة بيج وستائر تعتيم، وأبي ثلاجة صغيرة — ميزانيتي ٣٠٠٠',
    );
    // كل حقل جوهري مُعطى: أبعاد، ميزانية، عناصر، ألوان.
    expect(asksAbout(p, qBudget), isFalse, reason: 'سُئل عن ميزانية أعطاها');
    expect(asksAbout(p, qStyle), isFalse, reason: 'سُئل عن ألوان أعطاها');
    expect(asksAbout(p, qDims), isFalse, reason: 'سُئل عن أبعاد أعطاها');
    expect(asksAbout(p, qEssential), isFalse, reason: 'سُئل عن قطع أعطاها');
    expect(p.nextActions.followUpQuestions, isEmpty);
  });

  test('حارس دقيق: أبعاد+قطع مُعطاة، الميزانية غائبة ⟶ يُسأل عن الغائب لا عمّا أُعطي',
      () async {
    // أُعطيت الأبعاد والقطع وحُذفت الميزانية عمدًا. عندها يتفعّل سؤال المتابعة
    // (لوجود نقص حقيقي)، فيصير المِحكّ دقيقًا: يُسأل عن الميزانية الغائبة **دون**
    // إعادة السؤال عن الأبعاد والقطع اللتين أُجيبتا. هذا هو جوهر «لا تُسأل عمّا أُجيب».
    final p = await analyze('غرفة نوم ٤×٥، سرير وخزانة');
    // المُعطى لا يُسأل عنه:
    expect(asksAbout(p, qDims), isFalse, reason: 'سُئل عن أبعاد أعطاها');
    expect(asksAbout(p, qEssential), isFalse, reason: 'سُئل عن قطع أعطاها');
    // الغائب وحده يُسأل عنه:
    expect(asksAbout(p, qBudget), isTrue, reason: 'لم يُسأل عن الميزانية الغائبة');
  });

  test('المجهول يُعلَن: طلب عامّ بلا معطيات ⟶ يُسأل عن الغائب', () async {
    final p = await analyze('أبي أأثث بيتي');
    expect(p.nextActions.followUpQuestions, isNotEmpty);
    expect(asksAbout(p, qDims), isTrue);
    expect(asksAbout(p, qBudget), isTrue);
  });

  test('صدق البيانات: الاستخراج لا يملأ التوصيات (المحرّك يملؤها)', () async {
    final res = await service.extract(
        NormalizedInput(rawText: normalizeInput('غرفة نوم ٤×٥ سرير ميزانيتي ٥٠٠٠')));
    expect((res as Ok<FurnishingProject>).value.recommendations.isEmpty, isTrue);
  });
}
