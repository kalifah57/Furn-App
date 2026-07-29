import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../shared/models/furnishing_project.dart';
import '../domain/project_repository.dart';

/// تخزين المشاريع في الذاكرة للـ MVP (يُستبدل بـ Firestore لاحقًا — القرار G3).
class InMemoryProjectRepository implements ProjectRepository {
  final Map<String, FurnishingProject> _store = {};

  @override
  Future<Result<void>> save(FurnishingProject project) async {
    _store[project.projectId] = project.copyWith(updatedAt: DateTime.now());
    return const Ok(null);
  }

  @override
  Future<Result<List<FurnishingProject>>> listProjects() async {
    final list = _store.values.toList()
      ..sort((a, b) => (b.updatedAt ?? DateTime(0))
          .compareTo(a.updatedAt ?? DateTime(0)));
    return Ok(list);
  }

  @override
  Future<Result<FurnishingProject>> getById(String projectId) async {
    final p = _store[projectId];
    return p == null ? const Err(NotFoundFailure('المشروع غير موجود.')) : Ok(p);
  }

  @override
  Future<Result<void>> delete(String projectId) async {
    _store.remove(projectId);
    return const Ok(null);
  }
}
