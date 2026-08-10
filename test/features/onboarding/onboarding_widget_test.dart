import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/constants/app_strings.dart';
import 'package:furn_app/features/consent/data/consent_store.dart';
import 'package:furn_app/features/consent/presentation/consent_controller.dart';
import 'package:furn_app/features/onboarding/presentation/onboarding_screen.dart';

/// A smoke test — the point is simply that the door screen builds and paints
/// without throwing, which nothing verified before. It renders the entry CTA
/// and, on a first run (no consent choice), the consent gate.
void main() {
  testWidgets('the onboarding screen renders its entry CTA and consent gate',
      (tester) async {
    // التطبيق ويب بنافذة كبيرة؛ نمنح الاختبار سطحًا مماثلًا كي لا يفيض العمود
    // الطويل في نافذة 600px الافتراضية (فيضٌ بيئيّ لا خطأ حقيقي).
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final disk = <String, String>{}; // fresh: consent not yet chosen
    final container = ProviderContainer(overrides: [
      consentStoreProvider.overrideWithValue(
        ConsentStore(read: (k) => disk[k], write: (k, v) => disk[k] = v),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await tester.pump();

    expect(find.text(AppStrings.onboardingStart), findsOneWidget);
    expect(find.text(AppStrings.appTitle), findsOneWidget);
    expect(find.text('أوافق'), findsOneWidget); // consent gate on first run
  });
}
