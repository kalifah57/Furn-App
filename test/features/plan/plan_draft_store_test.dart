import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/plan/plan.dart';
import 'package:furn_app/domain_engine/plan/plan_workspace.dart';
import 'package:furn_app/features/plan/data/plan_draft_store.dart';
import 'package:furn_app/shared/models/models.dart';

/// خطة تختفي عند تحديث الصفحة ليست خطة يملكها أحد.
///
/// الادّعاء المركزي هنا أن **الخطة مشتقّة لا مخزّنة**: المحرّك حتمي، فحفظ
/// المُلخّص وقرارات المستخدم يكفي لإعادة إنتاج الخطة نفسها حرفيًا. أول اختبار في
/// مجموعة «الاستعادة» يثبت ذلك؛ البقيّة تحرس ما يحدث حين يسوء التخزين.
void main() {
  late Map<String, String> disk;
  late List<CatalogProduct> catalog;

  setUpAll(() {
    catalog = (jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
            as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .toList();
  });

  setUp(() => disk = {});

  PlanDraftStore storeOver(Map<String, String> d, {bool refuseWrites = false}) =>
      PlanDraftStore(
        read: (k) => d[k],
        write: (k, v) {
          if (refuseWrites) throw StateError('quota exceeded');
          d[k] = v;
        },
        remove: d.remove,
      );

  const brief = FurnishingProject(
    projectId: 'studio',
    room: Room(widthM: 4, lengthM: 3.7, roomType: RoomType.bedroom),
    budget: Budget(maxTotal: 3000),
    style: StylePreferences(preferred: ['modern'], colors: ['gray']),
    items: RequestedItems(
      essential: [RequestedItem(type: 'سرير'), RequestedItem(type: 'دولاب')],
      optional: [RequestedItem(type: 'إضاءة')],
    ),
  );

  /// بصمة الخطة: ما يراه المستخدم فعلًا — القطع وترتيبها والمجموع والثقة.
  String sign(Plan p) => '${p.confidence}|${p.total}|${p.itemCount}|'
      '${p.items.map((e) => '${e.item.productId}:${e.status.name}').join(',')}';

  String idOf(RecommendationCategory c) =>
      catalog.firstWhere((p) => p.category == c).productId;

  group('the plan is derived, not stored', () {
    test('replaying a saved draft reproduces the same plan exactly', () {
      final before = PlanWorkspace(project: brief, catalog: catalog);
      before.pin(idOf(RecommendationCategory.bed));
      before.reject(idOf(RecommendationCategory.storage));
      before.setBudget(2500);
      final expected = before.build();

      final store = storeOver(disk);
      store.save(before.project, before.snapshot());

      // جلسة جديدة: لا شيء في الذاكرة، كل شيء من التخزين.
      final draft = store.load()!;
      final after = PlanWorkspace(project: draft.brief, catalog: catalog)
        ..restore(draft.state);

      expect(sign(after.build()), sign(expected));
    });

    test('the brief survives whole — the room the user described', () {
      final store = storeOver(disk);
      store.save(brief, PlanWorkspace(project: brief, catalog: catalog).snapshot());
      expect(store.load()!.brief, brief);
    });

    test('a budget the user changed is part of what is saved', () {
      final ws = PlanWorkspace(project: brief, catalog: catalog)
        ..setBudget(1750);
      final store = storeOver(disk);
      store.save(ws.project, ws.snapshot());
      expect(store.load()!.state.budgetMax, 1750);
      expect(store.load()!.brief.budget.maxTotal, 1750);
    });

    test('a finished plan comes back finished', () {
      final ws = PlanWorkspace(project: brief, catalog: catalog)..finalizePlan();
      final store = storeOver(disk);
      store.save(ws.project, ws.snapshot());
      expect(store.load()!.state.finalized, isTrue);
    });
  });

  group('when there is nothing to restore', () {
    test('an empty store means no draft, not an error', () {
      expect(storeOver(disk).load(), isNull);
    });

    test('clear removes it', () {
      final store = storeOver(disk);
      store.save(brief, PlanWorkspace(project: brief, catalog: catalog).snapshot());
      store.clear();
      expect(store.load(), isNull);
    });
  });

  group('when the storage is bad', () {
    test('a draft from an older schema is ignored, not half-restored', () {
      // نصف استعادة أسوأ من لا استعادة: المستخدم لا يرى ما ضاع منه.
      disk[PlanDraftStore.key] = jsonEncode({
        'v': PlanDraftStore.version + 1,
        'brief': brief.toJson(),
        'state': {'pinned': [], 'rejected': [], 'budget_max': 3000, 'finalized': false},
      });
      expect(storeOver(disk).load(), isNull);
    });

    test('corrupt json yields no draft, and is cleared so it stops failing', () {
      disk[PlanDraftStore.key] = '{not json at all';
      expect(storeOver(disk).load(), isNull);
      expect(disk.containsKey(PlanDraftStore.key), isFalse);
    });

    test('a missing budget is not silently read as zero', () {
      // لو عوّضناه بصفر لاستعاد المستخدم خطته بميزانية صفر دون أن يعرف السبب.
      disk[PlanDraftStore.key] = jsonEncode({
        'v': PlanDraftStore.version,
        'brief': brief.toJson(),
        'state': {'pinned': [], 'rejected': [], 'finalized': false},
      });
      expect(storeOver(disk).load(), isNull);
    });

    test('storage that refuses writes does not take the app down', () {
      // وضع التصفّح الخاص في Safari يرمي عند الكتابة.
      final store = storeOver(disk, refuseWrites: true);
      expect(
        () => store.save(
            brief, PlanWorkspace(project: brief, catalog: catalog).snapshot()),
        returnsNormally,
      );
      expect(store.load(), isNull);
    });
  });

  group('the stored form', () {
    test('is deterministic — same state, same bytes', () {
      final a = <String, String>{};
      final b = <String, String>{};
      for (final d in [a, b]) {
        final ws = PlanWorkspace(project: brief, catalog: catalog)
          ..pin(idOf(RecommendationCategory.bed))
          ..pin(idOf(RecommendationCategory.lamp))
          ..reject(idOf(RecommendationCategory.storage));
        storeOver(d).save(ws.project, ws.snapshot());
      }
      expect(a[PlanDraftStore.key], b[PlanDraftStore.key]);
    });

    test('carries a schema version, so the next change can reject it', () {
      final store = storeOver(disk);
      store.save(brief, PlanWorkspace(project: brief, catalog: catalog).snapshot());
      final map = jsonDecode(disk[PlanDraftStore.key]!) as Map<String, dynamic>;
      expect(map['v'], PlanDraftStore.version);
    });
  });
}
