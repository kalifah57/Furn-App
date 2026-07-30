import '../../shared/models/models.dart';
import '../budget/budget_allocator.dart';
import '../constraint/constraint_engine.dart';
import 'bundle_composer.dart';
import 'category_mapper.dart';
import 'recommended_item_mapper.dart';
import 'scored_candidate.dart';
import 'scoring.dart';

/// محرّك التوصيات الحتمي (recommendation_engine.md) — منسّق للمراحل التسع.
///
/// مستقلّ تمامًا عن الـ AI. يفوّض: التصفية+التقييم إلى [ConstraintEngine]، وتكوين
/// الباقات إلى [BundleComposer]، والتحويل إلى عنصر توصية إلى recommended_item_mapper
/// (تفكيك المحرّك إلى محرّكات مستقلّة — decision_engine.md).
class RecommendationEngine {
  const RecommendationEngine({
    this.scorer = const RecommendationScorer(),
    this.allocator = const BudgetAllocator(),
    this.constraintEngine = const ConstraintEngine(),
    this.bundleComposer = const BundleComposer(),
  });

  final RecommendationScorer scorer;
  final BudgetAllocator allocator;
  final ConstraintEngine constraintEngine;
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

    // المراحل 1–7: التصفية + التقييم + الترتيب.
    final viable =
        constraintEngine.selectEligible(catalog, ctx, requestedCats, scorer);

    final individual = _buildIndividual(viable, essentialCats, optionalCats);

    // المرحلة 8+9: الباقات (مع التحذيرات/التنازلات).
    final bundles = bundleComposer.compose(project, viable, essentialCats);

    return Recommendations(individualItems: individual, bundles: bundles);
  }

  Set<RecommendationCategory> _categoriesOf(List<RequestedItem> items) =>
      items.map((e) => mapTypeToCategory(e.type)).toSet();

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
