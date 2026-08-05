import 'package:go_router/go_router.dart';

import '../../features/ar/presentation/ar_visualization_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/recommendations/presentation/recommendations_screen.dart';
import '../../features/room_analysis/presentation/analysis_screen.dart';
import '../../features/room_input/presentation/image_input_screen.dart';
import '../../features/room_input/presentation/input_method_screen.dart';
import '../../features/room_input/presentation/manual_input_screen.dart';
import '../../features/room_input/presentation/voice_input_screen.dart';
import '../../features/saved_projects/presentation/saved_projects_screen.dart';

/// مسارات التطبيق (ADR-0001 §3 — GoRouter).
abstract class Routes {
  static const onboarding = '/';
  static const inputMethod = '/input';
  static const manualInput = '/input/manual';
  static const voiceInput = '/input/voice';
  static const imageInput = '/input/image';
  static const analysis = '/analysis';
  static const recommendations = '/recommendations';
  static const saved = '/saved';
  static const plan = '/plan';
  static const ar = '/ar';
}

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.onboarding,
  routes: [
    GoRoute(
      path: Routes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: Routes.inputMethod,
      builder: (context, state) => const InputMethodScreen(),
    ),
    GoRoute(
      path: Routes.manualInput,
      builder: (context, state) => const ManualInputScreen(),
    ),
    GoRoute(
      path: Routes.voiceInput,
      builder: (context, state) => const VoiceInputScreen(),
    ),
    GoRoute(
      path: Routes.imageInput,
      builder: (context, state) => const ImageInputScreen(),
    ),
    GoRoute(
      path: Routes.analysis,
      builder: (context, state) => const AnalysisScreen(),
    ),
    GoRoute(
      path: Routes.recommendations,
      builder: (context, state) => const RecommendationsScreen(),
    ),
    GoRoute(
      path: Routes.saved,
      builder: (context, state) => const SavedProjectsScreen(),
    ),
    GoRoute(
      path: Routes.plan,
      builder: (context, state) => const PlanScreen(),
    ),
    GoRoute(
      path: Routes.ar,
      builder: (context, state) => const ArVisualizationScreen(),
    ),
  ],
);
