import '../../shared/models/models.dart';
import '../budget/budget_allocator.dart';
import 'category_mapper.dart';
import 'scoring.dart';

/// محرّك التوصيات الحتمي (recommendation_engine.md).
///
/// مستقلّ تمامًا عن الـ AI: يأخذ مشروعًا مُستخرَجًا + كتالوجًا ويُنتج توصيات فردية
/// وباقات عبر 9 مراحل، مع تحذيرات وتنازلات. قابل للاختبار بالكامل.
class RecommendationEngine {
  const RecommendationEngine({
    this.scorer = const RecommendationScorer(),
    this.allocator = const BudgetAllocator(),
  });

  final RecommendationScorer scorer;
  final BudgetAllocator allocator;

  Recommendations generate(
    FurnishingProject project,
    List<CatalogProduct> catalog,
  ) {
    final allocation = allocator.allocate(project.room, project.budget);
    final ctx = ScoringContext(
      room: project.room,
      budget: project.budget,
      style: project.style,
      categoryCeilings: allocation.ceilings,
    );

    // الفئات المطلوبة من العناصر الأساسية/الاختيارية.
    final essentialCats = _categoriesOf(project.items.essential);
    final optionalCats = _categoriesOf(project.items.optional);
    final requestedCats = {...essentialCats, ...optionalCats};

    // المراحل 1–5: التصفية (استبعاد فوري).
    final viable = <_ScoredProduct>[];
    for (final p in catalog) {
      if (!p.isAvailable) continue; // مرحلة 5
      if (requestedCats.isNotEmpty && !requestedCats.contains(p.category)) {
        continue; // نوع لا يطابق الغرض المطلوب
      }
      final b = scorer.score(p, ctx); // مرحلة 6 (نحتاج room fit أدناه)
      if (b.room <= 0.0) continue; // لا يدخل المساحة (مرحلة 2)
      if (_exceedsHardPriceLimit(p, ctx)) continue; // سعر غير منطقي للفئة (مرحلة 3)
      viable.add(_ScoredProduct(p, b));
    }

    // مرحلة 7: ترتيب.
    viable.sort((a, b) => b.breakdown.total.compareTo(a.breakdown.total));

    final individual = _buildIndividual(viable, essentialCats, optionalCats);

    // مرحلة 8: الباقات. مرحلة 9: التحذيرات/التنازلات داخل كل باقة.
    final bundles = _buildBundles(project, viable, essentialCats);

    return Recommendations(individualItems: individual, bundles: bundles);
  }

  Set<RecommendationCategory> _categoriesOf(List<RequestedItem> items) =>
      items.map((e) => mapTypeToCategory(e.type)).toSet();

  bool _exceedsHardPriceLimit(CatalogProduct p, ScoringContext ctx) {
    // استبعاد فوري لسعر غير منطقي للفئة (recommendation_engine.md).
    // الهامش 2.5× يسمح ببقاء عناصر الباقة المميّزة مع قطع الأسعار الشاذّة.
    final ceiling = ctx.categoryCeilings[p.category];
    if (ceiling != null && ceiling > 0) return p.price > ceiling * 2.5;
    if (ctx.budget.hasBudget) return p.price > ctx.budget.maxTotal;
    return false;
  }

  List<RecommendedItem> _buildIndividual(
    List<_ScoredProduct> viable,
    Set<RecommendationCategory> essentialCats,
    Set<RecommendationCategory> optionalCats,
  ) {
    final result = <RecommendedItem>[];
    final seen = <String>{};

    void addTopForCategory(RecommendationCategory cat, ItemPriority priority, int n) {
      final ofCat = viable.where((s) => s.product.category == cat).take(n);
      for (final s in ofCat) {
        if (seen.add(s.product.productId)) {
          result.add(_toRecommended(s, priority));
        }
      }
    }

    for (final cat in essentialCats) {
      addTopForCategory(cat, ItemPriority.essential, 2);
    }
    for (final cat in optionalCats) {
      addTopForCategory(cat, ItemPriority.optional, 1);
    }
    // إن لم تُطلب فئات محددة: أعلى العناصر عمومًا.
    if (essentialCats.isEmpty && optionalCats.isEmpty) {
      for (final s in viable.take(6)) {
        if (seen.add(s.product.productId)) {
          result.add(_toRecommended(s, ItemPriority.useful));
        }
      }
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }

  List<Bundle> _buildBundles(
    FurnishingProject project,
    List<_ScoredProduct> viable,
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
    List<_ScoredProduct> viable,
    Set<RecommendationCategory> cats, {
    required BundleTier tier,
    required _ScoredProduct? Function(List<_ScoredProduct>) pick,
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
      items.add(_toRecommended(chosen, ItemPriority.essential));
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

    // premium لا تُعرض فوق الميزانية إلا مع تحذير واضح (نبقيها مع علم exceedsBudget).
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

  _ScoredProduct? _cheapestPerCategory(List<_ScoredProduct> l) {
    if (l.isEmpty) return null;
    return l.reduce((a, b) => a.product.price <= b.product.price ? a : b);
  }

  _ScoredProduct? _bestScorePerCategory(List<_ScoredProduct> l) =>
      l.isEmpty ? null : l.first; // مرتّبة تنازليًا مسبقًا

  _ScoredProduct? _bestQualityPerCategory(List<_ScoredProduct> l) {
    if (l.isEmpty) return null;
    return l.reduce((a, b) {
      final ra = a.product.ratingOptional ?? 0;
      final rb = b.product.ratingOptional ?? 0;
      if (ra != rb) return ra >= rb ? a : b;
      return a.product.price >= b.product.price ? a : b;
    });
  }

  RecommendedItem _toRecommended(_ScoredProduct s, ItemPriority priority) {
    return RecommendedItem(
      name: s.product.title,
      category: s.product.category,
      price: s.product.price,
      reason: _reasonFor(s.breakdown),
      priority: priority,
      productId: s.product.productId,
      score: double.parse(s.breakdown.total.toStringAsFixed(1)),
    );
  }

  String _reasonFor(ScoreBreakdown b) {
    final parts = <String>[];
    if (b.room >= 0.8) parts.add('يناسب مساحة الغرفة');
    if (b.budget >= 0.7) parts.add('ضمن سقف الميزانية');
    if (b.style >= 0.7) parts.add('متوافق مع النمط المفضّل');
    if (b.quality >= 0.8) parts.add('تقييم مرتفع');
    if (parts.isEmpty) parts.add('خيار عملي متوازن');
    return '${parts.join('، ')}.';
  }
}

class _ScoredProduct {
  const _ScoredProduct(this.product, this.breakdown);
  final CatalogProduct product;
  final ScoreBreakdown breakdown;
}
