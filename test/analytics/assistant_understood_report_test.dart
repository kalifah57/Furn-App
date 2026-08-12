import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/analytics/assistant_understood_report.dart';

/// G5: معدّل الفهم من assistant_command — يغذّي U2 لمسار ٣.
void main() {
  final events = <AnalyticsEvent>[
    const AssistantCommand(intent: 'add', understood: true),
    const AssistantCommand(intent: 'set_budget', understood: true),
    const AssistantCommand(intent: 'unknown', understood: false),
    const AssistantCommand(intent: 'remove', understood: true),
    const AssistantCommand(intent: 'unknown', understood: false),
    const FlowStarted('onboarding'), // ضجيج — يجب تجاهله
  ];

  test('counts only assistant_command events', () {
    final r = AssistantUnderstoodReport.fromEvents(events);
    expect(r.total, 5);
    expect(r.understood, 3);
    expect(r.notUnderstood, 2);
  });

  test('understood-rate and its complement', () {
    final r = AssistantUnderstoodReport.fromEvents(events);
    expect(r.understoodRate, closeTo(0.6, 1e-9));
    expect(r.notUnderstoodRate, closeTo(0.4, 1e-9));
  });

  test('intent distribution, ranked stably (count desc, name asc)', () {
    final r = AssistantUnderstoodReport.fromEvents(events);
    expect(r.byIntent, {'add': 1, 'set_budget': 1, 'unknown': 2, 'remove': 1});
    expect(r.intentsRanked.first.key, 'unknown'); // الأعلى عددًا
    // فاصل التعادل بالاسم: add < remove < set_budget
    expect(r.intentsRanked.map((e) => e.key).toList(),
        ['unknown', 'add', 'remove', 'set_budget']);
  });

  test('empty stream is safe', () {
    final r = AssistantUnderstoodReport.fromEvents(const []);
    expect(r.total, 0);
    expect(r.understoodRate, 0);
    expect(r.format(), contains('assistant commands: 0'));
  });
}
