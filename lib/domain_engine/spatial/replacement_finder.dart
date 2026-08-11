import '../../shared/models/models.dart';
import 'ar_spatial_engine.dart';
import 'placement_solver.dart';

/// **مُرشِّح الاستبدال** — عند طلب «بدّل هذه القطعة»، يجد البدائل التي تدخل في
/// نفس الخانة، وتبقى داخل الميزانية، وتناسب نمط الغرفة. حتمي بالكامل.
///
/// ملاحظتان تصميميتان تُغيّران السلوك:
///
/// 1. **سقف الميزانية = المتبقّي + سعر المُزالة.** إزالة كنب بـ 900 ريال تُحرّر
///    900 ريال؛ لو قِسنا البدائل على «المتبقّي» وحده لَما ظهر أي بديل بسعر
///    مماثل — وهو أسوأ سلوك ممكن في شاشة استبدال.
///
/// 2. **«نفس المقاس» ليست مطابقة تامة.** لا يوجد في أي كتالوج بديل بالمليمتر
///    نفسه. الشرط الحقيقي: أن تدخل القطعة في *الخانة* التي أخلتها السابقة دون
///    أن تخرج عن الغرفة أو تصطدم بجيرانها — وهذا ما نفحصه فعليًا.

/// سماح أبعاد افتراضي (سم) حول مقاس القطعة المُزالة.
const double kSlotToleranceCm = 15;

/// بديل مرشَّح مع الأرقام التي بُني عليها ترتيبه.
class ReplacementCandidate {
  const ReplacementCandidate({
    required this.product,
    required this.priceDelta,
    required this.styleScore,
  });

  final CatalogProduct product;

  /// فرق السعر عن القطعة المُزالة (سالب = توفير).
  final double priceDelta;

  /// عدد الوسوم المتطابقة مع نمط/ألوان الغرفة — إشارة ترتيب لا فلترة.
  final int styleScore;

  bool get isCheaper => priceDelta < 0;
}

class ReplacementFinder {
  const ReplacementFinder();

  /// يعيد البدائل مرتّبة: الأقرب نمطًا أولًا، ثم الأرخص، ثم المعرّف.
  ///
  /// [remainingBudget] المتبقّي *قبل* إعادة سعر القطعة المُزالة.
  /// [others] بقية المشهد — للتأكد أن البديل لا يصطدم بجيرانه.
  List<ReplacementCandidate> alternativesFor({
    required Placement slot,
    required List<CatalogProduct> catalog,
    required RoomSpace room,
    required List<Placement> others,
    required double remainingBudget,
    required StylePreferences style,
    double toleranceCm = kSlotToleranceCm,
  }) {
    final removed = slot.product;
    final ceiling = remainingBudget + removed.price;
    final neighbours = others
        .where((p) => p.product.productId != removed.productId)
        .toList();

    final out = <ReplacementCandidate>[];
    for (final p in catalog) {
      if (p.productId == removed.productId) continue;
      if (p.category != removed.category) continue;
      if (!p.isAvailable) continue;
      if (!p.hasFootprint) continue; // المسقط يحتاج مقاسات، لا نموذجًا ثلاثيًّا
      if (p.price > ceiling) continue;
      if (!_fitsSlot(p, removed, slot, room, neighbours, toleranceCm)) continue;

      out.add(ReplacementCandidate(
        product: p,
        priceDelta: p.price - removed.price,
        styleScore: _styleScore(p, style),
      ));
    }

    // ترتيب كلّي: النمط تنازليًا، ثم السعر تصاعديًا، ثم المعرّف — فرز Dart غير
    // مضمون الاستقرار، فالمعرّف يجعل الناتج واحدًا في كل تشغيل.
    out.sort((a, b) {
      final byStyle = b.styleScore.compareTo(a.styleScore);
      if (byStyle != 0) return byStyle;
      final byPrice = a.product.price.compareTo(b.product.price);
      if (byPrice != 0) return byPrice;
      return a.product.productId.compareTo(b.product.productId);
    });
    return out;
  }

  /// هل يدخل البديل في الخانة نفسها؟ نضعه في مركز القطعة المُزالة بنفس دورانها،
  /// ثم نفحص: ضمن السماح، وداخل الغرفة، وبلا تصادم مع الجيران.
  bool _fitsSlot(
    CatalogProduct candidate,
    CatalogProduct removed,
    Placement slot,
    RoomSpace room,
    List<Placement> neighbours,
    double tolerance,
  ) {
    if (candidate.widthCm > removed.widthCm + tolerance) return false;
    if (candidate.depthCm > removed.depthCm + tolerance) return false;
    if (candidate.heightCm > removed.heightCm + tolerance) return false;

    final trial = Placement(
      product: candidate,
      xCm: slot.xCm,
      zCm: slot.zCm,
      rotationDeg: slot.rotationDeg,
    );
    final halfX = room.widthCm / 2;
    final halfZ = room.lengthCm / 2;
    if (trial.minX < -halfX || trial.maxX > halfX) return false;
    if (trial.minZ < -halfZ || trial.maxZ > halfZ) return false;

    for (final n in neighbours) {
      if (mountOf(n.product) != ArMount.floor) continue;
      if (n.product.category == RecommendationCategory.rug) continue;
      if (trial.overlaps(n)) return false;
    }
    return true;
  }

  /// تقاطع الوسوم مع تفضيلات الغرفة — عدد صحيح ليبقى الترتيب حتميًا تمامًا
  /// (لا مقارنة أعداد عشرية).
  int _styleScore(CatalogProduct p, StylePreferences style) {
    final preferred = style.preferred.map((e) => e.toLowerCase()).toSet();
    final colors = style.colors.map((e) => e.toLowerCase()).toSet();
    var score = 0;
    for (final t in p.styleTags) {
      if (preferred.contains(t.toLowerCase())) score++;
    }
    for (final t in p.colorTags) {
      if (colors.contains(t.toLowerCase())) score++;
    }
    return score;
  }
}
