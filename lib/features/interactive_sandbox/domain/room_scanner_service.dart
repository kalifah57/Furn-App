import '../../../core/errors/result.dart';
import '../../../shared/models/models.dart';

/// تجريد **المسح المكاني** للغرفة (LiDAR / RoomPlan على iOS، ARCore على أندرويد).
///
/// يتبع تسمية العقود في المشروع (`CatalogRepository`, `VisionAnalysisService`)
/// بلا بادئة `I` — وهو أيضًا ما يوصي به دليل أسلوب Dart.
///
/// المخرَج المهم للمحرّك هو [ScannedRoom]: أبعاد بالسنتيمتر + شبكة اختيارية.
/// الـ MVP يعمل بالكامل على [MockRoomScannerService] دون أي SDK أصلي.
abstract interface class RoomScannerService {
  /// هل الجهاز يدعم المسح أصلًا؟ (الويب و iOS ما قبل LiDAR: لا).
  Future<bool> isSupported();

  /// يبدأ جلسة مسح ويعيد الغرفة المُقاسة.
  Future<Result<ScannedRoom>> scan();
}

/// جدار مُستخرَج من المسح — يُستخدم لاحقًا لإسناد الأثاث ولحساب الفتحات.
class ScannedSurface {
  const ScannedSurface({
    required this.widthCm,
    required this.heightCm,
    this.isOpening = false,
  });

  final double widthCm;
  final double heightCm;

  /// باب أو نافذة: مساحة لا يجوز إسناد أثاث إليها.
  final bool isOpening;
}

/// نتيجة المسح: ما يحتاجه المحرّك المكاني ليبني مشهدًا.
class ScannedRoom {
  const ScannedRoom({
    required this.widthCm,
    required this.lengthCm,
    required this.ceilingCm,
    this.surfaces = const [],
    this.meshAssetPath = '',
    this.confidence = 1.0,
  });

  final double widthCm;
  final double lengthCm;
  final double ceilingCm;
  final List<ScannedSurface> surfaces;

  /// مسار شبكة الغرفة (USDZ/GLB) حين يوفّرها المسح الحقيقي.
  final String meshAssetPath;

  /// ثقة القياس 0..1 — المسح اليدوي = 1.0، والتقدير من صورة أقل.
  final double confidence;

  /// جسر إلى نموذج المشروع: المحرّك كله يقرأ [Room] بالمتر.
  Room toRoom({RoomType roomType = RoomType.other}) => Room(
        widthM: widthCm / 100,
        lengthM: lengthCm / 100,
        heightM: ceilingCm / 100,
        roomType: roomType,
      );
}

/// تنفيذ وهمي بشكل مخرجات RoomPlan (mock-first — القرار G2).
///
/// يعيد غرفة ثابتة: أي تعشية عشوائية هنا تجعل المشهد الناتج غير قابل لإعادة
/// الإنتاج، وتُفقد الاختبارات معناها.
class MockRoomScannerService implements RoomScannerService {
  const MockRoomScannerService({
    this.widthCm = 380,
    this.lengthCm = 420,
    this.ceilingCm = 280,
  });

  final double widthCm;
  final double lengthCm;
  final double ceilingCm;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<Result<ScannedRoom>> scan() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return Ok(ScannedRoom(
      widthCm: widthCm,
      lengthCm: lengthCm,
      ceilingCm: ceilingCm,
      surfaces: [
        ScannedSurface(widthCm: widthCm, heightCm: ceilingCm),
        const ScannedSurface(widthCm: 90, heightCm: 210, isOpening: true), // باب
        const ScannedSurface(widthCm: 140, heightCm: 120, isOpening: true), // نافذة
      ],
      confidence: 0.92,
    ));
  }
}
