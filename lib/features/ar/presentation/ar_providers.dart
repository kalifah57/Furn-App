import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../domain_engine/spatial/ar_spatial_engine.dart';
import '../../../shared/models/models.dart';

/// حقن تبعيات شاشة الواقع المعزّز (ADR-0001 §4): كل شيء عبر مزوّدات قابلة
/// للاستبدال، فلا تعرف الشاشة من أين جاء الكتالوج ولا كيف تُحسب المساحة.

/// المحرّك المكاني — بلا حالة، لذا `const`.
final arSpatialEngineProvider =
    Provider<ArSpatialEngine>((ref) => const ArSpatialEngine());

/// الغرفة الممسوحة التي تُقاس عليها القطع.
///
/// يُستبدل بالقياس الحقيقي (من مسح الكاميرا أو الإدخال اليدوي) عبر `override`
/// عند بناء الشاشة؛ الافتراضي غرفة معيشة 4×4 م لمعاينة الـ MVP.
final arRoomProvider = Provider<Room>(
  (ref) => const Room(widthM: 4, lengthM: 4, roomType: RoomType.livingRoom),
);

/// القطع المثبّتة في الغرفة فعلًا — تستهلك المساحة المتبقّية للقطع التالية.
final arPlacedProvider = StateProvider<List<CatalogProduct>>((ref) => const []);

/// تقييم الكتالوج كاملًا مقابل الغرفة: لكل قطعة حكم وسبب.
///
/// نُبقي القطع غير المطابقة في النتيجة (مع سببها) بدل حذفها بصمت — المستخدم
/// يثق بالأداة حين يرى *لماذا* اختفت القطعة، لا حين تختفي فقط.
final arFitResultsProvider = FutureProvider<List<ArFitResult>>((ref) async {
  final result = await ref.watch(catalogRepositoryProvider).loadProducts();
  final catalog = result.valueOrNull ?? const <CatalogProduct>[];
  return ref.watch(arSpatialEngineProvider).evaluateAll(
        catalog,
        RoomSpace.fromRoom(ref.watch(arRoomProvider)),
        placed: ref.watch(arPlacedProvider),
      );
});
