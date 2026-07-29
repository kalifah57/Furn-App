import 'dart:convert';

import '../../core/errors/failure.dart';
import '../../core/errors/result.dart';
import '../../shared/models/furnishing_project.dart';

/// StructuredResponseParser (ai_pipeline.md / prompt_engineering.md — Error handling).
///
/// يحوّل مخرجات الـ LLM (نص JSON) إلى نموذج منظّم مع:
/// - محاولة تحليل مباشرة.
/// - خطوة إصلاح (repair): إزالة أسوار الأكواد واستخراج أول كائن JSON.
/// - فشل واضح ([AiParsingFailure]) عند تعذّر التحليل → ينتقل المستدعي إلى fallback.
class StructuredResponseParser {
  const StructuredResponseParser();

  Result<FurnishingProject> parse(String raw) {
    final direct = _tryDecode(raw);
    if (direct != null) return Ok(FurnishingProject.fromJson(direct));

    final repaired = _tryDecode(_repair(raw));
    if (repaired != null) return Ok(FurnishingProject.fromJson(repaired));

    return const Err(AiParsingFailure());
  }

  Map<String, dynamic>? _tryDecode(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {/* تُعالَج عبر repair */}
    return null;
  }

  /// إزالة ```json ... ``` واستخراج أول {...} متوازن.
  String _repair(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^```(json)?', multiLine: true), '');
    s = s.replaceAll('```', '').trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) return s.substring(start, end + 1);
    return s;
  }
}
