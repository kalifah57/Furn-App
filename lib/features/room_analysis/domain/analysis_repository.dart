import '../../../ai/models/normalized_input.dart';
import '../../../core/errors/result.dart';
import '../../../shared/models/furnishing_project.dart';

/// واجهة تنسيق مسار التحليل (ai_pipeline.md).
/// تُجرِّد: STT/Vision → LLM extraction → business rules.
abstract interface class AnalysisRepository {
  /// تحليل من نص/صوت مُحوَّل إلى نص.
  Future<Result<FurnishingProject>> analyzeFromText(
    String text, {
    InputSource source,
  });

  /// تحليل من تسجيل صوتي (يُحوَّل عبر STT وهمي).
  Future<Result<FurnishingProject>> analyzeFromVoice(String audioRef);

  /// تحليل من صور (+ نص اختياري) عبر Vision وهمي.
  Future<Result<FurnishingProject>> analyzeFromImages(
    List<String> imageRefs, {
    String text,
  });

  /// إنهاء الإدخال اليدوي المنظّم: قواعد العمل فقط (بلا استدعاء LLM — cost control).
  FurnishingProject finalizeManual(FurnishingProject draft);
}
