import 'analytics.dart';

/// أسماء أحداث مرحلة «الانخراط» (engaged) — تفاعل فعليّ بالخطة داخل حلقة الثقة.
const _engagedEvents = <String>{
  'item_pinned',
  'item_rejected',
  'item_swapped',
  'budget_changed',
};

/// تقرير قِمع الثقة — يُحسب **محليًّا** من مجرى أحداث، بلا شبكة وبلا PII.
///
/// المصدر الآن: `DebugAnalytics.events` (لكل جلسة قائمة أحداثها). حين تُفتح نقطة
/// النهاية (قرار المؤسّس F4) يُعبَّر عن المنطق نفسه بـ SQL على المستودع دون لمس
/// نقاط النداء — انظر `docs/analytics_funnel_dashboards.md`. القياس يلاحظ ولا يغيّر.
///
/// العدّ **على مستوى الجلسة** (حضور مرحلة، لا عدد أحداث خام): جلسة تُحسب مرّة
/// واحدة لكل مرحلة بلغتها. النِّسَب المتسلسلة (seed/engage/finalize) «حضور مرحلة»
/// لا تسلسلًا زمنيًّا صارمًا (قد تنخرط جلسة مُستعادة دون بذرة) — النجم الشمالي
/// (التفعيل) والإتمام الكلّي هما الرقمان المتينان.
class FunnelReport {
  const FunnelReport({
    required this.sessions,
    required this.started,
    required this.seeded,
    required this.engaged,
    required this.finalized,
    required this.restored,
    required this.abandoned,
    required this.merchantIntentSessions,
  });

  /// عدد الجلسات المرصودة.
  final int sessions;

  /// جلسات مرّت بكل مرحلة (عدّ جلسات مميّزة).
  final int started; // flow_started
  final int seeded; // plan_seeded فقط — **لا** plan_restored (عدّها بذرة يضخّم القِمع)
  final int engaged; // ≥1 من _engagedEvents
  final int finalized; // plan_finalized
  final int restored; // plan_restored — إشارة العودة
  final int abandoned; // session_abandoned
  final int merchantIntentSessions; // جلسات فيها merchant_click

  /// **التفعيل = plan_finalized / flow_started** (النجم الشمالي).
  double get activation => _ratio(finalized, started);

  /// تحوّلات القِمع الأربعة (حضور مرحلة على السابقة).
  double get seedRate => _ratio(seeded, started);
  double get engageRate => _ratio(engaged, seeded);
  double get finalizeRate => _ratio(finalized, engaged);
  double get overallCompletion => _ratio(finalized, started);

  /// **العودة = plan_restored / (plan_seeded + plan_restored)** — كم يعود لخطته.
  double get returnRate => _ratio(restored, seeded + restored);

  /// نيّة الشراء لكل جلسة بادئة (مدخل قِمع الإيراد).
  double get merchantIntentRate => _ratio(merchantIntentSessions, started);

  static double _ratio(int numerator, int denominator) =>
      denominator == 0 ? 0 : numerator / denominator;

  /// يبني التقرير من عدّة جلسات (كل جلسة = قائمة أحداثها، كما في `DebugAnalytics.events`).
  factory FunnelReport.fromSessions(Iterable<List<AnalyticsEvent>> sessions) {
    var count = 0,
        started = 0,
        seeded = 0,
        engaged = 0,
        finalized = 0,
        restored = 0,
        abandoned = 0,
        merchant = 0;
    for (final events in sessions) {
      count++;
      final names = {for (final e in events) e.name};
      if (names.contains('flow_started')) started++;
      if (names.contains('plan_seeded')) seeded++;
      if (names.any(_engagedEvents.contains)) engaged++;
      if (names.contains('plan_finalized')) finalized++;
      if (names.contains('plan_restored')) restored++;
      if (names.contains('session_abandoned')) abandoned++;
      if (names.contains('merchant_click')) merchant++;
    }
    return FunnelReport(
      sessions: count,
      started: started,
      seeded: seeded,
      engaged: engaged,
      finalized: finalized,
      restored: restored,
      abandoned: abandoned,
      merchantIntentSessions: merchant,
    );
  }

  /// راحةٌ للجلسة المحلّية الواحدة (`DebugAnalytics.events`).
  factory FunnelReport.fromSession(List<AnalyticsEvent> events) =>
      FunnelReport.fromSessions([events]);

  /// تنسيق نصّي للوحة محلّية على الـ console — يُطبع من `DebugAnalytics`.
  String format() => [
        'sessions=$sessions',
        'activation (finalized/started) = ${_pct(activation)}  ($finalized/$started)',
        'trust funnel: started=$started → seeded=$seeded → engaged=$engaged → finalized=$finalized',
        '  step rates: seed=${_pct(seedRate)}  engage=${_pct(engageRate)}  finalize=${_pct(finalizeRate)}  overall=${_pct(overallCompletion)}',
        'return (restored/(seeded+restored)) = ${_pct(returnRate)}  (restored=$restored)',
        'abandoned=$abandoned   merchant intent=${_pct(merchantIntentRate)}  ($merchantIntentSessions/$started)',
      ].join('\n');

  static String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}
