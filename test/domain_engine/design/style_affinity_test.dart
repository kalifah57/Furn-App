import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/design/design_language.dart';

/// اختبارات محور الستايل (docs/design/01 §1). القيم مُشتقّة من جدول السمات
/// ومحقَّقة بأوراكل مستقلّ قبل الكتابة (لا Flutter SDK في البيئة).
void main() {
  group('styleAffinity', () {
    test('KA-ST1 يتحقّق من السمات دون تلقين (§1.4)', () {
      // القاعدة المُعلنة سلفًا في knowledge_base.md:99:
      // style=modern ⇒ affinity(minimal)=high, affinity(classic)=low
      expect(styleAffinity(FurnitureStyle.modern, FurnitureStyle.minimal), 80);
      expect(styleRelation(FurnitureStyle.modern, FurnitureStyle.minimal),
          StyleRelation.high);
      expect(styleAffinity(FurnitureStyle.modern, FurnitureStyle.classic), 50);
      expect(styleRelation(FurnitureStyle.modern, FurnitureStyle.classic),
          StyleRelation.low);
    });

    test('متناظر · الذات=100 · ضمن 0..100 لكل الأزواج', () {
      for (final a in FurnitureStyle.values) {
        expect(styleAffinity(a, a), 100, reason: '$a مع نفسه');
        for (final b in FurnitureStyle.values) {
          expect(styleAffinity(a, b), styleAffinity(b, a),
              reason: 'تناظر $a/$b');
          expect(styleAffinity(a, b), inInclusiveRange(0, 100));
        }
      }
    });

    test('قيم المصفوفة المعروفة (§1.4)', () {
      expect(styleAffinity(FurnitureStyle.classic, FurnitureStyle.majlis), 80);
      expect(styleAffinity(FurnitureStyle.minimal, FurnitureStyle.boho), 45);
      expect(
          styleAffinity(FurnitureStyle.industrial, FurnitureStyle.majlis), 45);
    });

    test('explainAffinity حتميّ وغير فارغ', () {
      final s1 = explainAffinity(FurnitureStyle.minimal, FurnitureStyle.classic);
      final s2 = explainAffinity(FurnitureStyle.minimal, FurnitureStyle.classic);
      expect(s1, s2);
      expect(s1, isNotEmpty);
      expect(s1, contains('متنافران'));
    });
  });
}
