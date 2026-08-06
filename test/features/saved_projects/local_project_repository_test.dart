import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/features/saved_projects/data/local_project_repository.dart';
import 'package:furn_app/shared/models/models.dart';

/// «احفظ المشروع» كان يعرض «تم الحفظ» ثم يمحو كل شيء عند أول تحديث للصفحة.
/// الاختبار المركزي هنا هو **مستودع جديد فوق نفس القرص**: هذا بالضبط ما يحدث
/// حين يُغلق المستخدم المتصفّح ويعود.
void main() {
  late Map<String, String> disk;
  late DateTime clock;

  setUp(() {
    disk = {};
    clock = DateTime.utc(2026, 8, 6, 10);
  });

  LocalProjectRepository repo({bool refuseWrites = false}) =>
      LocalProjectRepository(
        read: (k) => disk[k],
        write: (k, v) {
          if (refuseWrites) throw StateError('quota exceeded');
          disk[k] = v;
        },
        now: () => clock,
      );

  FurnishingProject project(String id) => FurnishingProject(
        projectId: id,
        room: const Room(widthM: 4, lengthM: 3.7, roomType: RoomType.bedroom),
        budget: const Budget(maxTotal: 3000),
        items: const RequestedItems(
          essential: [RequestedItem(type: 'سرير')],
        ),
      );

  Future<List<String>> idsFrom(LocalProjectRepository r) async =>
      (await r.listProjects()).valueOrNull!.map((p) => p.projectId).toList();

  group('surviving the browser', () {
    test('a saved project is there in the next session', () async {
      await repo().save(project('studio'));

      // مستودع جديد تمامًا — لا حالة في الذاكرة، كل شيء من التخزين.
      expect(await idsFrom(repo()), ['studio']);
    });

    test('the project comes back whole, not just its id', () async {
      await repo().save(project('studio'));
      final back = (await repo().getById('studio')).valueOrNull!;
      expect(back.room.widthM, 4);
      expect(back.budget.maxTotal, 3000);
      expect(back.items.essential.single.type, 'سرير');
    });

    test('a delete survives too', () async {
      await repo().save(project('studio'));
      await repo().delete('studio');
      expect(await idsFrom(repo()), isEmpty);
    });

    test('nothing saved yet is an empty list, not an error', () async {
      final res = await repo().listProjects();
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, isEmpty);
    });
  });

  group('the list itself', () {
    test('saving the same id twice updates rather than duplicates', () async {
      await repo().save(project('studio'));
      clock = clock.add(const Duration(minutes: 5));
      await repo().save(project('studio'));
      expect(await idsFrom(repo()), ['studio']);
    });

    test('newest first', () async {
      await repo().save(project('old'));
      clock = clock.add(const Duration(hours: 1));
      await repo().save(project('new'));
      expect(await idsFrom(repo()), ['new', 'old']);
    });

    test('two saved in the same instant keep a stable order', () async {
      // `List.sort` في Dart غير مستقرّ: بلا فاصل ترتيب، مشروعان بنفس الطابع
      // الزمني كانا سيتبادلان المواضع بين استدعاءين بلا أن يفعل المستخدم شيئًا.
      await repo().save(project('b'));
      await repo().save(project('a'));
      expect(await idsFrom(repo()), ['a', 'b']);
      expect(await idsFrom(repo()), ['a', 'b']);
    });

    test('an unknown id is a NotFoundFailure, not a crash', () async {
      final res = await repo().getById('nope');
      expect(res.isErr, isTrue);
      expect(res.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('when the storage is bad', () {
    test('corrupt storage reads as empty instead of taking the app down',
        () async {
      disk[LocalProjectRepository.key] = 'not json';
      expect(await idsFrom(repo()), isEmpty);
    });

    test('an older schema is ignored', () async {
      disk[LocalProjectRepository.key] = jsonEncode({
        'v': LocalProjectRepository.version + 1,
        'projects': [project('studio').toJson()],
      });
      expect(await idsFrom(repo()), isEmpty);
    });

    test('an entry with no id is skipped, not collapsed onto its neighbours',
        () async {
      // مدخلان تالفان بلا معرّف كانا سيدهسان بعضهما تحت المفتاح الفارغ نفسه.
      disk[LocalProjectRepository.key] = jsonEncode({
        'v': LocalProjectRepository.version,
        'projects': [
          <String, dynamic>{'room': <String, dynamic>{}},
          <String, dynamic>{'room': <String, dynamic>{}},
          project('studio').toJson(),
        ],
      });
      expect(await idsFrom(repo()), ['studio']);
    });

    test('storage that refuses writes does not throw at the caller', () async {
      final res = await repo(refuseWrites: true).save(project('studio'));
      expect(res.isOk, isTrue);
      expect(await idsFrom(repo()), isEmpty);
    });
  });
}
