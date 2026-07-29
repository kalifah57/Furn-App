import '../../../core/errors/result.dart';
import '../../../shared/models/furnishing_project.dart';

/// واجهة توليد التوصيات: تربط المشروع المُستخرَج بالكتالوج + المحرّك الحتمي.
abstract interface class RecommendationRepository {
  /// يُعيد المشروع نفسه بعد ملء `recommendations` (وتحذيرات fallback عند اللزوم).
  Future<Result<FurnishingProject>> recommend(FurnishingProject project);
}
