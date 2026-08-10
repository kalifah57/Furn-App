import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/features/consent/data/consent_store.dart';
import 'package:furn_app/features/consent/presentation/consent_banner.dart';
import 'package:furn_app/features/consent/presentation/consent_controller.dart';

/// The first widget tests in the repo: they prove a screen actually renders,
/// and that the consent gate behaves on screen the way its logic tests say it
/// does — the banner is the visible half of "no collection without a choice".
void main() {
  ProviderContainer containerOver(Map<String, String> disk) => ProviderContainer(
        overrides: [
          consentStoreProvider.overrideWithValue(
            ConsentStore(read: (k) => disk[k], write: (k, v) => disk[k] = v),
          ),
        ],
      );

  Future<ProviderContainer> pumpBanner(
      WidgetTester tester, Map<String, String> disk) async {
    final container = containerOver(disk);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ConsentBanner())),
    ));
    return container;
  }

  testWidgets('shows until a choice is made, and collection is off meanwhile',
      (tester) async {
    final container = await pumpBanner(tester, {});

    expect(find.text('أوافق'), findsOneWidget);
    expect(find.text('لا، شكرًا'), findsOneWidget);
    expect(container.read(analyticsConsentProvider), isFalse);
  });

  testWidgets('granting dismisses the banner and turns collection on',
      (tester) async {
    final disk = <String, String>{};
    final container = await pumpBanner(tester, disk);

    await tester.tap(find.text('أوافق'));
    await tester.pump();

    expect(find.text('أوافق'), findsNothing); // banner gone
    expect(container.read(analyticsConsentProvider), isTrue);
    expect(disk[ConsentStore.key], 'granted');
  });

  testWidgets('declining also dismisses it, and keeps collection off',
      (tester) async {
    final disk = <String, String>{};
    final container = await pumpBanner(tester, disk);

    await tester.tap(find.text('لا، شكرًا'));
    await tester.pump();

    expect(find.text('لا، شكرًا'), findsNothing);
    expect(container.read(analyticsConsentProvider), isFalse);
    expect(disk[ConsentStore.key], 'denied');
  });

  testWidgets('a prior choice means the banner never appears', (tester) async {
    await pumpBanner(tester, {ConsentStore.key: 'granted'});
    expect(find.byType(Card), findsNothing);
    expect(find.text('أوافق'), findsNothing);
  });
}
