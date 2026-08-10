import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/plan/plan.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/shared/models/models.dart';

/// The confidence number is only trustworthy if it can explain itself. These
/// tests hold the advice to the same arithmetic as the meter: every point the
/// user is missing is a concrete gap they can close, and nothing is promised
/// that the meter would not actually pay.
void main() {
  late List<CatalogProduct> catalog;

  setUpAll(() {
    catalog = (jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .toList();
  });

  FurnishingProject project(
    List<String> essentials, {
    double budget = 5000,
    double widthM = 4,
    double lengthM = 4,
  }) =>
      FurnishingProject(
        projectId: 'p',
        room: Room(widthM: widthM, lengthM: lengthM, roomType: RoomType.bedroom),
        budget: Budget(maxTotal: budget),
        items: RequestedItems(
          essential: [for (final e in essentials) RequestedItem(type: e)],
        ),
      );

  int gapPoints(Plan plan) =>
      plan.confidenceGaps.fold<int>(0, (s, g) => s + g.points);

  group('the advice matches the meter', () {
    test('confidence plus the unmet gaps always totals 100', () {
      // The invariant that makes the number honest: each component is either
      // true (counted in confidence) or a gap (counted here), never neither,
      // never both.
      for (final p in [
        project(['سرير']),
        project(['سرير', 'دولاب', 'أريكة'], budget: 300), // over budget
        project(['سرير', 'مرآة']), // an unmet, not-stocked essential
        project(['سرير'], widthM: 0, lengthM: 0), // room unknown
      ]) {
        final plan = PlanWorkspace(project: p, catalog: catalog).build();
        expect(plan.confidence + gapPoints(plan), 100,
            reason: 'confidence ${plan.confidence} + gaps ${gapPoints(plan)}');
      }
    });

    test('a met component never appears as a gap', () {
      final plan = PlanWorkspace(project: project(['سرير']), catalog: catalog)
          .build();
      if (plan.assurances.withinBudget) {
        expect(plan.confidenceGaps.any((g) => g.label.contains('الميزانية')),
            isFalse);
      }
    });
  });

  group('the gaps are actionable', () {
    test('the budget gap is present exactly when the plan is over budget', () {
      // Contract, not a guess about the engine's allocator: gap iff !within.
      final plan = PlanWorkspace(
              project: project(['سرير', 'دولاب', 'أريكة'], budget: 200),
              catalog: catalog)
          .build();
      final budgetGap =
          plan.confidenceGaps.where((g) => g.label.contains('الميزانية'));
      if (plan.assurances.withinBudget) {
        expect(budgetGap, isEmpty);
      } else {
        expect(budgetGap.single.points, 25);
        expect(budgetGap.single.actions.single, contains('تجاوزت'));
      }
    });

    test('an unmet essential lowers confidence and shows an essentials gap', () {
      // مرآة is not stocked (scope_table) → it lowers confidence deterministically.
      final plan =
          PlanWorkspace(project: project(['سرير', 'مرآة']), catalog: catalog)
              .build();
      expect(plan.assurances.essentialsComplete, isFalse);
      final essentials =
          plan.confidenceGaps.where((g) => g.label.contains('الأساسيات'));
      expect(essentials.single.points, 40);
      expect(essentials.single.actions, isNotEmpty);
    });

    test('gaps are ordered by impact, biggest first', () {
      final plan = PlanWorkspace(
              project: project(['سرير', 'مرآة'], budget: 150), catalog: catalog)
          .build();
      final pts = plan.confidenceGaps.map((g) => g.points).toList();
      expect(pts, List.of(pts)..sort((a, b) => b.compareTo(a)));
    });

    test('a plan with nothing missing has no gaps to show', () {
      // Build a plan, then satisfy it: if the engine reaches full assurances,
      // the advice list must be empty — we never ask for work already done.
      final plan = PlanWorkspace(project: project(['سرير']), catalog: catalog)
          .build();
      if (plan.confidence == 100) {
        expect(plan.confidenceGaps, isEmpty);
      }
    });

    test('advice is deterministic', () {
      String render() {
        final plan = PlanWorkspace(
                project: project(['سرير', 'مرآة'], budget: 150),
                catalog: catalog)
            .build();
        return plan.confidenceGaps
            .map((g) => '${g.label}:${g.points}:${g.actions.join("|")}')
            .join(';');
      }

      expect(render(), render());
    });
  });
}
