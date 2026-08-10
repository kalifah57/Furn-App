import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/router/app_router.dart';

/// سطح الملاحة هو نموذج المنتج مكتوبًا بالشيفرة: **ثلاث تجارب لا أكثر**.
///
/// هذه الاختبارات تحرس شيئين لا يمسكهما المترجم:
/// * أن تبقى التجارب ثلاثًا — إضافة وجهة رابعة على المستوى الأعلى هي القرار
///   الذي يُفلت عادةً بلا نقاش، فيتحوّل المنتج إلى قائمة شاشات.
/// * أن يكون كل ثابت في [Routes] مسارًا مُهيّأً فعلًا — `context.go` إلى مسار
///   غير مُعلَن لا يفشل عند البناء، بل يعرض صفحة خطأ للمستخدم وقت التشغيل.
void main() {
  final paths = appRoutes.map((r) => r.path).toList();

  /// كل ثابت يستطيع أي شاشة أن تنتقل إليه — تُحدَّث يدويًا لأن Dart لا تتيح
  /// تعداد أعضاء صنف، وهذا بالضبط ما يجعل الاختبار مفيدًا.
  const declared = [
    Routes.onboarding,
    Routes.assistant,
    Routes.assistantManual,
    Routes.assistantThinking,
    Routes.room,
    Routes.roomSaved,
    Routes.preview,
  ];

  group('ثلاث تجارب، لا رابعة', () {
    test('التجارب ثلاث بالضبط، وكلٌّ منها مسار حقيقي', () {
      expect(Routes.experiences, hasLength(3));
      for (final e in Routes.experiences) {
        expect(paths, contains(e));
      }
    });

    test('كل شاشة إمّا الباب وإمّا تحت إحدى التجارب الثلاث', () {
      for (final p in paths) {
        if (p == Routes.onboarding) continue;
        expect(
          Routes.experiences.any((e) => p == e || p.startsWith('$e/')),
          isTrue,
          reason: '«$p» لا ينتمي لأي من التجارب الثلاث',
        );
      }
    });

    test('الواقع المعزّز ليس شاشة في الـ MVP', () {
      expect(paths, isNot(contains('/ar')));
    });
  });

  group('لا وجهة معطوبة', () {
    test('كل ثابت مُعلَن له مسار مُهيّأ', () {
      for (final d in declared) {
        expect(paths, contains(d), reason: '«$d» ثابت بلا مسار — 404 وقت التشغيل');
      }
    });

    test('ولا مسار مُهيّأ بلا اسم يناديه', () {
      for (final p in paths) {
        expect(declared, contains(p), reason: '«$p» مسار لا يشير إليه أي ثابت');
      }
    });

    test('لا مسار مُعلَن مرّتين', () {
      expect(paths.toSet(), hasLength(paths.length));
    });

    test('الراوتر يُبنى فعلًا بهذه المسارات', () {
      // إنشاء GoRouter يتحقّق من صحّة المسارات: مسار مشوّه يرمي هنا لا عند المستخدم.
      expect(appRouter.routerDelegate, isNotNull);
    });

    test('البداية على الباب', () {
      expect(paths.first, Routes.onboarding);
    });
  });
}
