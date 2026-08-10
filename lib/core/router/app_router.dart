import 'package:go_router/go_router.dart';

import '../../features/interactive_sandbox/presentation/sandbox_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/room_analysis/presentation/analysis_screen.dart';
import '../../features/room_input/presentation/image_input_screen.dart';
import '../../features/room_input/presentation/input_method_screen.dart';
import '../../features/room_input/presentation/manual_input_screen.dart';
import '../../features/room_input/presentation/voice_input_screen.dart';
import '../../features/saved_projects/presentation/saved_projects_screen.dart';

/// مسارات التطبيق (ADR-0001 §3 — GoRouter).
///
/// المنتج **ثلاث تجارب لا أكثر**، والعنوان يقولها صراحةً. أي شاشة جديدة يجب أن
/// تجد لنفسها موضعًا تحت واحدة منها؛ وإن لم تجد، فهي على الأرجح خارج الـ MVP:
///
/// * **`/assistant` — المساعد**: المدخل الوحيد (نصّ/صوت/صور) حتى أول مسوّدة خطة.
/// * **`/room` — غرفتي**: القلب. الخطة والأثاث والميزانية والثقة والمقارنة
///   والتعديل. المستخدم يقضي وقته هنا ونادرًا ما يغادرها.
/// * **`/preview` — المعاينة**: المخطّط ثنائي الأبعاد (وصور الغرف المولّدة لاحقًا).
///
/// `/` ليست تجربة رابعة بل الباب الذي يفتح على المساعد. والواقع المعزّز ليس
/// مسارًا: شيفرته باقية في `features/ar/` لكنه خارج سطح الـ MVP، فيما عدا زرّ
/// «شاهدها في غرفتك» على قطعة لها نموذج جاهز — وهو نافذة يفتحها المتصفّح، لا شاشة.
abstract class Routes {
  /// الباب.
  static const onboarding = '/';

  // ---- ١. المساعد --------------------------------------------------------
  static const assistant = '/assistant';
  static const assistantManual = '/assistant/manual';
  static const assistantVoice = '/assistant/voice';
  static const assistantPhoto = '/assistant/photo';
  static const assistantThinking = '/assistant/thinking';

  // ---- ٢. غرفتي ----------------------------------------------------------
  static const room = '/room';
  static const roomSaved = '/room/saved';

  // ---- ٣. المعاينة -------------------------------------------------------
  static const preview = '/preview';

  /// جذور التجارب الثلاث — يحرسها `test/features/router_test.dart` كي لا تصير أربعًا.
  static const experiences = [assistant, room, preview];
}

/// المسارات مُعلَنة **مسطّحة** رغم أن نصوصها هرمية، وهذا مقصود لا سهو:
///
/// التعشيش في GoRouter يبني الأب مع الابن، فدخول `/room/saved` كان سيُنشئ
/// `PlanScreen` تحته ويُطلق `plan_seeded` **قبل** أن يصل المستخدم إلى الخطة — أي
/// يزيّف القِمع الذي نقيس به التفعيل. الهرمية هنا في العنوان لا في المكدّس؛
/// المكدّس يبقى كما كان تمامًا.
final List<GoRoute> appRoutes = [
  GoRoute(
    path: Routes.onboarding,
    builder: (context, state) => const OnboardingScreen(),
  ),

  // ١. المساعد — يفهم اللغة والصور ويستخرج المعلومات، ولا يتّخذ قرارًا.
  GoRoute(
    path: Routes.assistant,
    builder: (context, state) => const InputMethodScreen(),
  ),
  GoRoute(
    path: Routes.assistantManual,
    builder: (context, state) => const ManualInputScreen(),
  ),
  GoRoute(
    path: Routes.assistantVoice,
    builder: (context, state) => const VoiceInputScreen(),
  ),
  GoRoute(
    path: Routes.assistantPhoto,
    builder: (context, state) => const ImageInputScreen(),
  ),
  GoRoute(
    path: Routes.assistantThinking,
    builder: (context, state) => const AnalysisScreen(),
  ),

  // ٢. غرفتي — القلب: هنا تُبنى الثقة، وكل قرار فيها من محرّك المجال.
  GoRoute(
    path: Routes.room,
    builder: (context, state) => const PlanScreen(),
  ),
  GoRoute(
    path: Routes.roomSaved,
    builder: (context, state) => const SavedProjectsScreen(),
  ),

  // ٣. المعاينة — الخطة موضوعة في مساحة الغرفة الحقيقية، بمقاسها.
  GoRoute(
    path: Routes.preview,
    builder: (context, state) => const SandboxScreen(),
  ),
];

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.onboarding,
  routes: appRoutes,
);
