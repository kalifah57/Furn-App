import '../../core/errors/result.dart';
import '../../shared/models/models.dart';
import '../contracts/llm_extraction_service.dart';
import '../models/normalized_input.dart';

/// تنفيذ وهمي لاستخراج الـ LLM (mock-first).
///
/// يقوم باستخراج حتمي خفيف من النص العربي (أبعاد، ميزانية، عناصر، نمط) لإنتاج
/// نموذج منظّم مطابق لـ json_schema.md — **دون أي توصيات** (يملؤها المحرّك لاحقًا).
/// يحاكي سلوك مزوّد حقيقي مع structured outputs.
class MockLlmExtractionService implements LlmExtractionService {
  const MockLlmExtractionService({this.uuidFactory});

  final String Function()? uuidFactory;

  @override
  Future<Result<FurnishingProject>> extract(NormalizedInput input) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final text = _normalizeDigits(input.rawText);

    final room = _extractRoom(text, input);
    final budget = _extractBudget(text);
    final style = _extractStyle(text);
    final items = _extractItems(text);

    var confidence = 0.7;
    if (room.widthM > 0 && room.lengthM > 0) confidence += 0.1;
    if (budget.hasBudget) confidence += 0.1;
    if (items.essential.isNotEmpty) confidence += 0.05;
    confidence = confidence.clamp(0.0, 0.95);

    final analysis = RoomAnalysis(
      summary: _summary(room, budget, items),
      confidenceScore: double.parse(confidence.toStringAsFixed(2)),
    );

    return Ok(FurnishingProject(
      projectId: (uuidFactory ?? _fallbackId)(),
      room: room,
      budget: budget,
      style: style,
      items: items,
      analysis: analysis,
    ));
  }

  Room _extractRoom(String text, NormalizedInput input) {
    var roomType = RoomType.other;
    if (text.contains('نوم')) {
      roomType = RoomType.bedroom;
    } else if (text.contains('معيشة') || text.contains('صالة')) {
      roomType = RoomType.livingRoom;
    } else if (text.contains('مجلس') || text.contains('ضيوف')) {
      roomType = RoomType.guestRoom;
    }

    double w = 0, l = 0;
    final dim = RegExp(r'(\d+(?:\.\d+)?)\s*(?:في|x|×|\*)\s*(\d+(?:\.\d+)?)')
        .firstMatch(text);
    if (dim != null) {
      w = double.tryParse(dim.group(1)!) ?? 0;
      l = double.tryParse(dim.group(2)!) ?? 0;
    }
    return Room(widthM: w, lengthM: l, roomType: roomType);
  }

  Budget _extractBudget(String text) {
    final m = RegExp(r'(\d{2,6}(?:\.\d+)?)\s*(?:ريال|ر\.?\s?س|sar|﷼)',
            caseSensitive: false)
        .firstMatch(text);
    final flexible = text.contains('تسمح') ||
        text.contains('مرن') ||
        text.contains('لو سمح');
    if (m == null) return Budget(flexible: flexible);
    return Budget(
      maxTotal: double.tryParse(m.group(1)!) ?? 0,
      flexible: flexible,
    );
  }

  StylePreferences _extractStyle(String text) {
    final preferred = <String>[];
    if (text.contains('مودرن') || text.contains('عصري')) preferred.add('modern');
    if (text.contains('كلاسيك')) preferred.add('classic');
    if (text.contains('مينمال') || text.contains('بسيط')) preferred.add('minimal');
    return StylePreferences(preferred: preferred);
  }

  RequestedItems _extractItems(String text) {
    // فصل الجزء الاختياري: ما بعد عبارة «إذا/إن ... تسمح/الميزانية».
    final split = RegExp(r'(?:إذا|إن|لو).{0,15}?(?:تسمح|سمح|الميزانية)')
        .firstMatch(text);
    final essentialText = split == null ? text : text.substring(0, split.start);
    final optionalText = split == null ? '' : text.substring(split.start);

    return RequestedItems(
      essential: _detect(essentialText),
      optional: _detect(optionalText),
    );
  }

  static const Map<String, List<String>> _itemKeywords = {
    'bed': ['سرير'],
    'sofa': ['كنب', 'أريكة', 'صوفا', 'كرسي'],
    'rug': ['سجاد', 'سجادة'],
    'table': ['طاولة', 'مكتب'],
    'lamp': ['إضاء', 'مصباح', 'ثريا'],
    'storage': ['تخزين', 'خزانة', 'دولاب'],
  };

  List<RequestedItem> _detect(String segment) {
    if (segment.isEmpty) return const [];
    final result = <RequestedItem>[];
    _itemKeywords.forEach((type, keys) {
      if (keys.any(segment.contains)) {
        result.add(RequestedItem(
          type: type,
          constraints: _constraints(segment),
          quantity: 1,
        ));
      }
    });
    return result;
  }

  List<String> _constraints(String segment) {
    final c = <String>[];
    if (segment.contains('صغير')) c.add('small');
    if (segment.contains('كبير')) c.add('large');
    if (segment.contains('مزدوج') || segment.contains('دبل')) c.add('double');
    if (segment.contains('مفرد')) c.add('single');
    return c;
  }

  String _summary(Room room, Budget budget, RequestedItems items) {
    final parts = <String>[];
    if (room.areaM2 > 0) {
      parts.add('${room.roomType.arabicLabel} بمساحة ~${room.areaM2.toStringAsFixed(0)}م²');
    }
    if (budget.hasBudget) {
      parts.add('ميزانية ${budget.maxTotal.toStringAsFixed(0)} ${budget.currency}');
    }
    if (items.essential.isNotEmpty) {
      parts.add('${items.essential.length} عناصر أساسية');
    }
    return parts.isEmpty ? 'طلب تأثيث' : parts.join('، ');
  }

  /// تحويل الأرقام العربية-الهندية إلى لاتينية للتحليل.
  String _normalizeDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final ch in s.split('')) {
      final idx = arabic.indexOf(ch);
      buffer.write(idx >= 0 ? idx.toString() : ch);
    }
    return buffer.toString();
  }

  static String _fallbackId() =>
      'proj_${DateTime.now().millisecondsSinceEpoch}';
}
