import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/room_analysis/presentation/analysis_screen.dart';
import '../../features/room_input/presentation/manual_input_screen.dart';
import '../../features/saved_projects/presentation/saved_projects_screen.dart';
import '../../features/shell/presentation/experience_shell.dart';

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
  static const assistantManual = '/assistant/manual'; // إدخال مفصّل بالحقول
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
/// التجارب الثلاث **صفحةٌ واحدة تُحدَّث، لا ثلاث تُستبدل.**
///
/// المفتاح مشترك عمدًا: `Page.canUpdate` تقارن النوع والمفتاح، فيرى الـ`Navigator`
/// المسارات الثلاثة صفحةً واحدة ويُحدّثها في مكانها بدل أن يهدم ويبني. أثره أن
/// حالة الهيكل — موضع السحب وسجلّ المحادثة — تبقى حيّة عبر التنقّل بالعنوان،
/// بينما يبقى كل مسارٍ رابطًا عميقًا صادقًا.
NoTransitionPage<void> _experiencePage(int page) => NoTransitionPage<void>(
      key: const ValueKey('experience-shell'),
      child: ExperienceShell(page: page),
    );

final List<GoRoute> appRoutes = [
  // الباب لم يعد وجهة: فتح التطبيق يهبط على المساعد مباشرة (بانر الموافقة فوقه).
  // يبقى مسارًا مُحوِّلًا كي لا يسقط رابطٌ قديم في صفحة خطأ.
  GoRoute(
    path: Routes.onboarding,
    redirect: (context, state) => Routes.assistant,
  ),

  // ١. المساعد — سطح محادثة واحد يفهم اللغة والصوت والصورة، ولا يتّخذ قرارًا.
  GoRoute(
    path: Routes.assistant,
    pageBuilder: (context, state) => _experiencePage(0),
  ),

  // ٢. غرفتي — القلب: هنا تُبنى الثقة، وكل قرار فيها من محرّك المجال.
  GoRoute(
    path: Routes.room,
    pageBuilder: (context, state) => _experiencePage(1),
  ),

  // ٣. المعاينة — الخطة موضوعة في مساحة الغرفة الحقيقية، بمقاسها.
  GoRoute(
    path: Routes.preview,
    pageBuilder: (context, state) => _experiencePage(2),
  ),

  // ما يُدفع **فوق** الهيكل: نوافذ عمل يعود منها المستخدم إلى مكانه، ولها زرّ
  // رجوع تلقائي لأنها تُكدَّس فوق صفحة حيّة لا تحلّ محلّها.
  GoRoute(
    path: Routes.assistantManual,
    builder: (context, state) => const ManualInputScreen(),
  ),
  GoRoute(
    path: Routes.assistantThinking,
    builder: (context, state) => const AnalysisScreen(),
  ),
  GoRoute(
    path: Routes.roomSaved,
    builder: (context, state) => const SavedProjectsScreen(),
  ),
];

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.onboarding,
  routes: appRoutes,
);
