import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/analytics/funnel_report.dart';

/// اللوحة المحلّية (G2): تحسب قِمع الثقة من مجرى أحداث `DebugAnalytics` بلا شبكة.
void main() {
  // أربع جلسات تمثيلية:
  final sessionA = <AnalyticsEvent>[ // جديدة سعيدة: بذر → انخراط → إتمام
    const FlowStarted('onboarding'),
    const PlanSeeded(
        confidence: 80,
        itemCount: 3,
        missingCount: 0,
        total: 1200,
        withinBudget: true),
    const ItemPinned('bed'),
    const PlanFinalized(confidence: 85, itemCount: 3, pinnedCount: 1, edits: 1),
  ];
  final sessionB = <AnalyticsEvent>[ // بذرت ولم تنخرط ولم تُتِمّ
    const FlowStarted('onboarding'),
    const PlanSeeded(
        confidence: 60,
        itemCount: 2,
        missingCount: 1,
        total: 900,
        withinBudget: true),
  ];
  final sessionC = <AnalyticsEvent>[ // تسرّبت
    const FlowStarted('sample_plan'),
    const PlanSeeded(
        confidence: 55,
        itemCount: 2,
        missingCount: 1,
        total: 800,
        withinBudget: false),
    const SessionAbandoned(lastStep: 'plan', lastConfidence: 55),
  ];
  final sessionD = <AnalyticsEvent>[ // عادت لخطتها ثم انخرطت ونقرت للتاجر (بلا بذرة جديدة)
    const PlanRestored(confidence: 70, itemCount: 3, decisions: 2),
    const ItemSwapped('sofa'),
    const MerchantClicked('prod_1', category: 'sofa'),
  ];

  test('a single session (DebugAnalytics.events) reads as one funnel row', () {
    final a = DebugAnalytics(log: false);
    for (final e in sessionA) {
      a.track(e);
    }
    final r = FunnelReport.fromSession(a.events);
    expect(r.sessions, 1);
    expect(r.started, 1);
    expect(r.seeded, 1);
    expect(r.engaged, 1);
    expect(r.finalized, 1);
    expect(r.activation, 1.0);
  });

  group('across sessions', () {
    final r = FunnelReport.fromSessions([sessionA, sessionB, sessionC, sessionD]);

    test('stage presence is counted once per session', () {
      expect(r.sessions, 4);
      expect(r.started, 3); // A, B, C
      expect(r.seeded, 3); // A, B, C — NOT D (restored is not a seed)
      expect(r.engaged, 2); // A, D
      expect(r.finalized, 1); // A
      expect(r.restored, 1); // D
      expect(r.abandoned, 1); // C
      expect(r.merchantIntentSessions, 1); // D
    });

    test('activation = finalized / started', () {
      expect(r.activation, closeTo(1 / 3, 1e-9));
      expect(r.overallCompletion, closeTo(1 / 3, 1e-9));
    });

    test('return rate excludes restored from the seed base', () {
      // restored / (seeded + restored) = 1 / (3 + 1)
      expect(r.returnRate, closeTo(0.25, 1e-9));
    });

    test('step rates are presence-based', () {
      expect(r.seedRate, closeTo(1.0, 1e-9)); // 3/3
      expect(r.engageRate, closeTo(2 / 3, 1e-9)); // engaged 2 / seeded 3
      expect(r.finalizeRate, closeTo(0.5, 1e-9)); // finalized 1 / engaged 2
      expect(r.merchantIntentRate, closeTo(1 / 3, 1e-9)); // 1 / started 3
    });

    test('format renders a readable console dashboard without throwing', () {
      final text = r.format();
      expect(text, contains('activation'));
      expect(text, contains('trust funnel'));
      expect(text, contains('return'));
    });
  });

  test('an empty stream yields zeroed rates, never a divide-by-zero', () {
    final r = FunnelReport.fromSessions(const []);
    expect(r.sessions, 0);
    expect(r.activation, 0);
    expect(r.returnRate, 0);
  });
}
