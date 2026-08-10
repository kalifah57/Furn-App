import '../../shared/models/models.dart';
import 'ar_spatial_engine.dart';

/// **مُحدِّد المواضع** — يحوّل «باقة أثاث» إلى مشهد ثلاثي الأبعاد قابل للعرض:
/// أين تقف كل قطعة وبأي دوران. حتمي بالكامل وبلا Flutter.
///
/// [ArSpatialEngine] يجيب: *هل تدخل؟* — أما هذا فيجيب: *أين توضع؟* وهما سؤالان
/// مختلفان: الأول حساب مساحات، والثاني إسناد إلى الجدران مع تفادي التصادم.
///
/// نظام الإحداثيات: المبدأ في **مركز أرضية الغرفة**، المحور x عرض الغرفة،
/// z طولها، y إلى الأعلى — وهو نفس ما تُؤلَّف عليه نماذج الـ GLB (الأرضية عند
/// y=0 والمبدأ في مركز القاعدة)، فلا يلزم تحويل عند التركيب.

/// جدران الغرفة: الشمال عند z سالب، الجنوب z موجب، الغرب x سالب، الشرق x موجب.
enum Wall { north, south, east, west }

/// فجوة بين القطع الملاصقة للجدار نفسه (سم) — تمنع التصاق القطع بصريًا.
const double kPieceGapCm = 10;

/// بُعد الطاولة/السجادة أمام القطعة المرساة (سم).
const double kFrontOffsetCm = 45;

/// موضع قطعة واحدة في المشهد.
class Placement {
  const Placement({
    required this.product,
    required this.xCm,
    required this.zCm,
    this.rotationDeg = 0,
  });

  final CatalogProduct product;

  /// مركز القطعة على الأرضية، بالنسبة لمركز الغرفة.
  final double xCm;
  final double zCm;

  /// دوران حول المحور y — مقيّد بأربع زوايا فقط ليبقى الحلّ حتميًا.
  final int rotationDeg;

  /// الامتداد الفعلي على المحور x بعد الدوران.
  double get spanXCm =>
      rotationDeg % 180 == 0 ? product.widthCm : product.depthCm;

  /// الامتداد الفعلي على المحور z بعد الدوران.
  double get spanZCm =>
      rotationDeg % 180 == 0 ? product.depthCm : product.widthCm;

  double get minX => xCm - spanXCm / 2;
  double get maxX => xCm + spanXCm / 2;
  double get minZ => zCm - spanZCm / 2;
  double get maxZ => zCm + spanZCm / 2;

  /// تقاطع مستطيلَي القاعدة (AABB) — لمس الحواف ليس تصادمًا.
  bool overlaps(Placement other) =>
      minX < other.maxX &&
      maxX > other.minX &&
      minZ < other.maxZ &&
      maxZ > other.minZ;

  Placement copyWith({CatalogProduct? product}) => Placement(
        product: product ?? this.product,
        xCm: xCm,
        zCm: zCm,
        rotationDeg: rotationDeg,
      );
}

/// ناتج الحلّ: ما وُضع، وما تعذّر وضعه (لا نُسقط قطعة بصمت).
class PlacementPlan {
  const PlacementPlan({required this.placements, required this.unplaced});

  final List<Placement> placements;
  final List<CatalogProduct> unplaced;

  bool get isComplete => unplaced.isEmpty;
  double get totalPrice =>
      placements.fold<double>(0, (s, p) => s + p.product.price);

  Placement? byProductId(String id) {
    for (final p in placements) {
      if (p.product.productId == id) return p;
    }
    return null;
  }
}

class PlacementSolver {
  const PlacementSolver();

  /// أولوية الوضع: القطعة المرساة أولًا (السرير/الكنب) ثم ما يُسند إليها.
  static int _priority(CatalogProduct p) => switch (p.category) {
        RecommendationCategory.bed => 0,
        RecommendationCategory.sofa => 1,
        RecommendationCategory.storage => 2,
        RecommendationCategory.table => 3,
        RecommendationCategory.rug => 4,
        RecommendationCategory.lamp => 5,
        RecommendationCategory.other => 6,
      };

  /// الجدار الأطول — عليه تُسند القطعة المرساة.
  static Wall _longestWall(RoomSpace room) =>
      room.widthCm >= room.lengthCm ? Wall.north : Wall.west;

  static Wall _opposite(Wall w) => switch (w) {
        Wall.north => Wall.south,
        Wall.south => Wall.north,
        Wall.east => Wall.west,
        Wall.west => Wall.east,
      };

  /// ترتيب ثابت للجدران البديلة عند فشل الجدار المفضّل.
  static List<Wall> _wallOrder(Wall first) =>
      [first, _opposite(first), ...Wall.values.where((w) => w != first && w != _opposite(first))];

  /// دوران القطعة كي يكون ظهرها إلى الجدار.
  static int _rotationFor(Wall w) => switch (w) {
        Wall.north => 0,
        Wall.south => 180,
        Wall.west => 90,
        Wall.east => 270,
      };

  /// يحلّ الباقة كاملة. النتيجة دالة بحتة في (الباقة، الغرفة) — لا عشوائية.
  PlacementPlan solve(List<CatalogProduct> package, RoomSpace room) {
    // ترتيب كلّي (الأولوية ثم المعرّف) حتى لا يعتمد الناتج على استقرار الفرز:
    // فرز Dart غير مضمون الاستقرار، والمعرّف يكسر التعادل نهائيًا.
    final ordered = [...package]..sort((a, b) {
        final byPriority = _priority(a).compareTo(_priority(b));
        return byPriority != 0
            ? byPriority
            : a.productId.compareTo(b.productId);
      });

    final placed = <Placement>[];
    final unplaced = <CatalogProduct>[];
    final anchorWall = _longestWall(room);
    Placement? anchor;

    for (final product in ordered) {
      final mount = mountOf(product);

      // المعلّق في السقف: مركز الغرفة، لا يشغل أرضية ولا يصطدم بشيء.
      if (mount == ArMount.ceiling) {
        placed.add(Placement(product: product, xCm: 0, zCm: 0));
        continue;
      }

      // السجادة: تُفرش أمام القطعة المرساة وتمرّ تحت الأثاث — بلا فحص تصادم.
      if (product.category == RecommendationCategory.rug) {
        final spot = _inFrontOf(anchor, room, product);
        placed.add(Placement(product: product, xCm: spot.$1, zCm: spot.$2));
        continue;
      }

      // أباجورة الطاولة: توضع فوق قطعة أخرى، فلا تُحجز لها أرضية.
      if (mount == ArMount.tabletop) {
        final host = placed.isNotEmpty ? placed.last : null;
        placed.add(Placement(
          product: product,
          xCm: _clampCentre(host?.xCm ?? 0, product.widthCm, room.widthCm),
          zCm: _clampCentre(host?.zCm ?? 0, product.depthCm, room.lengthCm),
        ));
        continue;
      }

      final result = _placeAgainstWall(
        product: product,
        room: room,
        placed: placed,
        preferred: anchor == null ? anchorWall : _opposite(anchorWall),
      );

      if (result == null) {
        unplaced.add(product);
        continue;
      }
      placed.add(result);
      anchor ??= result;
    }

    return PlacementPlan(placements: placed, unplaced: unplaced);
  }

  /// موضع أمام القطعة المرساة (للسجادة)، أو مركز الغرفة إن لم توجد.
  (double, double) _inFrontOf(
      Placement? anchor, RoomSpace room, CatalogProduct product) {
    if (anchor == null) return (0, 0);
    // ندفع القطعة نحو مركز الغرفة بمقدار نصف عمق المرساة + فجوة.
    final towardCentre = anchor.zCm <= 0 ? 1.0 : -1.0;
    final z = anchor.zCm +
        towardCentre * (anchor.spanZCm / 2 + kFrontOffsetCm + product.depthCm / 2);
    return (
      _clampCentre(anchor.xCm, product.widthCm, room.widthCm),
      _clampCentre(z, product.depthCm, room.lengthCm),
    );
  }

  /// يقيّد مركز القطعة بحيث تبقى **بصمتها كاملة** داخل الغرفة، لا مركزها فقط —
  /// وإلا خرج نصف السجادة من الجدار. القطعة الأكبر من الغرفة تُوسَّط.
  static double _clampCentre(double centre, double spanCm, double roomCm) {
    final limit = (roomCm - spanCm) / 2;
    if (limit <= 0) return 0;
    return centre.clamp(-limit, limit);
  }

  /// يجرّب الجدران بترتيب ثابت، وعلى كل جدار خانات جانبية بترتيب ثابت،
  /// ويعيد أول موضع لا يخرج عن الغرفة ولا يصطدم بما وُضع.
  Placement? _placeAgainstWall({
    required CatalogProduct product,
    required RoomSpace room,
    required List<Placement> placed,
    required Wall preferred,
  }) {
    for (final wall in _wallOrder(preferred)) {
      final rotation = _rotationFor(wall);
      final probe = Placement(product: product, xCm: 0, zCm: 0, rotationDeg: rotation);
      final halfX = room.widthCm / 2;
      final halfZ = room.lengthCm / 2;

      // مركز القطعة وظهرها ملاصق للجدار.
      final backX = switch (wall) {
        Wall.west => -halfX + probe.spanXCm / 2,
        Wall.east => halfX - probe.spanXCm / 2,
        _ => 0.0,
      };
      final backZ = switch (wall) {
        Wall.north => -halfZ + probe.spanZCm / 2,
        Wall.south => halfZ - probe.spanZCm / 2,
        _ => 0.0,
      };

      // إزاحة جانبية بخطوات ثابتة لرصّ أكثر من قطعة على الجدار نفسه.
      final slidesAlongX = wall == Wall.north || wall == Wall.south;
      final step = (slidesAlongX ? probe.spanXCm : probe.spanZCm) + kPieceGapCm;
      for (final k in const [0, 1, -1, 2, -2, 3, -3]) {
        final offset = step * k;
        final candidate = Placement(
          product: product,
          xCm: slidesAlongX ? offset : backX,
          zCm: slidesAlongX ? backZ : offset,
          rotationDeg: rotation,
        );
        if (candidate.minX < -halfX || candidate.maxX > halfX) continue;
        if (candidate.minZ < -halfZ || candidate.maxZ > halfZ) continue;
        if (placed.any((e) => _blocks(e) && candidate.overlaps(e))) continue;
        return candidate;
      }
    }
    return null;
  }

  /// السجاد والمعلّقات وما يوضع فوق الأثاث لا تمنع وضع قطعة أرضية مكانها.
  static bool _blocks(Placement p) =>
      mountOf(p.product) == ArMount.floor &&
      p.product.category != RecommendationCategory.rug;
}
