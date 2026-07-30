import '../../shared/models/models.dart';
import 'recommended_item_mapper.dart';
import 'scored_candidate.dart';

/// Bundle Engine (decision_engine.md): يكوّن الباقات الثلاث (اقتصادية/متوازنة/مميّزة)
/// من المرشّحين المُقيَّمين، مع احترام الفئات + التنازلات. حتمي وقابل للاختبار وحده.
///
/// مُستخرَج من RecommendationEngine مع الحفاظ على السلوك نفسه (evolution، لا rewrite).
class BundleComposer {
  const BundleComposer();

  List<Bundle> compose(
    FurnishingProject project,
    List<ScoredCandidate> viable,
    Set<RecommendationCategory> essentialCats,
  ) {
    // فئات الباقة: المطلوبة أساسًا، وإلا استنتج من المتوفر.
    final cats = essentialCats.isNotEmpty
        ? essentialCats
        : viable.map((s) => s.product.category).toSet();
    if (viable.isEmpty || cats.isEmpty) return const [];

    final budgetBundle = _bundleByStrategy(
      project,
      viable,
      cats,
      tier: BundleTier.budget,
      pick: _cheapestPerCategory,
      reason: 'أقل تكلفة مقبولة تركّز على الأساسيات الضرورية.',
      designNote: 'أقل إضافات تجميلية للحفاظ على الميزانية.',
      tradeoff: 'إضافات تجميلية محدودة.',
    );
    final balancedBundle = _bundleByStrategy(
      project,
      viable,
      cats,
      tier: BundleTier.balanced,
      pick: _bestScorePerCategory,
      reason: 'أفضل توازن بين الشكل والسعر مع أساسيات قوية.',
      designNote: 'أساسيات قوية وبعض اللمسات الإضافية.',
      tradeoff: 'سعر أعلى قليلًا من الباقة الاقتصادية.',
    );
    final premiumBundle = _bundleByStrategy(
      project,
      viable,
      cats,
      tier: BundleTier.premium,
      pick: _bestQualityPerCategory,
      reason: 'أعلى جودة ضمن هامش أعلى.',
      designNote: 'خامات وجودة أعلى وتناسق أوضح.',
      tradeoff: 'تكلفة أعلى؛ قد تتجاوز الميزانية.',
    );

    return [
      if (budgetBundle != null) budgetBundle,
      if (balancedBundle != null) balancedBundle,
      if (premiumBundle != null) premiumBundle,
    ];
  }

  Bundle? _bundleByStrategy(
    FurnishingProject project,
    List<ScoredCandidate> viable,
    Set<RecommendationCategory> cats, {
    required BundleTier tier,
    required ScoredCandidate? Function(List<ScoredCandidate>) pick,
    required String reason,
    required String designNote,
    required String tradeoff,
  }) {
    final items = <RecommendedItem>[];
    var total = 0.0;
    for (final cat in cats) {
      final ofCat = viable.where((s) => s.product.category == cat).toList();
      final chosen = pick(ofCat);
      if (chosen == null) continue;
      items.add(toRecommendedItem(chosen, ItemPriority.essential));
      total += chosen.product.price;
    }
    if (items.isEmpty) return null;

    final budget = project.budget;
    final exceeds = budget.hasBudget && total > budget.maxTotal;
    final tradeoffs = <String>[tradeoff];
    if (exceeds) {
      tradeoffs.add(
          'تتجاوز الميزانية بمقدار ${(total - budget.maxTotal).round()} ${budget.currency}.');
    }

    return Bundle(
      tier: tier,
      totalPrice: total,
      items: items,
      designNotes: [designNote],
      tradeoffs: tradeoffs,
      reason: reason,
      exceedsBudget: exceeds,
    );
  }

  ScoredCandidate? _cheapestPerCategory(List<ScoredCandidate> l) {
    if (l.isEmpty) return null;
    return l.reduce((a, b) => a.product.price <= b.product.price ? a : b);
  }

  ScoredCandidate? _bestScorePerCategory(List<ScoredCandidate> l) =>
      l.isEmpty ? null : l.first; // مرتّبة تنازليًا مسبقًا

  ScoredCandidate? _bestQualityPerCategory(List<ScoredCandidate> l) {
    if (l.isEmpty) return null;
    return l.reduce((a, b) {
      final ra = a.product.ratingOptional ?? 0;
      final rb = b.product.ratingOptional ?? 0;
      if (ra != rb) return ra >= rb ? a : b;
      return a.product.price >= b.product.price ? a : b;
    });
  }
}
