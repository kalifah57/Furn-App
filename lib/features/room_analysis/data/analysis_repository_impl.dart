import '../../../ai/contracts/llm_extraction_service.dart';
import '../../../ai/contracts/speech_to_text_service.dart';
import '../../../ai/contracts/vision_analysis_service.dart';
import '../../../ai/models/normalized_input.dart';
import '../../../ai/prompt/prompt_builder.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/text_normalizer.dart';
import '../../../domain_engine/business_rules/business_rules_engine.dart';
import '../../../shared/models/furnishing_project.dart';
import '../domain/analysis_repository.dart';

/// تنفيذ مسار التحليل: يربط طبقة الـ AI بقواعد العمل الحتمية.
class AnalysisRepositoryImpl implements AnalysisRepository {
  const AnalysisRepositoryImpl({
    required this.speechToText,
    required this.vision,
    required this.llm,
    this.promptBuilder = const PromptBuilder(),
    this.rules = const BusinessRulesEngine(),
  });

  final SpeechToTextService speechToText;
  final VisionAnalysisService vision;
  final LlmExtractionService llm;
  final PromptBuilder promptBuilder;
  final BusinessRulesEngine rules;

  @override
  Future<Result<FurnishingProject>> analyzeFromText(
    String text, {
    InputSource source = InputSource.text,
  }) {
    final input = NormalizedInput(rawText: normalizeInput(text), source: source);
    return _extract(input);
  }

  @override
  Future<Result<FurnishingProject>> analyzeFromVoice(String audioRef) async {
    final transcript = await speechToText.transcribe(audioRef);
    switch (transcript) {
      case Ok(:final value):
        return analyzeFromText(value, source: InputSource.voice);
      case Err(:final failure):
        return Err(failure);
    }
  }

  @override
  Future<Result<FurnishingProject>> analyzeFromImages(
    List<String> imageRefs, {
    String text = '',
  }) async {
    final visionRes = await vision.analyze(imageRefs);
    final summary = visionRes.valueOrNull ?? '';
    final input = NormalizedInput(
      rawText: normalizeInput(text),
      source: InputSource.image,
      visionSummary: summary,
      imageRefs: imageRefs,
    );
    return _extract(input);
  }

  @override
  FurnishingProject finalizeManual(FurnishingProject draft) => rules.apply(draft);

  Future<Result<FurnishingProject>> _extract(NormalizedInput input) async {
    // يُبنى الـ prompt (مُصدَّر ومُوَثَّق) — يُرسَل للمزوّد الحقيقي لاحقًا.
    promptBuilder.build(input);
    final extracted = await llm.extract(input);
    return switch (extracted) {
      Ok(:final value) => Ok(rules.apply(value)),
      Err(:final failure) => Err(failure),
    };
  }
}
