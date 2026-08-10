import '../../core/errors/result.dart';
import '../../shared/models/furnishing_project.dart';
import '../models/normalized_input.dart';

/// تجريد استخراج الـ LLM (ai_pipeline.md / prompt_engineering.md).
///
/// **قاعدة جوهرية:** يُخرِج بيانات منظمة فقط (room/budget/style/items/analysis)
/// مطابقة لـ json_schema.md — ولا يقرّر التوصيات. حقول `recommendations` تبقى فارغة
/// ويملؤها محرّك التوصيات الحتمي لاحقًا.
abstract interface class LlmExtractionService {
  Future<Result<FurnishingProject>> extract(NormalizedInput input);
}
