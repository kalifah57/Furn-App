import '../../shared/models/models.dart';
import '../recommendation/scored_candidate.dart';
import '../recommendation/scoring.dart';

/// Constraint Engine (decision_engine.md): يطبّق التصفية الصارمة (الاستبعاد الفوري)
/// ويُعيد المرشّحين المؤهّلين مُقيَّمين ومرتّبين تنازليًا بالدرجة.
///
/// مُستخرَج حرفيًا من RecommendationEngine (evolution، لا تغيير في السلوك). يستدعي
/// الـ scorer ضمن مرحلة التأهيل كما في السلوك الحالي؛ الفصل الكامل بين التصفية
/// والتقييم تحسين لاحق يُنفَّذ عند الحاجة فقط.
class ConstraintEngine {
  const ConstraintEngine();

  /// المراحل 1–7: التصفية (توفر، مطابقة الفئة، دخول المساحة، سقف السعر) + التقييم + الترتيب.
  List<ScoredCandidate> selectEligible(
    List<CatalogProduct> catalog,
    ScoringContext ctx,
    Set<RecommendationCategory> requestedCats,
    RecommendationScorer scorer,
  ) {
    final viable = <ScoredCandidate>[];
    for (final p in catalog) {
      if (!p.isAvailable) continue; // مرحلة 5: التوفر
      if (requestedCats.isNotEmpty && !requestedCats.contains(p.category)) {
        continue; // نوع لا يطابق الغرض المطلوب
      }
      final b = scorer.score(p, ctx); // مرحلة 6: احتساب الدرجة
      if (b.room <= 0.0) continue; // مرحلة 2: لا يدخل المساحة
      if (_exceedsHardPriceLimit(p, ctx)) continue; // مرحلة 3: سعر غير منطقي للفئة
      viable.add(ScoredCandidate(p, b));
    }
    viable.sort((a, b) => b.breakdown.total.compareTo(a.breakdown.total)); // مرحلة 7
    return viable;
  }

  bool _exceedsHardPriceLimit(CatalogProduct p, ScoringContext ctx) {
    // الهامش 2.5× يسمح ببقاء عناصر الباقة المميّزة مع قطع الأسعار الشاذّة.
    final ceiling = ctx.categoryCeilings[p.category];
    if (ceiling != null && ceiling > 0) return p.price > ceiling * 2.5;
    if (ctx.budget.hasBudget) return p.price > ctx.budget.maxTotal;
    return false;
  }
}
