import '../../shared/models/models.dart';
import '../budget/budget_allocator.dart';
import 'bundle_composer.dart';
import 'category_mapper.dart';
import 'recommended_item_mapper.dart';
import 'scored_candidate.dart';
import 'scoring.dart';

/// محرّك التوصيات الحتمي (recommendation_engine.md) — منسّق للمراحل التسع.
///
/// مستقلّ تمامًا عن الـ AI. يأخذ مشروعًا مُستخرَجًا + كتالوجًا ويُنتج توصيات فردية
/// وباقات. تُفوَّض الباقات إلى [BundleComposer]، والتحويل إلى عنصر توصية إلى
/// recommended_item_mapper (بدء تفكيك المحرّك إلى محرّكات مستقلّة — decision_engine.md).
class RecommendationEngine {
  const RecommendationEngine({
    this.scorer = const RecommendationScorer(),
    this.allocator = const BudgetAllocator(),
    this.bundleComposer = const BundleComposer(),
  });

  final RecommendationScorer scorer;
  final BudgetAllocator allocator;
  final BundleComposer bundleComposer;

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

    // المراحل 1–6: التصفية (استبعاد فوري) + احتساب الدرجة.
    final viable = <ScoredCandidate>[];
    for (final p in catalog) {
      if (!p.isAvailable) continue; // مرحلة 5
      if (requestedCats.isNotEmpty && !requestedCats.contains(p.category)) {
        continue; // نوع لا يطابق الغرض المطلوب
      }
      final b = scorer.score(p, ctx); // مرحلة 6 (نحتاج room fit أدناه)
      if (b.room <= 0.0) continue; // لا يدخل المساحة (مرحلة 2)
      if (_exceedsHardPriceLimit(p, ctx)) continue; // سعر غير منطقي للفئة (مرحلة 3)
      viable.add(ScoredCandidate(p, b));
    }

    // مرحلة 7: ترتيب.
    viable.sort((a, b) => b.breakdown.total.compareTo(a.breakdown.total));

    final individual = _buildIndividual(viable, essentialCats, optionalCats);

    // مرحلة 8+9: الباقات (مع التحذيرات/التنازلات) عبر BundleComposer.
    final bundles = bundleComposer.compose(project, viable, essentialCats);

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
    List<ScoredCandidate> viable,
    Set<RecommendationCategory> essentialCats,
    Set<RecommendationCategory> optionalCats,
  ) {
    final result = <RecommendedItem>[];
    final seen = <String>{};

    void addTopForCategory(RecommendationCategory cat, ItemPriority priority, int n) {
      final ofCat = viable.where((s) => s.product.category == cat).take(n);
      for (final s in ofCat) {
        if (seen.add(s.product.productId)) {
          result.add(toRecommendedItem(s, priority));
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
          result.add(toRecommendedItem(s, ItemPriority.useful));
        }
      }
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }
}
