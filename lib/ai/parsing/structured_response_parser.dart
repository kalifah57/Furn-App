import 'dart:convert';

import '../../core/errors/failure.dart';
import '../../core/errors/result.dart';
import '../../shared/models/furnishing_project.dart';

/// يحوّل مخرجات الـ LLM (نصّ JSON) إلى [FurnishingProject] منظّم.
///
/// مزوّدات الـ LLM لا تُخرج JSON نظيفًا دائمًا: تلفّه بأسوار ```code```، أو تسبقه
/// بجملة تمهيدية، أو تُنهيه بشرح. لذا التحليل على ثلاث محاولات متدرّجة —
/// مباشرة، ثم إصلاح، ثم استخراج أوّل كائن متوازن — قبل الاستسلام.
///
/// **قرار جوهري:** JSON صالح نحويًّا لا يعني مشروعًا صالحًا. `{"foo": 1}` يُفكَّك
/// بنجاح، لكن `FurnishingProject.fromJson` يعطي عندها مشروعًا فارغًا بمعرّف فارغ
/// وأبعاد صفرية **بلا خطأ** — فيمرّ إلى المستخدم كأنه فُهم. لذلك نرفض أي ناتج
/// بلا `project_id`: غياب المعرّف علامة أن ما فُكّك ليس مشروعًا، ففشلٌ واضح خير
/// من مشروع صامت فارغ.
class StructuredResponseParser {
  const StructuredResponseParser();

  Result<FurnishingProject> parse(String raw) {
    final map = _tryDecode(raw) ?? _tryDecode(_repair(raw));
    if (map == null) {
      return const Err(AiParsingFailure());
    }
    if (!_looksLikeProject(map)) {
      return const Err(
          AiParsingFailure('المخرجات JSON صالح لكنه ليس مشروعًا (لا معرّف).'));
    }
    return Ok(FurnishingProject.fromJson(map));
  }

  Map<String, dynamic>? _tryDecode(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {/* تُعالَج عبر repair أو تُبلَّغ كفشل */}
    return null;
  }

  /// المفتاح الأدنى الذي يميّز مشروعًا عن أي كائن آخر. لا نتحقّق من الغرفة أو
  /// الميزانية — قد يتركهما المستخدم فارغتين عمدًا — بل من وجود هوية للمشروع.
  bool _looksLikeProject(Map<String, dynamic> m) {
    final id = m['project_id'];
    return id is String && id.trim().isNotEmpty;
  }

  /// إزالة أسوار ```json ... ``` واستخراج أوّل `{...}` متوازن من نصّ قد يحيط به
  /// كلام. نعتمد التوازن لا `lastIndexOf('}')`: جملة ختامية فيها `}` كانت
  /// ستبتلع نصًّا ليس من الكائن.
  String _repair(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'```(json)?', multiLine: true), '').trim();

    final start = s.indexOf('{');
    if (start < 0) return s;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return s.substring(start); // غير متوازن — يفشل التفكيك، فيُبلَّغ كفشل
  }
}
