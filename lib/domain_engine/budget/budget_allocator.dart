import '../../shared/models/models.dart';

/// نتيجة توزيع الميزانية على الفئات.
class BudgetAllocation {
  const BudgetAllocation({
    required this.total,
    required this.percentages,
    required this.ceilings,
  });

  final double total;

  /// النسبة المخصّصة لكل فئة (0..1).
  final Map<RecommendationCategory, double> percentages;

  /// السقف بالريال لكل فئة.
  final Map<RecommendationCategory, double> ceilings;
}

/// موزّع الميزانية الحتمي (recommendation_engine.md).
/// نِسب افتراضية لكل نوع غرفة (G8). المثال الاقتصادي لغرفة النوم مطابق للوثيقة:
/// السرير 40٪ · الكنب/الكرسي 20٪ · التخزين 15٪ · الإضاءة 10٪ · السجادة والإضافات 15٪.
class BudgetAllocator {
  const BudgetAllocator();

  static const Map<RoomType, Map<RecommendationCategory, double>> _distributions = {
    RoomType.bedroom: {
      RecommendationCategory.bed: 0.40,
      RecommendationCategory.sofa: 0.20,
      RecommendationCategory.storage: 0.15,
      RecommendationCategory.lamp: 0.10,
      RecommendationCategory.rug: 0.10,
      RecommendationCategory.other: 0.05,
    },
    RoomType.livingRoom: {
      RecommendationCategory.sofa: 0.35,
      RecommendationCategory.table: 0.15,
      RecommendationCategory.storage: 0.15,
      RecommendationCategory.rug: 0.15,
      RecommendationCategory.lamp: 0.10,
      RecommendationCategory.other: 0.10,
    },
    RoomType.guestRoom: {
      RecommendationCategory.sofa: 0.40,
      RecommendationCategory.rug: 0.20,
      RecommendationCategory.table: 0.10,
      RecommendationCategory.lamp: 0.10,
      RecommendationCategory.storage: 0.10,
      RecommendationCategory.other: 0.10,
    },
    RoomType.other: {
      RecommendationCategory.sofa: 0.25,
      RecommendationCategory.storage: 0.20,
      RecommendationCategory.table: 0.15,
      RecommendationCategory.lamp: 0.15,
      RecommendationCategory.rug: 0.15,
      RecommendationCategory.other: 0.10,
    },
  };

  BudgetAllocation allocate(Room room, Budget budget) {
    final dist = _distributions[room.roomType] ?? _distributions[RoomType.other]!;
    final total = budget.maxTotal;
    final ceilings = <RecommendationCategory, double>{
      for (final entry in dist.entries) entry.key: total * entry.value,
    };
    return BudgetAllocation(
      total: total,
      percentages: Map.unmodifiable(dist),
      ceilings: Map.unmodifiable(ceilings),
    );
  }
}
