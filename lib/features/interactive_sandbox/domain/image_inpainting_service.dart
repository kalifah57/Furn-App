import '../../../core/errors/result.dart';

/// تجريد **تنظيف الغرفة بصريًا**: ترسل صورة الغرفة إلى خدمة رؤية سحابية تزيل
/// الأثاث الموجود، وتعيد كساءً نظيفًا يُلبَس على شبكة الغرفة في المشهد.
///
/// عقد فقط — لا شبكة هنا. الـ MVP يعمل على [MockImageInpaintingService]، ويُبدَّل
/// التنفيذ الحقيقي عبر `override` في الـ DI دون لمس الشاشة (ADR-0001 §4).
///
/// ملاحظة تشغيلية تخصّ التنفيذ الحقيقي لاحقًا: هذه أوّل نقطة في التطبيق تغادر
/// فيها **صورة داخل منزل المستخدم** الجهاز. تحتاج موافقة صريحة ومسار حذف قبل
/// أن تُشحن — وهو قرار منتج لا يُتخذ ضمنيًا في طبقة الخدمات.
abstract interface class ImageInpaintingService {
  /// [imageRef] مرجع الصورة الملتقطة (مسار محلي في الـ MVP).
  /// يعيد مرجع الكساء النظيف الجاهز للإسقاط على الشبكة.
  Future<Result<InpaintedTexture>> removeFurniture(String imageRef);
}

/// الكساء الناتج بعد إزالة الأثاث.
class InpaintedTexture {
  const InpaintedTexture({
    required this.textureRef,
    this.removedRegions = 0,
    this.isFallback = false,
  });

  /// مرجع/مسار الصورة النظيفة.
  final String textureRef;

  /// عدد المناطق التي أُزيلت — إشارة للمستخدم أن التنظيف تمّ فعلًا.
  final int removedRegions;

  /// true حين تعذّر التنظيف واستُخدمت الصورة الأصلية كما هي.
  final bool isFallback;
}

/// تنفيذ وهمي حتمي: يعيد مرجعًا مشتقًّا من المدخل بلا أي عشوائية.
class MockImageInpaintingService implements ImageInpaintingService {
  const MockImageInpaintingService();

  @override
  Future<Result<InpaintedTexture>> removeFurniture(String imageRef) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (imageRef.isEmpty) {
      return const Ok(InpaintedTexture(textureRef: '', isFallback: true));
    }
    return Ok(InpaintedTexture(
      textureRef: 'mock://inpainted/$imageRef',
      removedRegions: 3,
    ));
  }
}
