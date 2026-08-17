import '../../core/errors/result.dart';
import '../../shared/models/models.dart';
import '../contracts/llm_extraction_service.dart';
import '../models/normalized_input.dart';

/// تنفيذ وهمي لاستخراج الـ LLM (mock-first).
///
/// يقوم باستخراج حتمي خفيف من النص العربي (أبعاد، ميزانية، عناصر، ألوان، نمط)
/// لإنتاج نموذج منظّم مطابق لـ json_schema.md — **دون أي توصيات** (يملؤها المحرّك
/// لاحقًا). يحاكي سلوك مزوّد حقيقي مع structured outputs.
///
/// **مبدأ لا يُكسَر:** يُخرِج بيانات فقط، وحقول التوصيات تبقى فارغة (افتراض
/// `FurnishingProject`). ما لا يُلتقَط بنيويًّا لا يُسقَط بصمت: خارج نطاق الكتالوج
/// (مرتبة/ستائر/ثلاجة) والخامات ومقاسات القطع تُسجَّل في `analysis.warnings`
/// (قناة الخسارة المعلنة — ai_review_report.md · R-1/R-2).
class MockLlmExtractionService implements LlmExtractionService {
  const MockLlmExtractionService({this.uuidFactory});

  final String Function()? uuidFactory;

  @override
  Future<Result<FurnishingProject>> extract(NormalizedInput input) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final text = _normalizeText(input.rawText);

    final room = _extractRoom(text);
    final budget = _extractBudget(text);
    final style = _extractStyle(text);
    final items = _extractItems(text);
    final warnings = _warnings(text);

    var confidence = 0.7;
    if (room.widthM > 0 && room.lengthM > 0) confidence += 0.1;
    if (budget.hasBudget) confidence += 0.1;
    if (items.essential.isNotEmpty) confidence += 0.05;
    confidence = confidence.clamp(0.0, 0.95);

    final analysis = RoomAnalysis(
      summary: _summary(room, budget, items),
      warnings: warnings,
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

  // ─────────────────────────── الغرفة ───────────────────────────

  Room _extractRoom(String t) {
    var roomType = RoomType.other;
    if (t.contains('نوم')) {
      roomType = RoomType.bedroom;
    } else if (t.contains('معيشة') || t.contains('صالة')) {
      roomType = RoomType.livingRoom;
    } else if (t.contains('مجلس') || t.contains('ضيوف')) {
      roomType = RoomType.guestRoom;
    }

    // أوّل زوج أبعاد **معقول كغرفة** (كلا الطرفين 1..30م). هكذا لا يُقرأ مقاس
    // قطعة «120×200» ولا سنتيمترات «400×350» أبعادًا للغرفة (G-06).
    double w = 0, l = 0;
    for (final m in _dimRe.allMatches(t)) {
      final a = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
      final b = double.tryParse(m.group(2)!.replaceAll(',', '.')) ?? 0;
      if (a >= 1.0 && a <= 30.0 && b >= 1.0 && b <= 30.0) {
        w = a;
        l = b;
        break;
      }
    }
    return Room(widthM: w, lengthM: l, roomType: roomType);
  }

  // الفاصل العشري يقبل النقطة أو الفاصلة (بعد أن يوحّد `٫` إلى `.`).
  static final RegExp _dimRe =
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:في|x|×|\*)\s*(\d+(?:[.,]\d+)?)');

  // ─────────────────────────── الميزانية ───────────────────────────

  /// يلتقط الميزانية بثلاث صيغ متدرّجة: رقم+عملة، كلمة ميزانية+رقم، ثم «N ألف».
  /// يدعم مضاعِف «ألف/آلاف» (بعد طيّ الهمزة: الف/الاف) — يعالج G-01.
  Budget _extractBudget(String t) {
    final flexible =
        t.contains('تسمح') || t.contains('مرن') || t.contains('لو سمح');

    double? amount;
    final a = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*(الف|الاف)?\s*(?:ريال|sar|﷼)',
            caseSensitive: false)
        .firstMatch(t);
    if (a != null) amount = _amount(a.group(1)!, a.group(2));

    if (amount == null) {
      final b = RegExp(
              r'(?:ميزاني\S*|بحدود|حدود|حدد|خلها|خليها|اجعلها)\D{0,6}(\d[\d,]*(?:\.\d+)?)\s*(الف|الاف)?')
          .firstMatch(t);
      if (b != null) amount = _amount(b.group(1)!, b.group(2));
    }

    if (amount == null) {
      final c = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*(الف|الاف)').firstMatch(t);
      if (c != null) amount = _amount(c.group(1)!, c.group(2));
    }

    return Budget(maxTotal: amount ?? 0, flexible: flexible);
  }

  double _amount(String number, String? multiplier) {
    final v = double.tryParse(number.replaceAll(',', '')) ?? 0;
    return multiplier != null ? v * 1000 : v;
  }

  // ─────────────────────────── النمط والألوان ───────────────────────────

  StylePreferences _extractStyle(String t) {
    final preferred = <String>[];
    if (t.contains('مودرن') || t.contains('عصري')) preferred.add('modern');
    if (t.contains('كلاسيك')) preferred.add('classic');
    if (t.contains('مينمال') || t.contains('بسيط')) preferred.add('minimal');
    return StylePreferences(preferred: preferred, colors: _extractColors(t));
  }

  /// ألوان/درجات المشروع → `style.colors` (G-02 · R-2). صفات القطعة الواحدة من
  /// خامة/تشطيب تعيش في `warnings` لا هنا.
  List<String> _extractColors(String t) {
    const colors = <String, List<String>>{
      'black': ['اسود'],
      'white': ['ابيض'],
      'beige': ['بيج'],
      'gray': ['رمادي', 'رصاصي'],
      'brown': ['بني'],
      'walnut': ['جوز'],
      'gold': ['ذهبي'],
      'blue': ['ازرق', 'كحلي', 'نيلي'],
      'green': ['اخضر'],
      'red': ['احمر'],
      'pink': ['وردي', 'زهري'],
      'cream': ['كريمي'],
    };
    final found = <String>{};
    colors.forEach((canonical, keys) {
      if (keys.any(t.contains)) found.add(canonical);
    });
    // ترتيب معجميّ حتميّ (القيم فريدة، فلا تعادل — لا مصيدة List.sort).
    final list = found.toList()..sort();
    return list;
  }

  // ─────────────────────────── العناصر ───────────────────────────

  RequestedItems _extractItems(String t) {
    // فصل الجزء الاختياري: ما بعد «إذا/إن/لو ... تسمح/الميزانية».
    final split = RegExp(r'(?:اذا|ان|لو).{0,15}?(?:تسمح|سمح|الميزاني)').firstMatch(t);
    final essentialText = split == null ? t : t.substring(0, split.start);
    final optionalText = split == null ? '' : t.substring(split.start);

    return RequestedItems(
      essential: _detect(essentialText),
      optional: _detect(optionalText),
    );
  }

  // تُطبَّع المفاتيح بنفس تطبيع النصّ (همزة/ألف مقصورة/حركات).
  static const Map<String, List<String>> _itemKeywords = {
    'bed': ['سرير', 'تخت'],
    'sofa': ['كنب', 'اريكة', 'صوفا', 'كرسي'],
    'rug': ['سجاد', 'سجادة'],
    'table': ['طاولة', 'مكتب'],
    'lamp': ['اضاء', 'مصباح', 'ثريا', 'نجف', 'ابليك', 'اباجور'],
    'storage': [
      'تخزين', 'خزانة', 'دولاب', 'كومدينو', 'كومدينه', 'ملابس', 'تسريح',
      'كونسول', 'رفوف',
    ],
  };

  List<RequestedItem> _detect(String segment) {
    if (segment.isEmpty) return const [];
    final result = <RequestedItem>[];
    _itemKeywords.forEach((type, keys) {
      // موضع أوّل مفردة مطابقة لهذا النوع.
      var idx = -1, klen = 0;
      for (final k in keys) {
        final j = segment.indexOf(k);
        if (j >= 0 && (idx < 0 || j < idx)) {
          idx = j;
          klen = k.length;
        }
      }
      if (idx >= 0) {
        // القيود من نافذة حول المفردة لا من الجملة كاملة — فلا يسري «صغيرة»
        // من الثلاجة على السرير (G-08).
        final start = (idx - 12) < 0 ? 0 : idx - 12;
        final end =
            (idx + klen + 12) > segment.length ? segment.length : idx + klen + 12;
        result.add(RequestedItem(
          type: type,
          constraints: _constraints(segment.substring(start, end)),
          quantity: 1,
        ));
      }
    });
    return result;
  }

  List<String> _constraints(String window) {
    final c = <String>[];
    if (window.contains('صغير')) c.add('small');
    if (window.contains('كبير')) c.add('large');
    if (window.contains('مزدوج') || window.contains('دبل')) c.add('double');
    if (window.contains('مفرد')) c.add('single');
    return c;
  }

  // ─────────────────────── التحذيرات (قناة الخسارة المعلنة) ───────────────────────

  /// لا يُسقَط شيء بصمت (R-1): خارج نطاق الكتالوج، الخامات، ومقاسات القطع
  /// تُدرَج تحذيرات ليعلنها المحرّك والواجهة لاحقًا.
  List<String> _warnings(String t) {
    final warnings = <String>[];

    final oos = _outOfScope(t);
    if (oos.isNotEmpty) {
      warnings.add('خارج نطاق الكتالوج (تُدرَج في قائمة النطاق): ${oos.join('، ')}');
    }

    final mats = _materials(t);
    if (mats.isNotEmpty) {
      warnings.add('خامات مذكورة (تُنسب للقطع لاحقًا): ${mats.join('، ')}');
    }

    for (final m in _dimIntRe.allMatches(t)) {
      final a = int.tryParse(m.group(1)!) ?? 0;
      final b = int.tryParse(m.group(2)!) ?? 0;
      if (!(a >= 1 && a <= 30 && b >= 1 && b <= 30)) {
        warnings.add('مقاس قطعة مذكور: $a×$b');
      }
    }

    return warnings;
  }

  static final RegExp _dimIntRe = RegExp(r'(\d+)\s*(?:في|x|×|\*)\s*(\d+)');

  static const Map<String, List<String>> _outOfScopeKeywords = {
    'مرتبة': ['مرتبة', 'مرتبه', 'فراش', 'فرشة', 'فرشه'],
    'ستائر': ['ستائر', 'ستارة', 'ستاره'],
    'ثلاجة': ['ثلاجة', 'ثلاجه', 'براد'],
    'غسالة': ['غسالة', 'غساله'],
    'مكيّف': ['مكيف', 'تكييف'],
  };

  List<String> _outOfScope(String t) {
    final r = <String>[];
    _outOfScopeKeywords.forEach((label, keys) {
      if (keys.any(t.contains)) r.add(label);
    });
    return r;
  }

  static const Map<String, String> _materialKeywords = {
    'معدني': 'معدني',
    'خشب': 'خشب',
    'جلد': 'جلد',
    'قماش': 'قماش',
    'كتان': 'كتان',
    'رخام': 'رخام',
    'زجاج': 'زجاج',
  };

  List<String> _materials(String t) {
    final r = <String>[];
    _materialKeywords.forEach((key, label) {
      if (t.contains(key)) r.add(label);
    });
    return r;
  }

  // ─────────────────────────── ملخّص وأدوات ───────────────────────────

  String _summary(Room room, Budget budget, RequestedItems items) {
    final parts = <String>[];
    if (room.areaM2 > 0) {
      parts.add(
          '${room.roomType.arabicLabel} بمساحة ~${room.areaM2.toStringAsFixed(0)}م²');
    }
    if (budget.hasBudget) {
      parts.add('ميزانية ${budget.maxTotal.toStringAsFixed(0)} ${budget.currency}');
    }
    if (items.essential.isNotEmpty) {
      parts.add('${items.essential.length} عناصر أساسية');
    }
    return parts.isEmpty ? 'طلب تأثيث' : parts.join('، ');
  }

  /// توحيد النصّ قبل الاستخراج: أرقام عربية-هندية → لاتينية، الفاصلة العشرية
  /// العربية `٫` → `.`، فاصل الآلاف `٬` يُحذف، طيّ الهمزة (أ/إ/آ→ا) والألف
  /// المقصورة (ى→ي) وحذف التطويل والحركات. يعالج G-03 ويثبّت مطابقة المفردات.
  String _normalizeText(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final ch in s.split('')) {
      final idx = arabic.indexOf(ch);
      if (idx >= 0) {
        buffer.write(idx.toString());
      } else if (ch == '٫') {
        buffer.write('.'); // الفاصلة العشرية العربية
      } else if (ch == '٬') {
        // فاصل الآلاف العربي — يُحذف
      } else {
        buffer.write(ch);
      }
    }
    var t = buffer.toString();
    t = t.replaceAll(RegExp('[أإآ]'), 'ا');
    t = t.replaceAll('ى', 'ي').replaceAll('ـ', '');
    t = t.replaceAll(RegExp('[ً-ْ]'), ''); // الحركات
    return t;
  }

  static String _fallbackId() =>
      'proj_${DateTime.now().millisecondsSinceEpoch}';
}
