import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/design/design_language.dart';

/// اختبارات محور اللون (docs/design/01 §2). الحرارة/الإضاءة/التشبّع محسوبة من
/// CIELAB المضمَّن ومحقَّقة بأوراكل مستقلّ (docs/design/06 §هـ).
void main() {
  ColorToken t(String id) => kColorTokens[id]!;

  group('حرارة اللون من b* (CIELAB)', () {
    test('الرماديّ ينفصل دافئًا/باردًا', () {
      expect(t('gray_warm').temperature, Temperature.warm);
      expect(t('gray_cool').temperature, Temperature.cool);
    });

    test('بيج دافئ · أزرق بارد · أبيض محايد', () {
      expect(t('beige').temperature, Temperature.warm);
      expect(t('blue').temperature, Temperature.cool);
      expect(t('white').temperature, Temperature.neutral);
    });

    test('مثال المؤسّس: البنّي الدافئ يتعارض مع الرمادي البارد (C2)', () {
      expect(
          temperaturesClash(
              t('brown').temperature, t('gray_cool').temperature),
          isTrue);
      // الإصلاح إلى رمادي دافئ يُزيل التعارض.
      expect(
          temperaturesClash(
              t('brown').temperature, t('gray_warm').temperature),
          isFalse);
    });
  });

  group('شرائح الإضاءة والتشبّع', () {
    test('الإضاءة 0..4', () {
      expect(t('white').lightnessBand, 4);
      expect(t('black').lightnessBand, 0);
      expect(t('gray_cool').lightnessBand, 2);
    });

    test('التشبّع 0..4', () {
      expect(t('white').chromaBand, 0);
      expect(t('red').chromaBand, 4);
    });
  });

  group('خرط وسوم الكتالوج', () {
    test('الواضح يُحلّ، والغامض يُؤجَّل بـnull لا بتخمين', () {
      expect(colorTokenForTag('white')?.id, 'white');
      expect(colorTokenForTag('brown')?.id, 'brown');
      expect(colorTokenForTag('BLUE')?.id, 'blue'); // غير حسّاس للحالة
      expect(colorTokenForTag('gray'), isNull); // يحتاج حرارة السطح
      expect(colorTokenForTag('walnut'), isNull); // نغمة خشب لا لون
    });
  });
}
