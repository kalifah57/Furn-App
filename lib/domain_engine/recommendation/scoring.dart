import '../../shared/models/models.dart';

/// أوزان نموذج الدرجة (recommendation_engine.md). المجموع = 1.0.
/// الأوزان قابلة للتعديل حسب نوع/حجم الغرفة والميزانية.
class ScoringWeights {
  const ScoringWeights({
    this.roomCompatibility = 0.35,
    this.budgetFit = 0.30,
    this.styleMatch = 0.20,
    this.qualitySignal = 0.10,
    this.userPreferences = 0.05,
  });

  final double roomCompatibility;
  final double budgetFit;
  final double styleMatch;
  final double qualitySignal;
  final double userPreferences;

  /// يضبط الأوزان حسب السياق:
  /// - الغرف الصغيرة ترفع وزن توافق الغرفة.
  /// - الميزانيات الضيّقة/غير المرنة ترفع وزن ملاءمة الميزانية.
  factory ScoringWeights.forContext(Room room, Budget budget) {
    final area = room.areaM2;
    final smallRoom = area > 0 && area < 12;
    final tightBudget = budget.hasBudget && !budget.flexible;

    if (smallRoom) {
      return const ScoringWeights(
        roomCompatibility: 0.45,
        budgetFit: 0.25,
        styleMatch: 0.18,
        qualitySignal: 0.08,
        userPreferences: 0.04,
      );
    }
    if (tightBudget) {
      return const ScoringWeights(
        roomCompatibility: 0.30,
        budgetFit: 0.40,
        styleMatch: 0.18,
        qualitySignal: 0.08,
        userPreferences: 0.04,
      );
    }
    return const ScoringWeights();
  }
}

/// تفصيل درجة توصية واحدة (للشفافية وبناء نص السبب).
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.room,
    required this.budget,
    required this.style,
    required this.quality,
    required this.userPref,
    required this.weights,
  });

  final double room; // 0..1
  final double budget; // 0..1
  final double style; // 0..1
  final double quality; // 0..1
  final double userPref; // 0..1
  final ScoringWeights weights;

  /// الدرجة النهائية 0..100.
  double get total =>
      (room * weights.roomCompatibility +
          budget * weights.budgetFit +
          style * weights.styleMatch +
          quality * weights.qualitySignal +
          userPref * weights.userPreferences) *
      100;
}

/// سياق احتساب الدرجة لمنتج ضمن مشروع.
class ScoringContext {
  ScoringContext({
    required this.room,
    required this.budget,
    required this.style,
    required this.categoryCeilings,
  }) : weights = ScoringWeights.forContext(room, budget);

  final Room room;
  final Budget budget;
  final StylePreferences style;

  /// سقف السعر المخصّص لكل فئة (من budget allocation).
  final Map<RecommendationCategory, double> categoryCeilings;
  final ScoringWeights weights;
}

/// حاسب الدرجة الحتمي.
class RecommendationScorer {
  const RecommendationScorer();

  ScoreBreakdown score(CatalogProduct p, ScoringContext ctx) {
    return ScoreBreakdown(
      room: _roomCompatibility(p, ctx.room),
      budget: _budgetFit(p, ctx),
      style: _styleMatch(p, ctx.style),
      quality: _qualitySignal(p),
      userPref: _userPreferences(p, ctx.style),
      weights: ctx.weights,
    );
  }

  // 1) توافق الغرفة (35%): هل تدخل في المساحة وتترك حركة كافية؟
  double _roomCompatibility(CatalogProduct p, Room room) {
    if (room.widthM <= 0 || room.lengthM <= 0) return 0.5; // غير معروف → محايد
    final roomW = room.widthM * 100;
    final roomL = room.lengthM * 100;
    // القطعة يجب أن تدخل بأي اتجاه.
    final fitsDirect = p.widthCm <= roomW && p.depthCm <= roomL;
    final fitsRotated = p.depthCm <= roomW && p.widthCm <= roomL;
    if (!fitsDirect && !fitsRotated) return 0.0;

    final roomArea = room.areaM2 * 10000; // cm²
    final footprint = p.widthCm * p.depthCm;
    if (roomArea <= 0) return 0.5;
    final ratio = footprint / roomArea;
    // مثالي أن تشغل القطعة نسبة معتدلة وتترك مساحة حركة.
    if (ratio <= 0.25) return 1.0;
    if (ratio <= 0.4) return 0.8;
    if (ratio <= 0.6) return 0.5;
    return 0.2;
  }

  // 2) ملاءمة الميزانية (30%): ضمن سقف الفئة ويترك مجالًا للباقي؟
  double _budgetFit(CatalogProduct p, ScoringContext ctx) {
    final ceiling = ctx.categoryCeilings[p.category];
    if (ceiling == null || ceiling <= 0) {
      // بلا سقف فئة: قارن بإجمالي الميزانية.
      if (!ctx.budget.hasBudget) return 0.5;
      final r = p.price / ctx.budget.maxTotal;
      return (1 - r).clamp(0.0, 1.0);
    }
    if (p.price <= ceiling) {
      return (1 - (p.price / ceiling) * 0.5).clamp(0.5, 1.0);
    }
    // تجاوز السقف.
    final over = (p.price - ceiling) / ceiling;
    return (0.5 - over).clamp(0.0, 0.5);
  }

  // 3) مطابقة النمط (20%): تقاطع style/color tags.
  double _styleMatch(CatalogProduct p, StylePreferences style) {
    if (style.preferred.isEmpty && style.colors.isEmpty) return 0.6; // محايد
    final styleOverlap = _overlap(p.styleTags, style.preferred);
    final colorOverlap = _overlap(p.colorTags, style.colors);
    if (style.colors.isEmpty) return (0.4 + 0.6 * styleOverlap).clamp(0.0, 1.0);
    if (style.preferred.isEmpty) return (0.4 + 0.6 * colorOverlap).clamp(0.0, 1.0);
    return (0.4 + 0.4 * styleOverlap + 0.2 * colorOverlap).clamp(0.0, 1.0);
  }

  // 4) إشارة الجودة/الشعبية (10%): التقييم إن توفّر.
  double _qualitySignal(CatalogProduct p) {
    final rating = p.ratingOptional;
    if (rating == null) return 0.5;
    return (rating / 5).clamp(0.0, 1.0);
  }

  // 5) تفضيلات المستخدم (5%): تقارب مع الألوان المفضّلة (تقريب للـ MVP).
  double _userPreferences(CatalogProduct p, StylePreferences style) {
    if (style.colors.isEmpty) return 0.5;
    return _overlap(p.colorTags, style.colors) > 0 ? 1.0 : 0.4;
  }

  double _overlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final setB = b.map((e) => e.toLowerCase()).toSet();
    final hits = a.where((e) => setB.contains(e.toLowerCase())).length;
    return (hits / b.length).clamp(0.0, 1.0);
  }
}
