import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../domain/room_scanner_service.dart';

/// تنفيذ [RoomScannerService] فوق **RoomPlan** الأصلية عبر MethodChannel.
///
/// يُنفّذ العقد القائم في `domain/room_scanner_service.dart` بدل إنشاء خدمة
/// موازية: الشاشة والمتحكّم لا يعرفان أن المسح صار حقيقيًا — يُبدَّل المزوّد فقط.
///
/// **هذا المسار يعمل على iOS فقط.** المسح يتطلّب iOS 16+ وجهازًا فيه LiDAR
/// (iPhone 12 Pro فما فوق). على الويب — وهو ما يُنشر منه التطبيق اليوم — لا يوجد
/// تنفيذ أصلي، فيُرمى [MissingPluginException]؛ نلتقطه ونُبلّغ «غير مدعوم» بدل
/// أن نُسقط الشاشة.
class PlatformRoomScannerService implements RoomScannerService {
  const PlatformRoomScannerService({this.channel = defaultChannel});

  /// اسم القناة — مُتّفق عليه حرفيًا مع الجانب الأصلي في `RoomScanPlugin.swift`.
  static const MethodChannel defaultChannel =
      MethodChannel('com.furnapp.spatial/roomplan');

  static const String methodIsSupported = 'isSupported';
  static const String methodStartScan = 'startRoomScan';

  /// رموز الأخطاء التي يُرجعها الجانب الأصلي.
  static const String codeUnsupported = 'UNSUPPORTED';
  static const String codeCancelled = 'CANCELLED';
  static const String codeScanFailed = 'SCAN_FAILED';

  final MethodChannel channel;

  @override
  Future<bool> isSupported() async {
    try {
      return await channel.invokeMethod<bool>(methodIsSupported) ?? false;
    } on MissingPluginException {
      return false; // ويب/أندرويد: لا تنفيذ أصلي أصلًا
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Result<ScannedRoom>> scan() async {
    final String raw;
    try {
      raw = await channel.invokeMethod<String>(methodStartScan) ?? '';
    } on MissingPluginException {
      return const Err(ValidationFailure('المسح ثلاثي الأبعاد غير متاح على هذا الجهاز.'));
    } on PlatformException catch (e) {
      return Err(_failureFor(e));
    }

    if (raw.isEmpty) {
      return const Err(UnknownFailure('انتهى المسح دون إرجاع قياسات.'));
    }
    return _parse(raw);
  }

  Failure _failureFor(PlatformException e) => switch (e.code) {
        codeUnsupported =>
          const ValidationFailure('هذا الجهاز لا يدعم المسح ثلاثي الأبعاد (يلزم LiDAR).'),
        // الإلغاء ليس عطلًا: نُنهي الانتظار برسالة هادئة بدل تعليق الشاشة للأبد.
        codeCancelled => const ValidationFailure('أُلغي المسح.'),
        codeScanFailed => UnknownFailure('تعذّر إكمال المسح.', e),
        _ => UnknownFailure('خطأ غير متوقّع أثناء المسح.', e),
      };

  /// يحوّل حمولة JSON القادمة من RoomPlan إلى [ScannedRoom].
  ///
  /// نتحقّق من الأبعاد بدل الوثوق بها: قياس صفري أو سالب يمرّ إلى المحرّك المكاني
  /// فيُنتج مشهدًا فارغًا بلا سبب ظاهر — وهو أسوأ من خطأ صريح هنا.
  Result<ScannedRoom> _parse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final width = (json['width_cm'] as num?)?.toDouble() ?? 0;
      final length = (json['length_cm'] as num?)?.toDouble() ?? 0;
      final ceiling = (json['ceiling_cm'] as num?)?.toDouble() ?? 0;

      if (width <= 0 || length <= 0) {
        return const Err(ValidationFailure('المسح أعاد أبعادًا غير صالحة.'));
      }

      final surfaces = <ScannedSurface>[
        for (final s in (json['surfaces'] as List? ?? const []))
          if (s is Map)
            ScannedSurface(
              widthCm: (s['width_cm'] as num?)?.toDouble() ?? 0,
              heightCm: (s['height_cm'] as num?)?.toDouble() ?? 0,
              isOpening: s['is_opening'] == true,
            ),
      ];

      return Ok(ScannedRoom(
        widthCm: width,
        lengthCm: length,
        ceilingCm: ceiling > 0 ? ceiling : 280,
        surfaces: surfaces,
        meshAssetPath: (json['mesh_path'] as String?) ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      ));
    } catch (e) {
      return Err(AiParsingFailure('تعذّر قراءة نتيجة المسح.', e));
    }
  }
}
