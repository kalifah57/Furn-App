import '../../../core/errors/result.dart';
import '../../../domain_engine/recommendation/recommendation_engine.dart';
import '../../../shared/models/catalog_product.dart';
import '../../../shared/models/furnishing_project.dart';
import '../../../shared/models/room_analysis.dart';
import '../../../shared/services/catalog_repository.dart';
import '../domain/recommendation_repository.dart';

/// تنفيذ التوصيات: يحمّل الكتالوج ثم يشغّل المحرّك الحتمي، مع سلوك fallback.
class RecommendationRepositoryImpl implements RecommendationRepository {
  const RecommendationRepositoryImpl({
    required this.catalog,
    this.engine = const RecommendationEngine(),
  });

  final CatalogRepository catalog;
  final RecommendationEngine engine;

  @override
  Future<Result<FurnishingProject>> recommend(FurnishingProject project) async {
    final loaded = await catalog.loadProducts();
    return switch (loaded) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(_withRecommendations(project, value)),
    };
  }

  FurnishingProject _withRecommendations(
      FurnishingProject project, List<CatalogProduct> products) {
    final recs = engine.generate(project, products);
    if (recs.isEmpty) {
      // fallback behavior (recommendation_engine.md / catalog_strategy.md).
      final warnings = <String>{
        ...project.analysis.warnings,
        'لا توجد منتجات كافية مطابقة؛ نعرض إرشادات عامة أو نطلب صورًا/تعديل الميزانية.',
      }.toList();
      return project.copyWith(
        recommendations: recs,
        analysis: project.analysis.copyWith(warnings: warnings),
        nextActions: project.nextActions.copyWith(askForImages: true),
      );
    }
    return project.copyWith(recommendations: recs);
  }
}
