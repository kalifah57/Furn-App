import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/plan/plan.dart';
import 'package:furn_app/domain_engine/project/decision.dart';
import 'package:furn_app/domain_engine/project/project.dart';
import 'package:furn_app/shared/models/models.dart';

/// The Project aggregate root: records a Decision Timeline and drives the
/// Draft → Active → Approved lifecycle. Pure domain — no Flutter.
void main() {
  const plan = Plan(
    items: const [],
    total: 1200,
    assurances: const Assurances(
      fitsRoom: true,
      withinBudget: true,
      allAvailable: true,
      essentialsComplete: true,
    ),
    confidence: 80,
    missingCategories: const [],
  );

  final brief = FurnishingProject(
    projectId: 'p1',
    room: const Room(widthM: 3, lengthM: 3.5, roomType: RoomType.bedroom),
    budget: const Budget(maxTotal: 1800),
    items: const RequestedItems(essential: [RequestedItem(type: 'سرير')]),
  );

  Project draft() => Project(id: 'p1', brief: brief, plan: plan);

  test('a fresh project starts as Draft with an empty timeline', () {
    final p = draft();
    expect(p.status, ProjectStatus.draft);
    expect(p.timeline.isEmpty, isTrue);
    expect(p.isApproved, isFalse);
  });

  test('recording a decision moves Draft → Active and appends to the timeline',
      () {
    var p = draft();
    p = p.record(
      Decision(
          kind: DecisionKind.pinned,
          at: DateTime(2026),
          category: RecommendationCategory.bed),
      plan,
    );
    p = p.record(
      Decision(kind: DecisionKind.budgetSet, at: DateTime(2026), value: 2000),
      plan,
    );

    expect(p.status, ProjectStatus.active);
    expect(p.timeline.length, 2);
    expect(p.timeline.edits, 2);
    expect(p.timeline.last!.kind, DecisionKind.budgetSet);
  });

  test('approve transitions to Approved and records an approve decision', () {
    final at = DateTime(2026, 1, 2);
    var p = draft().record(
      Decision(kind: DecisionKind.pinned, at: DateTime(2026)),
      plan,
    );
    p = p.approve(at);

    expect(p.isApproved, isTrue);
    expect(p.approvedAt, at);
    expect(p.timeline.last!.kind, DecisionKind.approved);
    expect(p.timeline.edits, 1); // approve is not counted as a user edit
  });

  test('reopen returns an approved project to Active', () {
    var p = draft().approve(DateTime(2026)).reopen(DateTime(2026, 1, 3));
    expect(p.status, ProjectStatus.active);
    expect(p.approvedAt, isNull);
    expect(p.timeline.last!.kind, DecisionKind.reopened);
  });
}
