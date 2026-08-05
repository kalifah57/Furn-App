import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/features/interactive_sandbox/data/handoff_room_scanner_service.dart';
import 'package:furn_app/features/interactive_sandbox/data/in_memory_handoff_channel.dart';
import 'package:furn_app/features/interactive_sandbox/domain/handoff_session.dart';
import 'package:furn_app/features/interactive_sandbox/domain/room_scanner_service.dart';

/// The cross-device handoff state machine. The network is the easy part to swap;
/// these transitions — expiry, cancellation, late writes, a phone that finishes
/// with nothing — are where the flow actually breaks, so they are the tests.
void main() {
  const scanned = ScannedRoom(widthCm: 382, lengthCm: 421, ceilingCm: 271);

  var counter = 0;
  late DateTime clock;
  late InMemoryHandoffChannel channel;

  setUp(() {
    counter = 0;
    clock = DateTime(2026, 8, 5, 12);
    channel = InMemoryHandoffChannel(
      newSessionId: () => 'session_${++counter}',
      now: () => clock,
    );
  });

  group('session identity', () {
    test('a pairing code is derived deterministically from the id', () {
      final a = HandoffSession(
          id: 'abc', createdAt: clock, expiresAt: clock.add(const Duration(minutes: 5)));
      final b = HandoffSession(
          id: 'abc', createdAt: clock, expiresAt: clock.add(const Duration(minutes: 9)));
      expect(a.pairingCode, b.pairingCode);
      expect(a.pairingCode.length, 6);
    });

    test('different sessions get different codes', () {
      String code(String id) => HandoffSession(
          id: id, createdAt: clock, expiresAt: clock).pairingCode;
      expect(code('session_1'), isNot(code('session_2')));
    });

    test('the code avoids visually ambiguous characters', () {
      final code = HandoffSession(
          id: 'anything-at-all', createdAt: clock, expiresAt: clock).pairingCode;
      expect(code.contains(RegExp(r'[O01I]')), isFalse);
    });
  });

  group('the happy path', () {
    test('the browser receives dimensions the phone published', () async {
      final service = HandoffRoomScannerService(channel: channel);
      final pending = service.scan();

      // The phone walks through its stages.
      await pumpEventQueue();
      await channel.simulatePhone('session_1', status: HandoffStatus.linked);
      await channel.simulatePhone('session_1', status: HandoffStatus.scanning);
      await channel.simulatePhone('session_1', status: HandoffStatus.processing);
      await channel.simulatePhone('session_1',
          status: HandoffStatus.completed, room: scanned);

      final room = (await pending).valueOrNull!;
      expect(room.widthCm, 382);
      expect(room.lengthCm, 421);
    });

    test('every stage is observable, so the UI is never a blind spinner', () async {
      final service = HandoffRoomScannerService(channel: channel);
      final seen = <HandoffStatus>[];
      final sub = service.sessions.listen((s) => seen.add(s.status));

      final pending = service.scan();
      await pumpEventQueue();
      for (final s in [
        HandoffStatus.linked,
        HandoffStatus.scanning,
        HandoffStatus.processing,
      ]) {
        await channel.simulatePhone('session_1', status: s);
      }
      await channel.simulatePhone('session_1',
          status: HandoffStatus.completed, room: scanned);
      await pending;
      await sub.cancel();

      expect(seen, [
        HandoffStatus.pending,
        HandoffStatus.linked,
        HandoffStatus.scanning,
        HandoffStatus.processing,
        HandoffStatus.completed,
      ]);
    });

    test('the mesh is not required to finish — dimensions alone complete it',
        () async {
      final service = HandoffRoomScannerService(channel: channel);
      final pending = service.scan();
      await pumpEventQueue();
      await channel.simulatePhone('session_1',
          status: HandoffStatus.completed, room: scanned);

      final result = await pending;
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.meshAssetPath, '');
    });
  });

  group('the ways a handoff fails', () {
    test('expiry ends the wait instead of hanging forever', () async {
      final service = HandoffRoomScannerService(channel: channel);
      final pending = service.scan();
      await pumpEventQueue();
      await channel.expire('session_1');

      final result = await pending;
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('a phone-side failure carries its reason back to the browser', () async {
      final service = HandoffRoomScannerService(channel: channel);
      final pending = service.scan();
      await pumpEventQueue();
      await channel.simulatePhone('session_1',
          status: HandoffStatus.failed, failureMessage: 'رُفض إذن الكاميرا');

      final failure = (await pending).failureOrNull!;
      expect(failure, isA<UnknownFailure>());
      expect(failure.message, contains('الكاميرا'));
    });

    test('cancellation resolves', () async {
      final service = HandoffRoomScannerService(channel: channel);
      final pending = service.scan();
      await pumpEventQueue();
      await channel.simulatePhone('session_1', status: HandoffStatus.cancelled);
      expect((await pending).failureOrNull, isA<ValidationFailure>());
    });

    test('completing with no room is an error, not a zero-sized room', () async {
      // Otherwise a 0x0 room reaches the deterministic engine and renders an
      // empty scene with no visible cause.
      final service = HandoffRoomScannerService(channel: channel);
      final pending = service.scan();
      await pumpEventQueue();
      await channel.simulatePhone('session_1', status: HandoffStatus.completed);
      expect((await pending).failureOrNull, isA<ValidationFailure>());
    });
  });

  group('late and hostile writes', () {
    test('a write after the session ended is rejected', () async {
      final opened = (await channel.open()).valueOrNull!;
      await channel.simulatePhone(opened.id, status: HandoffStatus.cancelled);

      final late = await channel.publish(
          opened.copyWith(status: HandoffStatus.completed, room: scanned));
      expect(late.isErr, isTrue);
    });

    test('a write past the TTL expires the session rather than reviving it',
        () async {
      final opened =
          (await channel.open(ttl: const Duration(minutes: 5))).valueOrNull!;
      clock = clock.add(const Duration(minutes: 6));

      final late = await channel.publish(
          opened.copyWith(status: HandoffStatus.completed, room: scanned));
      expect(late.isErr, isTrue);
    });

    test('publishing to an unknown session id fails', () async {
      final ghost = HandoffSession(
          id: 'not-a-session', createdAt: clock, expiresAt: clock);
      expect((await channel.publish(ghost)).failureOrNull, isA<NotFoundFailure>());
    });

    test('watching an unknown session errors rather than waiting', () async {
      expect(channel.watch('not-a-session'), emitsError(isA<NotFoundFailure>()));
    });
  });

  group('reconnecting', () {
    test('a late subscriber immediately receives the current stage', () async {
      final opened = (await channel.open()).valueOrNull!;
      await channel.simulatePhone(opened.id, status: HandoffStatus.scanning);

      // A browser tab that reloaded mid-scan resubscribes here.
      final first = await channel.watch(opened.id).first;
      expect(first.status, HandoffStatus.scanning);
    });
  });

  group('expiry accounting', () {
    test('remaining time never goes negative', () {
      final s = HandoffSession(
          id: 'x', createdAt: clock, expiresAt: clock.add(const Duration(minutes: 1)));
      expect(s.remainingAt(clock.add(const Duration(minutes: 5))), Duration.zero);
      expect(s.isExpiredAt(clock.add(const Duration(minutes: 5))), isTrue);
      expect(s.isExpiredAt(clock), isFalse);
    });

    test('only terminal states report as terminal', () {
      HandoffSession withStatus(HandoffStatus st) => HandoffSession(
          id: 'x', createdAt: clock, expiresAt: clock, status: st);
      expect(withStatus(HandoffStatus.pending).isTerminal, isFalse);
      expect(withStatus(HandoffStatus.scanning).isTerminal, isFalse);
      expect(withStatus(HandoffStatus.completed).isTerminal, isTrue);
      expect(withStatus(HandoffStatus.expired).isTerminal, isTrue);
    });
  });
}
