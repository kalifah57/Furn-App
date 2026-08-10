import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/analytics/http_analytics.dart';

/// The sink that finally makes activation visible. The cases worth testing are
/// the ones that would otherwise lose data silently or take a screen down with
/// them: a dropped network, a full buffer, a withdrawn consent.
void main() {
  final endpoint = Uri.parse('http://localhost:8080/events');

  late List<String> sent;
  late int failuresLeft;

  Future<void> poster(Uri url, String body) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw Exception('network down');
    }
    sent.add(body);
  }

  setUp(() {
    sent = [];
    failuresLeft = 0;
  });

  HttpAnalytics sink({
    bool consent = true,
    int batchSize = 20,
    int maxBuffer = 200,
  }) =>
      HttpAnalytics(
        endpoint: endpoint,
        post: poster,
        sessionId: 'session-1',
        consent: consent,
        batchSize: batchSize,
        maxBuffer: maxBuffer,
        flushInterval: const Duration(days: 1), // الوقت لا يُطلق الإرسال هنا
      );

  List<Map<String, Object?>> eventsIn(String body) =>
      ((jsonDecode(body) as Map)['events'] as List)
          .cast<Map<String, Object?>>();

  group('batching', () {
    test('nothing leaves before the batch is full', () {
      final a = sink(batchSize: 3);
      a.track(const FlowStarted('onboarding'));
      a.track(const FlowStarted('onboarding'));
      expect(sent, isEmpty);
      expect(a.pending, 2);
    });

    test('a full batch is sent', () async {
      final a = sink(batchSize: 2);
      a.track(const FlowStarted('onboarding'));
      a.track(const PlanShared(80));
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      expect(eventsIn(sent.single), hasLength(2));
      expect(a.pending, 0);
    });

    test('flush sends a partial batch', () async {
      final a = sink(batchSize: 50);
      a.track(const FlowStarted('onboarding'));
      await a.flush();
      expect(eventsIn(sent.single), hasLength(1));
    });

    test('flushing an empty buffer sends nothing', () async {
      await sink().flush();
      expect(sent, isEmpty);
    });
  });

  group('the payload', () {
    test('carries name, session, timestamp and params', () async {
      final a = sink();
      a.track(const NeedUnmet(rawType: 'ثلاجة', reason: 'out_of_scope'));
      await a.flush();

      final e = eventsIn(sent.single).single;
      expect(e['name'], 'need_unmet');
      expect(e['session_id'], 'session-1');
      expect(DateTime.tryParse(e['at']! as String), isNotNull);
      expect((e['params']! as Map)['raw_type'], 'ثلاجة');
    });

    test('the timestamp is capture time, not send time', () async {
      final a = sink(batchSize: 50);
      a.track(const FlowStarted('onboarding'));
      final captured = DateTime.now().toUtc();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await a.flush();

      final at = DateTime.parse(eventsIn(sent.single).single['at']! as String);
      // Sent 30ms later, but stamped when it happened.
      expect(at.isAfter(captured.add(const Duration(milliseconds: 20))), isFalse);
    });
  });

  group('consent', () {
    test('without consent nothing is stored, so nothing can leak later',
        () async {
      final a = sink(consent: false);
      a.track(const FlowStarted('onboarding'));
      a.track(const PlanShared(80));
      expect(a.pending, 0);
      await a.flush();
      expect(sent, isEmpty);
    });
  });

  group('a network that drops', () {
    test('a failed send is retried, not lost', () async {
      failuresLeft = 1;
      final a = sink(batchSize: 50);
      a.track(const FlowStarted('onboarding'));

      await a.flush(); // fails; the batch goes back
      expect(sent, isEmpty);
      expect(a.pending, 1);

      await a.flush(); // succeeds
      expect(eventsIn(sent.single), hasLength(1));
    });

    test('track never throws, whatever the network does', () {
      failuresLeft = 99;
      final a = sink(batchSize: 1);
      // Measurement observes the trust loop; it must never break it.
      expect(() => a.track(const FlowStarted('onboarding')), returnsNormally);
    });

    test('events accumulate across failures and go out together', () async {
      failuresLeft = 2;
      final a = sink(batchSize: 50);
      a.track(const FlowStarted('a'));
      await a.flush();
      a.track(const FlowStarted('b'));
      await a.flush();
      await a.flush();
      expect(eventsIn(sent.single).length, 2);
    });
  });

  group('the buffer is bounded', () {
    test('an offline session cannot grow without limit', () {
      final a = sink(batchSize: 1000, maxBuffer: 5);
      for (var i = 0; i < 50; i++) {
        a.track(PlanShared(i));
      }
      expect(a.pending, 5);
    });

    test('the newest events survive, the oldest are dropped', () async {
      final a = sink(batchSize: 1000, maxBuffer: 3);
      for (var i = 0; i < 6; i++) {
        a.track(PlanShared(i));
      }
      await a.flush();
      final confidences = eventsIn(sent.single)
          .map((e) => (e['params']! as Map)['confidence'])
          .toList();
      expect(confidences, [3, 4, 5]);
    });
  });

  group('fan-out', () {
    test('every sink receives the event', () {
      final debug = DebugAnalytics(log: false);
      final other = DebugAnalytics(log: false);
      FanOutAnalytics([debug, other]).track(const FlowStarted('onboarding'));
      expect(debug.names, ['flow_started']);
      expect(other.names, ['flow_started']);
    });

    test('one broken sink does not silence the others', () {
      final good = DebugAnalytics(log: false);
      FanOutAnalytics([_ThrowingAnalytics(), good])
          .track(const FlowStarted('onboarding'));
      expect(good.names, ['flow_started']);
    });
  });
}

class _ThrowingAnalytics implements Analytics {
  @override
  void track(AnalyticsEvent event) => throw Exception('broken sink');
}
