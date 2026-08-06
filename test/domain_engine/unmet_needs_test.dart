import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/domain_engine/plan/scope_table.dart';
import 'package:furn_app/domain_engine/plan/unmet_need.dart';
import 'package:furn_app/domain_engine/recommendation/category_mapper.dart';
import 'package:furn_app/shared/models/models.dart';

/// A plan that stays silent about what it could not do is not a plan anyone
/// trusts. These tests come from a real customer: a studio, 4x3.7m, 3000 SAR,
/// asking for a bed, a mattress, a fridge, a sofa bed and a TV stand — two of
/// which the catalog cannot represent at all.
void main() {
  late List<CatalogProduct> catalog;

  setUpAll(() {
    catalog = (jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .toList();
  });

  FurnishingProject projectAsking(
    List<String> essentials, {
    double budget = 3000,
    double widthM = 4,
    double lengthM = 3.7,
  }) =>
      FurnishingProject(
        projectId: 'studio',
        room: Room(widthM: widthM, lengthM: lengthM, roomType: RoomType.other),
        budget: Budget(maxTotal: budget),
        items: RequestedItems(
          essential: [for (final e in essentials) RequestedItem(type: e)],
        ),
      );

  PlanWorkspace workspaceFor(FurnishingProject p) =>
      PlanWorkspace(project: p, catalog: catalog);

  group('the mapper stops swallowing unknown types', () {
    test('a known type still maps as before', () {
      expect(mapTypeToCategoryOrNull('سرير'), RecommendationCategory.bed);
      expect(mapTypeToCategory('سرير'), RecommendationCategory.bed);
    });

    test('an unknown type is null, not `other`', () {
      expect(mapTypeToCategoryOrNull('ثلاجة'), isNull);
    });

    test('the old function keeps its contract for existing callers', () {
      expect(mapTypeToCategory('ثلاجة'), RecommendationCategory.other);
    });
  });

  group('the scope table', () {
    test('a fridge is out of scope, with an estimate', () {
      final need = lookupScope('ثلاجة')!;
      expect(need.reason, UnmetReason.outOfScope);
      expect(need.hasEstimate, isTrue);
    });

    test('a mattress is in scope but not stocked — a supply gap, not a limit',
        () {
      expect(lookupScope('مرتبة')!.reason, UnmetReason.notStocked);
    });

    test('the spec picks the tier: "صغيرة" costs less than the default', () {
      final small = lookupScope('ثلاجة صغيرة')!;
      final plain = lookupScope('ثلاجة')!;
      expect(small.tier!.lowSar, lessThan(plain.tier!.lowSar));
      expect(plain.tier!.isDefault, isTrue);
    });

    test('"بحجم مقبول" resolves to the medium tier', () {
      expect(lookupScope('ثلاجة بحجم مقبول')!.tier!.labelAr, contains('متوسطة'));
    });

    test('a large fridge costs more than the default', () {
      expect(lookupScope('ثلاجة كبيرة')!.tier!.lowSar,
          greaterThan(lookupScope('ثلاجة')!.tier!.lowSar));
    });

    test('items with no researched figure carry no invented one', () {
      // A number without a source misleads a budget more than no number does.
      expect(lookupScope('غسالة')!.hasEstimate, isFalse);
      expect(lookupScope('غسالة')!.reserveSar, 0);
    });

    test('something we never heard of is not claimed as known', () {
      expect(lookupScope('غوّاصة'), isNull);
    });

    test('lookup is deterministic', () {
      expect(lookupScope('ثلاجة'), lookupScope('ثلاجة'));
    });
  });

  group('the plan declares the gap', () {
    test('a fridge no longer shows up as "ناقص: أخرى"', () {
      final plan = workspaceFor(projectAsking(['سرير', 'ثلاجة'])).build();
      expect(plan.missingCategories, isNot(contains(RecommendationCategory.other)));
      expect(plan.unmetNeeds.map((u) => u.rawType), contains('ثلاجة'));
    });

    test('the user\'s own words are kept, not a category we chose', () {
      final plan = workspaceFor(projectAsking(['ثلاجة بحجم مقبول'])).build();
      expect(plan.unmetNeeds.single.rawType, 'ثلاجة بحجم مقبول');
    });

    test('the two reasons stay apart', () {
      final plan = workspaceFor(projectAsking(['ثلاجة', 'مرتبة'])).build();
      final byType = {for (final u in plan.unmetNeeds) u.rawType: u.reason};
      expect(byType['ثلاجة'], UnmetReason.outOfScope);
      expect(byType['مرتبة'], UnmetReason.notStocked);
    });

    test('a plan with nothing unknown behaves exactly as before', () {
      final plan = workspaceFor(projectAsking(['سرير', 'دولاب'])).build();
      expect(plan.unmetNeeds, isEmpty);
      expect(plan.effectiveBudgetSar, isNull);
      expect(plan.reservedSar, 0);
    });

    test('a request we have never heard of is still declared, not dropped', () {
      // The regression this guards: excluding unknown types from
      // missingCategories without declaring them turned "ناقص: أخرى" — a bad
      // label on a visible gap — into complete silence, which is worse.
      final plan = workspaceFor(projectAsking(['سرير', 'نباتات'])).build();
      expect(plan.unmetNeeds.map((u) => u.rawType), contains('نباتات'));
      expect(plan.unmetNeeds.single.reason, UnmetReason.notStocked);
      expect(plan.unmetNeeds.single.hasEstimate, isFalse);
    });

    test('an unheard-of request still lowers confidence', () {
      final plan = workspaceFor(projectAsking(['سرير', 'لوحة جدارية'])).build();
      expect(plan.assurances.essentialsComplete, isFalse);
    });

    test('an empty request type is ignored rather than declared', () {
      final plan = workspaceFor(projectAsking(['سرير', '  '])).build();
      expect(plan.unmetNeeds, isEmpty);
    });

    test('duplicates are collapsed and output is ordered', () {
      final plan =
          workspaceFor(projectAsking(['مرتبة', 'ثلاجة', 'مرتبة'])).build();
      expect(plan.unmetNeeds.length, 2);
      final types = plan.unmetNeeds.map((u) => u.rawType).toList();
      expect(types, List.of(types)..sort());
    });
  });

  group('the budget tells the truth', () {
    test('a fridge is reserved out of the furniture budget', () {
      final plan = workspaceFor(projectAsking(['سرير', 'ثلاجة'])).build();
      expect(plan.effectiveBudgetSar, lessThan(3000));
      expect(plan.effectiveBudgetSar, 3000 - plan.reservedSar);
    });

    test('a smaller fridge leaves more for furniture — the spec moves money',
        () {
      final small =
          workspaceFor(projectAsking(['سرير', 'ثلاجة صغيرة'])).build();
      final plain = workspaceFor(projectAsking(['سرير', 'ثلاجة'])).build();
      expect(small.effectiveBudgetSar,
          greaterThan(plain.effectiveBudgetSar as double));
    });

    test('an item with no estimate reserves nothing', () {
      final plan = workspaceFor(projectAsking(['سرير', 'غسالة'])).build();
      expect(plan.reservedSar, 0);
      expect(plan.effectiveBudgetSar, isNull);
    });

    test('a reserve larger than the budget floors at zero, never negative', () {
      final plan = workspaceFor(
              projectAsking(['سرير', 'ثلاجة كبيرة'], budget: 1000))
          .build();
      expect(plan.effectiveBudgetSar, 0);
      expect(plan.assurances.withinBudget, isFalse);
    });
  });

  group('confidence separates a declared limit from a real gap', () {
    test('being out of scope does not punish us', () {
      final clean = workspaceFor(projectAsking(['سرير'])).build();
      final withFridge = workspaceFor(projectAsking(['سرير', 'ثلاجة'])).build();
      expect(withFridge.assurances.essentialsComplete,
          clean.assurances.essentialsComplete);
    });

    test('a supply gap does', () {
      final withMattress =
          workspaceFor(projectAsking(['سرير', 'مرتبة'])).build();
      expect(withMattress.assurances.essentialsComplete, isFalse);
    });
  });

  group('the first customer, end to end', () {
    test('studio 4x3.7m, 3000 SAR, five things asked for', () {
      final plan = workspaceFor(projectAsking([
        'سرير',
        'مرتبة',
        'ثلاجة بحجم مقبول',
        'أريكة',
        'طاولة تلفزيون',
      ])).build();

      // Three we can serve, two we must declare.
      expect(plan.items, isNotEmpty);
      expect(plan.unmetNeeds.length, 2);
      expect(plan.unmetNeeds.map((u) => u.reason).toSet(),
          {UnmetReason.outOfScope, UnmetReason.notStocked});

      // He plans against what is left, not against 3000.
      expect(plan.effectiveBudgetSar, lessThan(3000));

      // And he is shown a cheaper fridge tier, because it changes the outcome.
      final fridge =
          plan.unmetNeeds.firstWhere((u) => u.rawType.contains('ثلاجة'));
      expect(fridge.hasCheaperAlternative, isTrue);
      expect(fridge.cheapestTier!.lowSar, lessThan(fridge.tier!.lowSar));
    });

    test('the whole pipeline is reproducible', () {
      String render() {
        final p = workspaceFor(projectAsking(
                ['سرير', 'مرتبة', 'ثلاجة بحجم مقبول', 'أريكة']))
            .build();
        return '${p.effectiveBudgetSar}|'
            '${p.unmetNeeds.map((u) => '${u.rawType}:${u.reason.name}').join(',')}';
      }

      expect(render(), render());
    });
  });
}
