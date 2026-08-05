import '../../shared/models/models.dart';

/// **محرّك المساحة للواقع المعزّز** (Spatial Decision Engine · AR gate).
///
/// حتمي بالكامل وبلا Flutter: نفس المدخلات ⇒ نفس المخرجات دائمًا. مهمّته الإجابة
/// على سؤال واحد قبل فتح الكاميرا: *هل تدخل هذه القطعة فعليًا في هذه الغرفة —
/// بعد ما وُضع فيها — وتترك ممرًّا للحركة؟*
///
/// [RecommendationScorer] يعطي درجة ناعمة (0..1) لتوافق الغرفة لأغراض الترتيب.
/// هنا القرار **ثنائي**: تُعرض في AR أو لا تُعرض. لا نضع المستخدم أمام الكاميرا
/// أمام قطعة لا يمكن أن تُوضع — ذلك أسرع طريق لفقد الثقة بالأداة.

/// عرض ممرّ الحركة الأدنى (سم). معيار تصميم شائع للمسار الرئيسي بين القطع.
const double kWalkwayCm = 75;

/// أقصى نسبة إشغال للأرضية. ما بقي (35%) هو مساحة الحركة والأبواب.
const double kMaxFloorOccupancy = 0.65;

/// ارتفاع سقف افتراضي (سم) حين لا تُعطي الغرفة ارتفاعًا.
const double kDefaultCeilingCm = 280;

/// أدنى ارتفاع حرّ تحت تعليقة السقف (سم) — يمرّ تحتها واقف دون ارتطام.
const double kHeadroomCm = 200;

/// كيف تُثبَّت القطعة — يحدّد إن كانت تستهلك أرضية أصلًا.
enum ArMount {
  /// قائمة على الأرض: تستهلك بصمة وممرًّا (سرير، كنب، دولاب…).
  floor,

  /// معلّقة في السقف: لا تستهلك أرضية، لكن يجب أن تترك ارتفاعًا حرًّا.
  ceiling,

  /// توضع فوق قطعة أخرى: لا تستهلك أرضية ولا ممرًّا (أباجورة طاولة).
  tabletop,
}

/// تصنيفات فرعية معلّقة في السقف (من `subcategory` في الكتالوج).
const _ceilingSubcategories = {'ceiling', 'pendant', 'chandelier'};

/// تصنيفات فرعية توضع فوق أثاث آخر.
const _tabletopSubcategories = {'table_lamp'};

/// يستنتج طريقة التثبيت من التصنيف الفرعي — الافتراض الآمن: قائمة على الأرض.
ArMount mountOf(CatalogProduct p) {
  final sub = p.subcategory.toLowerCase();
  if (_ceilingSubcategories.contains(sub)) return ArMount.ceiling;
  if (_tabletopSubcategories.contains(sub)) return ArMount.tabletop;
  return ArMount.floor;
}

/// الغرفة الممسوحة بوحدات السنتيمتر — وحدة المحرّك الوحيدة (تفادي خلط م/سم).
class RoomSpace {
  const RoomSpace({
    required this.widthCm,
    required this.lengthCm,
    this.ceilingCm = kDefaultCeilingCm,
  });

  /// يحوّل [Room] (بالمتر) إلى مساحة المحرّك (بالسنتيمتر).
  factory RoomSpace.fromRoom(Room room) => RoomSpace(
        widthCm: room.widthM * 100,
        lengthCm: room.lengthM * 100,
        ceilingCm: room.heightM > 0 ? room.heightM * 100 : kDefaultCeilingCm,
      );

  final double widthCm;
  final double lengthCm;
  final double ceilingCm;

  bool get isMeasured => widthCm > 0 && lengthCm > 0;
  double get areaCm2 => widthCm * lengthCm;

  /// أقصى بصمة أرضية مسموح بها إجمالًا (سم²) — الباقي للحركة.
  double get placeableAreaCm2 => areaCm2 * kMaxFloorOccupancy;

  /// أقصر ضلع — عليه يُقاس بقاء الممرّ.
  double get shortSideCm => widthCm < lengthCm ? widthCm : lengthCm;
}

/// سبب القرار — مرئي للمستخدم بالعربية (شفافية: لماذا اختفت القطعة).
enum ArFitVerdict {
  fits,
  noModel,
  roomUnknown,
  tooTall,
  tooLarge,
  noRemainingSpace,
  blocksWalkway,
  lowHeadroom,
}

/// نتيجة تقييم قطعة واحدة مقابل غرفة — مع الأرقام التي بُني عليها القرار.
class ArFitResult {
  const ArFitResult({
    required this.product,
    required this.verdict,
    required this.footprintCm2,
    required this.remainingAreaCm2,
    required this.clearSpanCm,
  });

  final CatalogProduct product;
  final ArFitVerdict verdict;

  /// بصمة القطعة على الأرض (سم²).
  final double footprintCm2;

  /// المساحة القابلة للوضع المتبقّية *بعد* هذه القطعة (سم²) — قد تكون سالبة.
  final double remainingAreaCm2;

  /// أوسع ممرّ يبقى على أقصر ضلع بعد وضع القطعة (سم).
  final double clearSpanCm;

  bool get canPlace => verdict == ArFitVerdict.fits;

  /// سبب عربي قصير يُعرض تحت القطعة بدل إخفائها بصمت.
  String get reasonAr => switch (verdict) {
        ArFitVerdict.fits => 'تدخل في غرفتك',
        ArFitVerdict.noModel => 'لا يوجد نموذج ثلاثي الأبعاد بعد',
        ArFitVerdict.roomUnknown => 'قِس غرفتك أولًا',
        ArFitVerdict.tooTall => 'أعلى من سقف الغرفة',
        ArFitVerdict.tooLarge => 'أكبر من أبعاد الغرفة',
        ArFitVerdict.noRemainingSpace => 'لا تبقى مساحة كافية بعد قطعك الحالية',
        ArFitVerdict.blocksWalkway => 'تسدّ ممرّ الحركة (أقل من ${kWalkwayCm.toInt()} سم)',
        ArFitVerdict.lowHeadroom => 'تتدلّى منخفضة أكثر من اللازم',
      };
}

/// المحرّك — بلا حالة، لذا `const` وقابل للمشاركة.
class ArSpatialEngine {
  const ArSpatialEngine();

  /// السجاد يُمشى فوقه: لا يستهلك ممرًّا ولا يُحتسب في نسبة الإشغال.
  static bool _isFloorCovering(CatalogProduct p) =>
      p.category == RecommendationCategory.rug;

  /// هل تستهلك القطعة بصمة أرضية أصلًا؟ (المعلّق والموضوع فوق طاولة لا يستهلك.)
  static bool _consumesFloor(CatalogProduct p) =>
      mountOf(p) == ArMount.floor && !_isFloorCovering(p);

  /// المساحة القابلة للوضع المتبقّية قبل إضافة القطعة الحالية (سم²).
  double _freeFloorArea(RoomSpace room, List<CatalogProduct> placed) {
    final used = placed
        .where(_consumesFloor)
        .fold<double>(0, (sum, e) => sum + e.widthCm * e.depthCm);
    return room.placeableAreaCm2 - used;
  }

  /// أصغر ضلع أفقي للقطعة — الاتجاه الذي يترك أوسع ممرّ.
  static double _minorSideCm(CatalogProduct p) =>
      p.widthCm < p.depthCm ? p.widthCm : p.depthCm;

  /// هل تدخل القطعة بأبعادها الأفقية بأيّ من الاتجاهين (مباشر أو مُدار 90°)؟
  bool fitsFootprint(CatalogProduct p, RoomSpace room) {
    final direct = p.widthCm <= room.widthCm && p.depthCm <= room.lengthCm;
    final rotated = p.depthCm <= room.widthCm && p.widthCm <= room.lengthCm;
    return direct || rotated;
  }

  /// يقيّم قطعة واحدة مقابل الغرفة، مع احتساب ما وُضع فيها [placed].
  ///
  /// ترتيب القواعد مقصود: نُرجع أوّل سبب مانع — من الأرخص فحصًا إلى الأغلى —
  /// حتى يكون السبب المعروض هو الأوضح للمستخدم.
  ArFitResult evaluate(
    CatalogProduct product,
    RoomSpace room, {
    List<CatalogProduct> placed = const [],
  }) {
    final footprint = product.widthCm * product.depthCm;

    ArFitResult result(ArFitVerdict v, {double remaining = 0, double span = 0}) =>
        ArFitResult(
          product: product,
          verdict: v,
          footprintCm2: footprint,
          remainingAreaCm2: remaining,
          clearSpanCm: span,
        );

    if (!product.hasArModel) return result(ArFitVerdict.noModel);
    if (!room.isMeasured) return result(ArFitVerdict.roomUnknown);

    final mount = mountOf(product);

    // المعلّقة في السقف: لا تلمس الأرض إطلاقًا. الشرط الوحيد أن تترك ارتفاعًا
    // حرًّا يمرّ تحته واقف — وأن يتّسع لها السقف أفقيًا.
    if (mount == ArMount.ceiling) {
      if (!fitsFootprint(product, room)) return result(ArFitVerdict.tooLarge);
      if (room.ceilingCm - product.heightCm < kHeadroomCm) {
        return result(ArFitVerdict.lowHeadroom);
      }
      return result(ArFitVerdict.fits, remaining: _freeFloorArea(room, placed));
    }

    if (product.heightCm > room.ceilingCm) return result(ArFitVerdict.tooTall);
    if (!fitsFootprint(product, room)) return result(ArFitVerdict.tooLarge);

    // فوق طاولة: لا بصمة أرضية ولا ممرّ — تتبع القطعة الحاملة لها.
    if (mount == ArMount.tabletop) {
      return result(ArFitVerdict.fits, remaining: _freeFloorArea(room, placed));
    }

    // السجادة تُفرش تحت الأثاث ويُمشى فوقها: تدخل ما دامت أبعادها تدخل.
    if (_isFloorCovering(product)) {
      return result(
        ArFitVerdict.fits,
        remaining: _freeFloorArea(room, placed),
        span: room.shortSideCm,
      );
    }

    final remaining = _freeFloorArea(room, placed) - footprint;
    if (remaining < 0) {
      return result(ArFitVerdict.noRemainingSpace, remaining: remaining);
    }

    final span = room.shortSideCm - _minorSideCm(product);
    if (span < kWalkwayCm) {
      return result(ArFitVerdict.blocksWalkway, remaining: remaining, span: span);
    }

    return result(ArFitVerdict.fits, remaining: remaining, span: span);
  }

  /// يقيّم الكتالوج كاملًا — يحافظ على ترتيب المدخل (حتمية).
  List<ArFitResult> evaluateAll(
    List<CatalogProduct> catalog,
    RoomSpace room, {
    List<CatalogProduct> placed = const [],
  }) =>
      [for (final p in catalog) evaluate(p, room, placed: placed)];

  /// البوّابة النهائية: القطع التي يُسمح بفتح الكاميرا عليها فقط.
  List<CatalogProduct> viewableInAr(
    List<CatalogProduct> catalog,
    RoomSpace room, {
    List<CatalogProduct> placed = const [],
  }) =>
      [
        for (final r in evaluateAll(catalog, room, placed: placed))
          if (r.canPlace) r.product,
      ];
}
