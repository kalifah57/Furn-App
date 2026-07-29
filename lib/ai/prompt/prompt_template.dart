/// بيانات إصدار الـ prompt (prompt_engineering.md — Versioning).
class PromptVersion {
  const PromptVersion({
    required this.promptName,
    required this.version,
    required this.lastUpdated,
    required this.supportedSchemaVersion,
  });

  final String promptName;
  final String version;
  final String lastUpdated;
  final String supportedSchemaVersion;

  Map<String, String> toMetadata() => {
        'prompt_name': promptName,
        'version': version,
        'last_updated': lastUpdated,
        'supported_schema_version': supportedSchemaVersion,
      };
}

/// قالب الـ prompt الرسمي (prompt_engineering.md — Prompt Structure Template).
/// عقد تشغيلي: يحدّد الدور، القواعد، الـ schema، المدخلات، وشكل المخرجات.
const String kSystemRole =
    'You are an AI extraction assistant for an Arabic-first furnishing '
    'consultancy app.\nYour only job is to extract structured room, budget, '
    'furniture, and preference data.\nReturn valid JSON only.';

const List<String> kExtractionRules = [
  'Do not invent dimensions.',
  'Do not guess budget if absent.',
  'Mark missing information explicitly.',
  'Separate essential vs optional items.',
  'Output must match the provided schema.',
];

/// هيكل الـ schema المرجعي المحقون في الـ prompt (مطابق json_schema.md).
const String kSchemaSkeleton = '''
{
  "project_id": "string",
  "locale": "ar-SA",
  "room": {"name": "string", "width_m": 0, "length_m": 0, "height_m": 0,
           "room_type": "bedroom|living_room|guest_room|other"},
  "budget": {"currency": "SAR", "max_total": 0, "flexible": false},
  "style": {"preferred": [], "colors": [], "notes": "string"},
  "items": {"essential": [{"type": "string", "constraints": [], "quantity": 1}],
            "optional": [{"type": "string", "constraints": [], "quantity": 1}]},
  "analysis": {"summary": "string", "missing_information": [], "warnings": [],
               "confidence_score": 0}
}
''';

const PromptVersion kExtractionPromptVersion = PromptVersion(
  promptName: 'room_extraction',
  version: '1.0.0',
  lastUpdated: '2026-07-29',
  supportedSchemaVersion: '1.0.0',
);
