import 'analytics.dart';

/// تقرير معدّل الفهم (understood-rate) لأوامر المساعد — يغذّي توسيع مُحلِّل
/// مسار ٣ (U2). يُحسب محليًّا من `assistant_command {intent, understood}`.
///
/// **حدّ الخصوصية:** لا يحمل نصّ الأمر الخام (PII) — فقط النيّة المُعدَّلة ونجاح
/// الفهم. لذلك يعطي **المعدّل والاتجاه** لا الأمثلة الفاشلة؛ جمع الأمثلة يبقى في
/// مجموعة اختبار مسار ٣ الخاصّة، لا في قياس الإنتاج.
class AssistantUnderstoodReport {
  const AssistantUnderstoodReport({
    required this.total,
    required this.understood,
    required this.byIntent,
  });

  /// إجمالي أحداث `assistant_command`.
  final int total;

  /// كم منها فُهم (`understood == true`).
  final int understood;

  /// توزيع النيّة على كل الأوامر (مفتاح `intent` → عدد).
  final Map<String, int> byIntent;

  int get notUnderstood => total - understood;
  double get understoodRate => total == 0 ? 0 : understood / total;
  double get notUnderstoodRate => total == 0 ? 0 : notUnderstood / total;

  /// يبني التقرير من مجرى أحداث (مثل `DebugAnalytics.events`)؛ يتجاهل ما عدا
  /// `assistant_command`.
  factory AssistantUnderstoodReport.fromEvents(Iterable<AnalyticsEvent> events) {
    var total = 0;
    var understood = 0;
    final byIntent = <String, int>{};
    for (final e in events.whereType<AssistantCommand>()) {
      total++;
      if (e.understood) understood++;
      byIntent.update(e.intent, (v) => v + 1, ifAbsent: () => 1);
    }
    return AssistantUnderstoodReport(
      total: total,
      understood: understood,
      byIntent: byIntent,
    );
  }

  /// النيّات مرتّبة تنازليًّا بالعدد، وفاصل تعادل مستقرّ بالاسم (تفاديًا لعدم
  /// استقرار الترتيب — مصيدة CI في الميثاق).
  List<MapEntry<String, int>> get intentsRanked {
    final entries = byIntent.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }

  String format() {
    final intents =
        intentsRanked.map((e) => '${e.key}=${e.value}').join(' ');
    return [
      'assistant commands: $total',
      'understood: $understood (${_pct(understoodRate)})   '
          'not understood: $notUnderstood (${_pct(notUnderstoodRate)})',
      'by intent: $intents',
    ].join('\n');
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}
