import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/constants/app_strings.dart';
import 'package:furn_app/features/room_input/presentation/manual_input_screen.dart';

import '../../support/arabic_app.dart';

/// An empty form used to pass straight through with a room of 0 × 0 metres and
/// no essential items, so the user crossed two screens only to be asked, by the
/// engine, for what had been on the screen in front of them. The validation
/// lives at the field now.
void main() {
  Future<void> pump(WidgetTester tester) async {
    // النموذج أطول من سطح الاختبار الافتراضي؛ نمنحه سطحًا يسع زرّ الإرسال.
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      child: arabicApp(const ManualInputScreen()),
    ));
  }

  Finder submit() =>
      find.widgetWithText(FilledButton, AppStrings.analyzeRequest);
  const dimsError = 'أدخل مقاس الغرفة بالمتر — رقمًا أكبر من صفر.';
  const itemsError = 'اختر قطعةً أساسية واحدة على الأقل.';

  testWidgets('an empty form is refused at the field, not two screens later',
      (tester) async {
    await pump(tester);

    expect(find.text(dimsError), findsNothing); // nothing shouted before trying
    expect(find.text(itemsError), findsNothing);

    await tester.tap(submit());
    await tester.pump();

    expect(find.text(dimsError), findsOneWidget);
    expect(find.text(itemsError), findsOneWidget);
  });

  testWidgets('each answer clears its own error and no other', (tester) async {
    await pump(tester);
    await tester.tap(submit());
    await tester.pump();

    // ترتيب الحقول في الشجرة: العرض ثم الطول ثم الميزانية.
    await tester.enterText(find.byType(TextField).at(0), '4');
    await tester.enterText(find.byType(TextField).at(1), '3.5');
    await tester.tap(submit());
    await tester.pump();

    expect(find.text(dimsError), findsNothing); // answered
    expect(find.text(itemsError), findsOneWidget); // still missing, still said
  });

  testWidgets('the form lays out right-to-left, the way the app runs',
      (tester) async {
    await pump(tester);
    expect(Directionality.of(tester.element(find.byType(TextField).first)),
        TextDirection.rtl);
  });
}
