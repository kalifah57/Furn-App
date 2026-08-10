import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/parsing/plan_command.dart';
import 'package:furn_app/ai/parsing/plan_command_parser.dart';
import 'package:furn_app/shared/models/enums.dart';

/// المُحلِّل يترجم لغة المستخدم إلى نيّةٍ منظّمة — حتميًّا، دون أن يقرّر شيئًا.
/// هذه الاختبارات تثبّت المفردات والأسبقية، وتصون القاعدة: ما لم يُفهَم يُعلَن
/// مجهولًا لا يُخمَّن فعلًا لم يُطلَب.
void main() {
  const parser = PlanCommandParser();

  group('الميزانية', () {
    test('«اجعلها أوفر» → إزاحةٌ للأوفر', () {
      final cmd = parser.parse('اجعلها أوفر');
      expect(cmd, isA<NudgeBudgetCommand>());
      expect((cmd as NudgeBudgetCommand).direction, -1);
    });

    test('«زد الميزانية» → إزاحةٌ للأعلى', () {
      final cmd = parser.parse('زد الميزانية');
      expect(cmd, isA<NudgeBudgetCommand>());
      expect((cmd as NudgeBudgetCommand).direction, 1);
    });

    test('«ميزانيتي ٣٠٠٠» → تحديدٌ صريح', () {
      final cmd = parser.parse('ميزانيتي ٣٠٠٠');
      expect(cmd, isA<SetBudgetCommand>());
      expect((cmd as SetBudgetCommand).amountSar, 3000.0);
    });

    test('رقمٌ مجرّد يُقرأ ميزانية', () {
      expect((parser.parse('٥٠٠٠') as SetBudgetCommand).amountSar, 5000.0);
    });

    test('«3000 ريال» يُقرأ ميزانية', () {
      expect((parser.parse('3000 ريال') as SetBudgetCommand).amountSar, 3000.0);
    });

    test('«قلل الميزانية» → إزاحةٌ للأوفر لا تحديدٌ برقم', () {
      final cmd = parser.parse('قلل الميزانية');
      expect(cmd, isA<NudgeBudgetCommand>());
      expect((cmd as NudgeBudgetCommand).direction, -1);
    });
  });

  group('إضافة/إزالة فئة', () {
    test('«أضف طاولة» → إضافة طاولة', () {
      final cmd = parser.parse('أضف طاولة');
      expect(cmd, isA<AddCategoryCommand>());
      expect((cmd as AddCategoryCommand).category, RecommendationCategory.table);
    });

    test('«ابي سرير» → إضافة سرير', () {
      expect((parser.parse('ابي سرير') as AddCategoryCommand).category,
          RecommendationCategory.bed);
    });

    test('«أضف كنبة» → إضافة كنب/كرسي', () {
      expect((parser.parse('أضف كنبة') as AddCategoryCommand).category,
          RecommendationCategory.sofa);
    });

    test('«احذف الطاولة» → إزالة طاولة', () {
      final cmd = parser.parse('احذف الطاولة');
      expect(cmd, isA<RemoveCategoryCommand>());
      expect(
          (cmd as RemoveCategoryCommand).category, RecommendationCategory.table);
    });

    test('الإضافة تسبق الميزانية: السعر في «أضف طاولة بـ ٥٠٠» يُتجاهل', () {
      final cmd = parser.parse('أضف طاولة بـ ٥٠٠');
      expect(cmd, isA<AddCategoryCommand>());
      expect((cmd as AddCategoryCommand).category, RecommendationCategory.table);
    });
  });

  group('الاعتماد والمجهول الصادق', () {
    test('«جاهز» → اعتماد', () {
      expect(parser.parse('جاهز'), isA<FinalizeCommand>());
    });

    test('«اعتمد الخطة» → اعتماد', () {
      expect(parser.parse('اعتمد الخطة'), isA<FinalizeCommand>());
    });

    test('كلامٌ لا أمرَ فيه يُعلَن مجهولًا لا يُخمَّن', () {
      expect(parser.parse('شكرا يا مساعد'), isA<UnknownCommand>());
    });

    test('الفارغ مجهول', () {
      expect(parser.parse('   '), isA<UnknownCommand>());
    });

    test('مقاسات الغرفة «٤×٣٫٧» لا تُقرأ ميزانية', () {
      // بلا كلمة ميزانية وليست رقمًا مجرّدًا — فلا نحوّل أبعاد الغرفة إلى مبلغ.
      expect(parser.parse('٤×٣٫٧'), isA<UnknownCommand>());
    });

    test('الفهم حتمي: نفس المدخل نفس النيّة', () {
      expect(parser.parse('اجعلها أوفر').intent,
          parser.parse('اجعلها أوفر').intent);
    });
  });
}
