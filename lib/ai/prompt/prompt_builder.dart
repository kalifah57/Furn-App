import '../models/normalized_input.dart';
import 'prompt_template.dart';

/// نتيجة بناء الـ prompt (النص + بيانات الإصدار للتسجيل).
class BuiltPrompt {
  const BuiltPrompt({required this.text, required this.version});
  final String text;
  final PromptVersion version;
}

/// PromptBuilder (prompt_engineering.md — Responsibilities):
/// يجمع المدخلات، يوحّد الصياغة، يحقن الـ schema، ويضيف إصدار الـ prompt.
class PromptBuilder {
  const PromptBuilder();

  BuiltPrompt build(NormalizedInput input) {
    final rules = kExtractionRules.map((r) => '- $r').join('\n');
    final vision = input.hasVision ? input.visionSummary : '(none)';

    final text = '''
[System Role]
$kSystemRole

[Rules]
$rules

[Schema]
$kSchemaSkeleton
[User Input]
${input.rawText}

[Vision Signals]
$vision

[Output]
Return valid JSON only.
''';

    return BuiltPrompt(text: text, version: kExtractionPromptVersion);
  }
}
