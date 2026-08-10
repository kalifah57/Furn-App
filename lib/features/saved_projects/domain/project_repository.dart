import '../../../core/errors/result.dart';
import '../../../shared/models/furnishing_project.dart';

/// واجهة حفظ/استرجاع المشاريع (PRD — حفظ المشاريع).
abstract interface class ProjectRepository {
  Future<Result<void>> save(FurnishingProject project);
  Future<Result<List<FurnishingProject>>> listProjects();
  Future<Result<FurnishingProject>> getById(String projectId);
  Future<Result<void>> delete(String projectId);
}
