import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart';
import 'package:furn_app/shared/models/models.dart';

/// The confidence funnel emits the right typed events through a swappable sink.
void main() {
  const catalog = <CatalogProduct>[
    CatalogProduct(
        productId: 'bed_a',
        title: 'سرير أ',
        category: RecommendationCategory.bed,
        widthCm: 90,
        depthCm: 200,
        price: 450),
    CatalogProduct(
        productId: 'bed_b',
        title: 'سرير ب',
        category: RecommendationCategory.bed,
        widthCm: 140,
        depthCm: 200,
        price: 780),
    CatalogProduct(
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

  PlanController controllerWith(DebugAnalytics a) => PlanController(
        PlanWorkspace(project: project, catalog: catalog),
        analytics: a,
      );

  test('happy path funnel: seed → pin → finalize', () {
    final a = DebugAnalytics(log: false);
    final c = controllerWith(a); // plan_seeded (on construction)
    c.pin('bed_b'); // item_pinned
    c.finalizePlan(); // plan_finalized
    addTearDown(c.dispose);

    expect(a.names, ['plan_seeded', 'item_pinned', 'plan_finalized']);
    final finalized = a.events.whereType<PlanFinalized>().single;
    expect(finalized.edits, greaterThanOrEqualTo(1));
    expect(finalized.pinnedCount, greaterThanOrEqualTo(1));
    final pinned = a.events.whereType<ItemPinned>().single;
    expect(pinned.category, 'bed');
  });

  test('abandon path: leaving unfinished emits session_abandoned exactly once',
      () {
    final a = DebugAnalytics(log: false);
    final c = controllerWith(a); // plan_seeded
    addTearDown(c.dispose);

    c.logAbandonedIfUnfinished(); // session_abandoned
    c.logAbandonedIfUnfinished(); // no duplicate

    expect(a.names, ['plan_seeded', 'session_abandoned']);
  });

  test('a finalized session is never counted as abandoned', () {
    final a = DebugAnalytics(log: false);
    final c = controllerWith(a);
    addTearDown(c.dispose);

    c.finalizePlan(); // plan_seeded, plan_finalized
    c.logAbandonedIfUnfinished(); // no-op — already finalized

    expect(a.names, ['plan_seeded', 'plan_finalized']);
  });

  test('consent = false drops every event', () {
    final a = DebugAnalytics(consent: false, log: false);
    final c = controllerWith(a);
    addTearDown(c.dispose);

    c.pin('bed_b');
    c.finalizePlan();

    expect(a.events, isEmpty);
  });
}
