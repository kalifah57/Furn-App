import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/features/consent/data/consent_store.dart';
import 'package:furn_app/features/consent/presentation/consent_controller.dart';

/// The consent gate is the difference between measuring the funnel and
/// collecting without permission. The default must be "not asked = no
/// collection", it must persist the user's choice, and the analytics sink must
/// actually see it.
void main() {
  group('the store', () {
    late Map<String, String> disk;
    setUp(() => disk = {});

    ConsentStore store({bool refuse = false}) => ConsentStore(
          read: (k) => disk[k],
          write: (k, v) {
            if (refuse) throw StateError('quota');
            disk[k] = v;
          },
        );

    test('unknown until asked — absence is never consent', () {
      expect(store().load(), isNull);
    });

    test('a grant persists across a fresh store over the same disk', () {
      store().save(granted: true);
      expect(store().load(), isTrue);
    });

    test('a denial persists too', () {
      store().save(granted: false);
      expect(store().load(), isFalse);
    });

    test('an unrecognised stored value reads as unknown, not as consent', () {
      disk[ConsentStore.key] = 'sure';
      expect(store().load(), isNull);
    });

    test('storage that refuses writes does not take the app down', () {
      expect(() => store(refuse: true).save(granted: true), returnsNormally);
    });
  });

  group('the gate feeding analytics', () {
    ProviderContainer make(Map<String, String> disk) {
      final c = ProviderContainer(overrides: [
        consentStoreProvider.overrideWithValue(
          ConsentStore(read: (k) => disk[k], write: (k, v) => disk[k] = v),
        ),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('before a choice, analytics consent is false — nothing collected', () {
      final c = make({});
      expect(c.read(consentControllerProvider), isNull);
      expect(c.read(analyticsConsentProvider), isFalse);
    });

    test('granting turns collection on and writes the choice', () {
      final disk = <String, String>{};
      final c = make(disk);
      c.read(consentControllerProvider.notifier).decide(granted: true);
      expect(c.read(analyticsConsentProvider), isTrue);
      expect(disk[ConsentStore.key], 'granted');
    });

    test('denying keeps collection off', () {
      final c = make({});
      c.read(consentControllerProvider.notifier).decide(granted: false);
      expect(c.read(analyticsConsentProvider), isFalse);
    });

    test('a prior granted choice is restored on the next launch', () {
      final c = make({ConsentStore.key: 'granted'});
      expect(c.read(consentControllerProvider), isTrue);
      expect(c.read(analyticsConsentProvider), isTrue);
    });
  });
}
