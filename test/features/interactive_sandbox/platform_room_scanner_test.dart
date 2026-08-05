import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/features/interactive_sandbox/data/platform_room_scanner_service.dart';

/// Drives the RoomPlan MethodChannel from the Dart side with a mock native
/// handler. The Swift cannot be exercised here, but every way it can answer —
/// success, cancel, unsupported, garbage, silence — is covered, because those
/// are the paths that hang or crash a screen if handled carelessly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = PlatformRoomScannerService.defaultChannel;
  const service = PlatformRoomScannerService();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockNative(Future<Object?> Function(MethodCall call)? handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => mockNative(null));

  String payload({
    double width = 382.4,
    double length = 421.9,
    double ceiling = 271,
    List<Map<String, Object?>>? surfaces,
    String? meshPath,
    double confidence = 0.95,
  }) =>
      jsonEncode({
        'width_cm': width,
        'length_cm': length,
        'ceiling_cm': ceiling,
        'confidence': confidence,
        if (meshPath != null) 'mesh_path': meshPath,
        'surfaces': surfaces ??
            [
              {'width_cm': 382.4, 'height_cm': 271.0, 'is_opening': false},
              {'width_cm': 90.0, 'height_cm': 210.0, 'is_opening': true},
            ],
      });

  group('a completed scan', () {
    test('parses dimensions, openings and mesh path', () async {
      mockNative((call) async {
        expect(call.method, PlatformRoomScannerService.methodStartScan);
        return payload(meshPath: '/caches/room.usdz');
      });

      final room = (await service.scan()).valueOrNull!;
      expect(room.widthCm, 382.4);
      expect(room.lengthCm, 421.9);
      expect(room.ceilingCm, 271);
      expect(room.meshAssetPath, '/caches/room.usdz');
      expect(room.confidence, 0.95);
      expect(room.surfaces.length, 2);
      expect(room.surfaces.where((s) => s.isOpening).length, 1);
    });

    test('converts into the Room the engine consumes, in metres', () async {
      mockNative((_) async => payload(width: 380, length: 420, ceiling: 280));
      final room = (await service.scan()).valueOrNull!;
      final asRoom = room.toRoom();
      expect(asRoom.widthM, 3.8);
      expect(asRoom.lengthM, 4.2);
      expect(asRoom.heightM, 2.8);
    });

    test('falls back to a standard ceiling when the scan omits one', () async {
      mockNative((_) async => payload(ceiling: 0));
      expect((await service.scan()).valueOrNull!.ceilingCm, 280);
    });
  });

  group('the ways a scan does not complete', () {
    test('user cancellation resolves rather than hanging', () async {
      mockNative((_) async => throw PlatformException(
          code: PlatformRoomScannerService.codeCancelled));
      final result = await service.scan();
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('a device without LiDAR reports unsupported', () async {
      mockNative((_) async => throw PlatformException(
          code: PlatformRoomScannerService.codeUnsupported));
      expect((await service.scan()).failureOrNull, isA<ValidationFailure>());
    });

    test('a native failure surfaces as UnknownFailure', () async {
      mockNative((_) async => throw PlatformException(
          code: PlatformRoomScannerService.codeScanFailed, message: 'ARKit died'));
      expect((await service.scan()).failureOrNull, isA<UnknownFailure>());
    });

    test('no native implementation (web/android) is handled, not thrown', () async {
      mockNative(null); // nothing registered on this channel
      final result = await service.scan();
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('an empty reply is an error, not a zero-sized room', () async {
      mockNative((_) async => '');
      expect((await service.scan()).failureOrNull, isA<UnknownFailure>());
    });

    test('malformed JSON is reported, never partially applied', () async {
      mockNative((_) async => '{not json');
      expect((await service.scan()).failureOrNull, isA<AiParsingFailure>());
    });

    test('zero dimensions are rejected before reaching the engine', () async {
      // A zero-width room would silently produce an empty scene downstream.
      mockNative((_) async => payload(width: 0));
      expect((await service.scan()).failureOrNull, isA<ValidationFailure>());
    });

    test('negative dimensions are rejected too', () async {
      mockNative((_) async => payload(length: -5));
      expect((await service.scan()).failureOrNull, isA<ValidationFailure>());
    });

    test('a missing surfaces list yields an empty list, not a crash', () async {
      mockNative((_) async => jsonEncode({
            'width_cm': 300.0,
            'length_cm': 400.0,
            'ceiling_cm': 260.0,
          }));
      final room = (await service.scan()).valueOrNull!;
      expect(room.surfaces, isEmpty);
      expect(room.meshAssetPath, '');
    });
  });

  group('isSupported', () {
    test('passes through the native answer', () async {
      mockNative((call) async {
        expect(call.method, PlatformRoomScannerService.methodIsSupported);
        return true;
      });
      expect(await service.isSupported(), isTrue);
    });

    test('is false where no native side exists', () async {
      mockNative(null);
      expect(await service.isSupported(), isFalse);
    });

    test('is false when the native side errors', () async {
      mockNative((_) async => throw PlatformException(code: 'BOOM'));
      expect(await service.isSupported(), isFalse);
    });
  });
}
