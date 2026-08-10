import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/features/room_input/presentation/assistant_screen.dart';

/// The single intake screen that replaced the method-picker and the separate
/// voice/image screens. Smoke + the one behaviour that matters: you cannot
/// build a plan from nothing, so the primary action stays disabled until the
/// user has described their room.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AssistantScreen()),
    ));
  }

  /// `find.byType` — which `widgetWithText` delegates to — matches on exact
  /// `runtimeType`, and `FilledButton.icon` builds the private
  /// `_FilledButtonWithIcon` subclass. Matching by type therefore finds nothing
  /// and the lookup throws "Bad state: No element" rather than failing on the
  /// assertion. Match on `is FilledButton` so the icon variant counts too.
  ButtonStyleButton buildButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text('ابنِ خطتي'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ));

  testWidgets('renders the intake with text, voice, image and detailed paths',
      (tester) async {
    await pump(tester);
    expect(find.text('صف غرفتك وميزانيتك'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('بالصوت'), findsOneWidget);
    expect(find.text('بصورة'), findsOneWidget);
    expect(find.text('إدخال مفصّل بالحقول'), findsOneWidget);
  });

  testWidgets('the build-plan action is disabled until the room is described',
      (tester) async {
    await pump(tester);
    expect(buildButton(tester).onPressed, isNull); // nothing typed yet

    await tester.enterText(find.byType(TextField), 'غرفة نوم ٤×٣٫٧');
    await tester.pump();
    expect(buildButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(buildButton(tester).onPressed, isNull); // whitespace is not a description
  });
}
