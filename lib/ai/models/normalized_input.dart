import 'package:equatable/equatable.dart';

/// مصدر إدخال المستخدم.
enum InputSource { voice, text, image, manual }

/// مدخلات موحّدة بعد التنظيف (Input Normalization في ai_pipeline.md).
/// تُغذّي PromptBuilder ثم LlmExtractionService.
class NormalizedInput extends Equatable {
  const NormalizedInput({
    required this.rawText,
    this.source = InputSource.text,
    this.visionSummary = '',
    this.imageRefs = const [],
  });

  /// نص المستخدم بعد التنظيف وتوحيد الوحدات.
  final String rawText;
  final InputSource source;

  /// ملخّص إشارات الرؤية (إن توفّرت).
  final String visionSummary;

  /// مراجع الصور (مسارات/معرّفات وهمية في الـ MVP).
  final List<String> imageRefs;

  bool get hasVision => visionSummary.isNotEmpty;

  @override
  List<Object?> get props => [rawText, source, visionSummary, imageRefs];
}
