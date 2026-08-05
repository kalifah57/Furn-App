import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/core/errors/result.dart';
import 'package:furn_app/domain_engine/project/project.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart'
    show planProjectProvider;
import 'package:furn_app/features/plan/presentation/project_controller.dart';
import 'package:furn_app/features/saved_projects/domain/project_repository.dart';
import 'package:furn_app/shared/models/models.dart';
import 'package:furn_app/shared/services/catalog_repository.dart';

/// Captures saved briefs so we can assert persistence on approve.
class FakeProjectRepository implements ProjectRepository {
  final List<FurnishingProject> saved = [];

  @override
  Future<Result<void>> save(FurnishingProject project) async {
    saved.add(project);
    return const Ok(null);
  }

  @override
  Future<Result<List<FurnishingProject>>> listProjects() async => Ok(saved);

  @override
  Future<Result<FurnishingProject>> getById(String projectId) async {
    for (final p in saved) {
      if (p.projectId == projectId) return Ok(p);
    }
    return const Err(NotFoundFailure('غير موجود'));
  }

  @override
  Future<Result<void>> delete(String projectId) async {
    saved.removeWhere((e) => e.projectId == projectId);
    return const Ok(null);
  }
}

void main() {
  const catalog = <CatalogProduct>[
    const CatalogProduct(
        productId: 'bed_a',
        title: 'سرير أ',
        category: RecommendationCategory.bed,
        widthCm: 90,
        depthCm: 200,
        price: 450),
    const CatalogProduct(
        productId: 'bed_b',
        title: 'سرير ب',
        category: RecommendationCategory.bed,
        widthCm: 140,
        depthCm: 200,
        price: 780),
    const CatalogProduct(
        productId: 'ward_a',
        title: 'دولاب أ',
        category: RecommendationCategory.storage,
        widthCm: 80,
        depthCm: 50,
        price: 540),
  ];

  final project = FurnishingProject(
    projectId: 't',
    room: const Room(widthM: 3, lengthM: 3.5, roomType: RoomType.bedroom),
    budget: const Budget(maxTotal: 1800),
    items: const RequestedItems(
      essential: [RequestedItem(type: 'سرير'), RequestedItem(type: 'دولاب')],
    ),
  );

  ProviderContainer make(DebugAnalytics debug, FakeProjectRepository repo) {
    final c = ProviderContainer(overrides: [
      catalogRepositoryProvider
          .overrideWithValue(const InMemoryCatalogRepository(catalog)),
      analyticsProvider.overrideWithValue(debug),
      projectRepositoryProvider.overrideWithValue(repo),
      planProjectProvider.overrideWithValue(project),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('draft → active → approved: funnel order + timeline + persistence',
      () async {
    final debug = DebugAnalytics(log: false);
    final repo = FakeProjectRepository();
    final c = make(debug, repo);

    final seeded = await c.read(projectControllerProvider.future);
    expect(seeded.status, ProjectStatus.draft);
    expect(debug.names, ['plan_seeded']);

    final ctrl = c.read(projectControllerProvider.notifier);
    ctrl.pin('bed_b');
    final afterPin = c.read(projectControllerProvider).requireValue;
    expect(afterPin.status, ProjectStatus.active);
    expect(afterPin.timeline.length, 1);

    ctrl.setBudget(2000);
    await ctrl.approve();

    final approved = c.read(projectControllerProvider).requireValue;
    expect(approved.status, ProjectStatus.approved);
    expect(approved.brief.budget.maxTotal, 2000); // brief synced from the engine
    expect(repo.saved.map((e) => e.projectId), contains('t'));
    expect(debug.names,
        ['plan_seeded', 'item_pinned', 'budget_changed', 'plan_finalized']);
    final fin = debug.events.whereType<PlanFinalized>().single;
    expect(fin.edits, greaterThanOrEqualTo(2)); // pin + budget
  });

  test('session_abandoned fires once before approve', () async {
    final debug = DebugAnalytics(log: false);
    final c = make(debug, FakeProjectRepository());

    await c.read(projectControllerProvider.future);
    final ctrl = c.read(projectControllerProvider.notifier);
    ctrl.logAbandonedIfUnfinished();
    ctrl.logAbandonedIfUnfinished();

    expect(debug.names, ['plan_seeded', 'session_abandoned']);
  });

  test('no session_abandoned after approve', () async {
    final debug = DebugAnalytics(log: false);
    final c = make(debug, FakeProjectRepository());

    await c.read(projectControllerProvider.future);
    final ctrl = c.read(projectControllerProvider.notifier);
    await ctrl.approve();
    ctrl.logAbandonedIfUnfinished();

    expect(debug.names, ['plan_seeded', 'plan_finalized']);
  });
}
