import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/domain_engine/spatial/ar_spatial_engine.dart';
import 'package:furn_app/features/ar/presentation/ar_providers.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart'
    show planProjectProvider;
import 'package:furn_app/shared/models/models.dart';
import 'package:furn_app/shared/services/catalog_repository.dart';

/// The AR gate must measure against the user's own room. A hardcoded default
/// here would silently answer "does it fit?" about somebody else's room, which
/// is the one thing this screen exists to get right.
void main() {
  const catalog = <CatalogProduct>[
    CatalogProduct(
      productId: 'sofa_big',
      title: 'كنب كبير',
      category: RecommendationCategory.sofa,
      widthCm: 260,
      depthCm: 100,
      heightCm: 85,
      modelGlbUrl: 'models/glb/sofa_big.glb',
      arReady: true,
    ),
    CatalogProduct(
      productId: 'stool_small',
      title: 'كرسي صغير',
      category: RecommendationCategory.sofa,
      widthCm: 45,
      depthCm: 45,
      heightCm: 45,
      modelGlbUrl: 'models/glb/stool_small.glb',
      arReady: true,
    ),
  ];

  FurnishingProject projectWith(Room room) =>
      FurnishingProject(projectId: 'p', room: room, budget: const Budget(maxTotal: 5000));

  ProviderContainer containerFor(Room room) {
    final c = ProviderContainer(overrides: [
      catalogRepositoryProvider
          .overrideWithValue(const InMemoryCatalogRepository(catalog)),
      planProjectProvider.overrideWithValue(projectWith(room)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('arRoomProvider follows the project room, not a fixed default', () {
    final c = containerFor(
        const Room(widthM: 2.5, lengthM: 3, roomType: RoomType.bedroom));
    expect(c.read(arRoomProvider).widthM, 2.5);
    expect(c.read(arRoomProvider).lengthM, 3);
  });

  test('a different project room changes what the gate admits', () async {
    // 260cm sofa fits a 4m wall but not a 2m one — the verdict must track the
    // room the user actually measured.
    final big = containerFor(
        const Room(widthM: 4, lengthM: 4, roomType: RoomType.livingRoom));
    final small = containerFor(
        const Room(widthM: 2, lengthM: 2, roomType: RoomType.livingRoom));

    final inBig = await big.read(arFitResultsProvider.future);
    final inSmall = await small.read(arFitResultsProvider.future);

    expect(inBig.firstWhere((r) => r.product.productId == 'sofa_big').verdict,
        ArFitVerdict.fits);
    expect(inSmall.firstWhere((r) => r.product.productId == 'sofa_big').verdict,
        ArFitVerdict.tooLarge);
    // The small stool clears both rooms.
    expect(inSmall.firstWhere((r) => r.product.productId == 'stool_small').canPlace,
        isTrue);
  });

  test('placing furniture shrinks what the gate still admits', () async {
    final c = containerFor(
        const Room(widthM: 2, lengthM: 2, roomType: RoomType.livingRoom));
    final before = await c.read(arFitResultsProvider.future);
    expect(before.where((r) => r.canPlace).map((r) => r.product.productId),
        contains('stool_small'));

    // 2x2m -> 40000 cm2 floor, 26000 placeable at 65%. Thirteen stools at
    // 2025 cm2 each overrun it, so the next one has nowhere to go.
    c.read(arPlacedProvider.notifier).state = List.filled(13, catalog[1]);
    final after = await c.read(arFitResultsProvider.future);
    expect(after.firstWhere((r) => r.product.productId == 'stool_small').verdict,
        ArFitVerdict.noRemainingSpace);
  });
}
