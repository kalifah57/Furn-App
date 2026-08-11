import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/features/room_input/presentation/assistant_chat.dart';
import 'package:furn_app/features/room_input/presentation/assistant_screen.dart';

import '../../support/arabic_app.dart';

/// المساعد صار سطح محادثة واحدًا (X0): تحية، فقاعات، ومؤشّر كتابة بدل شاشة
/// تفكير مستقلّة. المنطق لم يتغيّر — النصّ ما يزال الطريق الأساسي، والصوت
/// والصورة زرّان في شريط الإدخال، ولا يُبنى شيء من وصفٍ فارغ.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      child: arabicApp(const AssistantScreen()),
    ));
  }

  Finder sendButton() => find.widgetWithIcon(IconButton, Icons.send);

  testWidgets('يفتح على تحيةٍ وشريط إدخال فيه كتابة وصوت وصورة',
      (tester) async {
    await pump(tester);

    expect(find.text(AssistantChat.greeting), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.text('إدخال مفصّل بالحقول'), findsOneWidget);
  });

  testWidgets('لا يُبنى شيء من وصفٍ فارغ', (tester) async {
    await pump(tester);
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'غرفة نوم 4×3.7');
    await tester.pump();
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    // مسافات ليست وصفًا.
    expect(tester.widget<IconButton>(sendButton()).onPressed, isNull);
  });

  testWidgets('ما يدخل السجلّ يظهر فقاعةً، والتحية تبقى', (tester) async {
    // نقود السجلّ مباشرة بدل ضغط الإرسال: الإرسال يشعل مسار التحليل الوهمي
    // (٦٠٠ms + انتقال تلقائي)، والمقصود هنا التصيير لا الرحلة — الرحلة في X2.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: arabicApp(const AssistantScreen()),
    ));

    container.read(assistantChatProvider.notifier).user('غرفة نوم 4×3.7');
    await tester.pump();

    expect(find.text('غرفة نوم 4×3.7'), findsOneWidget);
    expect(find.text(AssistantChat.greeting), findsOneWidget);
  });

  testWidgets('المحادثة تُصيَّر من اليمين، كما يعمل التطبيق', (tester) async {
    await pump(tester);
    expect(Directionality.of(tester.element(find.byType(TextField))),
        TextDirection.rtl);
  });
}
