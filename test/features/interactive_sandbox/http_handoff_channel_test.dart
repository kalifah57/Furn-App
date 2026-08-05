import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/features/interactive_sandbox/data/http_handoff_channel.dart';
import 'package:furn_app/features/interactive_sandbox/domain/handoff_session.dart';

/// Polling client against the local rendezvous. The interesting cases are the
/// ones a real LAN produces: a phone that has not written yet, a dropped
/// request, a corrupt body, and measurements that are physically impossible.
void main() {
  late DateTime clock;
  late List<String?> replies;
  late List<String> posted;

  Uri base = Uri.parse('http://192.168.1.20:8080');

  HttpHandoffChannel channelWith({Duration ttl = const Duration(minutes: 10)}) =>
      HttpHandoffChannel(
        baseUrl: base,
        newSessionId: () => 'session_fixed',
        pollInterval: Duration.zero,
        now: () => clock,
        get: (_) async {
          if (replies.isEmpty) return null;
          final next = replies.removeAt(0);
          if (next == '__throw__') throw Exception('network dropped');
          return next;
        },
        post: (url, body) async => posted.add('$url|$body'),
      );

  setUp(() {
    clock = DateTime(2026, 8, 6, 10);
    replies = [];
    posted = [];
  });

  String phone(String status, {Map<String, Object?>? room, String? failure}) =>
      jsonEncode({
        'status': status,
        if (room != null) 'room': room,
        if (failure != null) 'failure': failure,
      });

  const goodRoom = {
    'width_cm': 382.4,
    'length_cm': 421.9,
    'ceiling_cm': 271.0,
    'confidence': 0.95,
  };

  test('the pairing code addresses the session on the server', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    await c.publish(session.copyWith(status: HandoffStatus.scanning));

    expect(posted.single, startsWith('http://192.168.1.20:8080/handoff/'));
    expect(posted.single, contains(session.pairingCode));
  });

  test('opening writes nothing — sessions appear on first phone write', () async {
    final c = channelWith();
    await c.open();
    expect(posted, isEmpty);
  });

  test('a scan the phone completes arrives as dimensions', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = [
      null, // phone has not opened the app yet
      phone('linked'),
      phone('scanning'),
      phone('completed', room: goodRoom),
    ];

    final seen = await c.watchSession(session).toList();
    expect(seen.map((e) => e.status), [
      HandoffStatus.pending,
      HandoffStatus.linked,
      HandoffStatus.scanning,
      HandoffStatus.completed,
    ]);
    expect(seen.last.room!.widthCm, 382.4);
    expect(seen.last.room!.ceilingCm, 271.0);
  });

  test('a dropped request is retried, not fatal', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = ['__throw__', '__throw__', phone('completed', room: goodRoom)];

    final seen = await c.watchSession(session).toList();
    expect(seen.last.status, HandoffStatus.completed);
  });

  test('a corrupt body is skipped rather than ending the session', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = ['{not json', '', phone('completed', room: goodRoom)];

    final seen = await c.watchSession(session).toList();
    expect(seen.last.status, HandoffStatus.completed);
  });

  test('impossible measurements fail the session instead of reaching the engine',
      () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = [
      phone('completed', room: {'width_cm': 0, 'length_cm': 421.9}),
    ];

    final seen = await c.watchSession(session).toList();
    expect(seen.last.status, HandoffStatus.failed);
    expect(seen.last.failureMessage, contains('غير صالحة'));
  });

  test('a missing ceiling falls back to a standard height', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = [
      phone('completed', room: {'width_cm': 300.0, 'length_cm': 400.0}),
    ];

    final seen = await c.watchSession(session).toList();
    expect(seen.last.room!.ceilingCm, 280);
  });

  test('a phone-side failure carries its reason', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = [phone('failed', failure: 'الجهاز لا يدعم LiDAR')];

    final seen = await c.watchSession(session).toList();
    expect(seen.last.status, HandoffStatus.failed);
    expect(seen.last.failureMessage, contains('LiDAR'));
  });

  test('the session expires rather than polling forever', () async {
    final c = channelWith();
    final session =
        (await c.open(ttl: const Duration(minutes: 5))).valueOrNull!;
    clock = clock.add(const Duration(minutes: 6));
    replies = [null, null, null];

    final seen = await c.watchSession(session).toList();
    expect(seen.last.status, HandoffStatus.expired);
  });

  test('an unknown status leaves the stage unchanged', () async {
    final c = channelWith();
    final session = (await c.open()).valueOrNull!;
    replies = [phone('teleporting'), phone('completed', room: goodRoom)];

    final seen = await c.watchSession(session).toList();
    expect(seen.map((e) => e.status),
        [HandoffStatus.pending, HandoffStatus.pending, HandoffStatus.completed]);
  });
}
