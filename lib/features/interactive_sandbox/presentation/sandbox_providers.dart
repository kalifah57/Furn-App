import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain_engine/spatial/furniture_package.dart';
import '../../../domain_engine/spatial/placement_solver.dart';
import '../../../domain_engine/spatial/replacement_finder.dart';
import '../../../shared/models/models.dart';
import '../../plan/presentation/plan_controller.dart' show planProjectProvider;
import '../domain/image_inpainting_service.dart';
import '../domain/room_scanner_service.dart';

/// حقن تبعيات الصندوق التفاعلي (ADR-0001 §4). محرّكات المجال بلا حالة، لذا
/// `const` — والخدمات الوهمية تُستبدل بالحقيقية عبر `override` دون لمس الشاشة.

// ---- خدمات المسح والتنظيف (mock-first) ----
final roomScannerServiceProvider =
    Provider<RoomScannerService>((ref) => const MockRoomScannerService());

final imageInpaintingServiceProvider =
    Provider<ImageInpaintingService>((ref) => const MockImageInpaintingService());

// ---- محرّكات المجال (نقية · حتمية) ----
final packageComposerProvider =
    Provider<PackageComposer>((ref) => const PackageComposer());

final placementSolverProvider =
    Provider<PlacementSolver>((ref) => const PlacementSolver());

final replacementFinderProvider =
    Provider<ReplacementFinder>((ref) => const ReplacementFinder());

/// المشروع الذي يقرأ منه الصندوق الميزانية والنمط ونوع الغرفة — نفس مصدر شاشة
/// الخطة، فلا يفترق الصندوق عن بقية التطبيق.
final sandboxBriefProvider =
    Provider<FurnishingProject>((ref) => ref.watch(planProjectProvider));
