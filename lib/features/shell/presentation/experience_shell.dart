import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../interactive_sandbox/presentation/sandbox_screen.dart';
import '../../plan/presentation/plan_screen.dart';
import '../../room_input/presentation/assistant_screen.dart';

/// **الهيكل الثلاثي** — التجارب الثلاث صفحاتٌ تُسحب أفقيًّا لا وجهاتٌ يُنتقل بينها.
///
/// الاتجاه يأتي مجّانًا: التمرير الأفقي يحترم `Directionality`، فالصفحة الأولى
/// (المساعد) تقع **يمينًا** في واجهة عربية بلا عكسٍ يدوي.
///
/// المسارات الثلاثة تبني هذا الهيكل نفسه بصفحةٍ مختلفة، وتتشارك مفتاح صفحةٍ
/// واحدًا في الراوتر — فيراها الـ`Navigator` صفحةً تُحدَّث لا ثلاثًا تُستبدل،
/// وتبقى المحادثة والخطة حيّتين عبر التنقّل.
class ExperienceShell extends StatefulWidget {
  const ExperienceShell({super.key, required this.page});

  /// ٠ المساعد · ١ غرفتي · ٢ المعاينة.
  final int page;

  /// ترتيب الصفحات = ترتيب التجارب في `Routes.experiences`.
  static const List<String> pagePaths = [
    Routes.assistant,
    Routes.room,
    Routes.preview,
  ];

  @override
  State<ExperienceShell> createState() => _ExperienceShellState();
}

class _ExperienceShellState extends State<ExperienceShell> {
  late final PageController _controller;

  /// **حارس القِمع.** `PageView` يبني الصفحة المجاورة أثناء السحب، ولو بُني
  /// `PlanScreen` هكذا لأُطلق `plan_seeded` قبل أن يصل المستخدم — أي يزيّف
  /// القِمع الذي نقيس به التفعيل (نفس ما منعه تسطيح المسارات في ADR-0002).
  ///
  /// فالصفحة تُركَّب حين **تستقرّ** لا حين تُلمَح: هنا تُسجَّل الصفحات المستقرّة،
  /// وما عداها يعرض هيكلًا محايدًا. `PlanScreen` وحده يراقب `planControllerProvider`،
  /// و`PlanController` وحده يُطلق الحدث — فلا تركيب، لا حدث.
  late final Set<int> _settled;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.page);
    _settled = {widget.page};
  }

  @override
  void didUpdateWidget(covariant ExperienceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // العنوان تغيّر من خارج السحب (رابط عميق أو انتقال تلقائي بعد بناء الخطة).
    if (widget.page != oldWidget.page &&
        _controller.hasClients &&
        _controller.page?.round() != widget.page) {
      _controller.animateToPage(
        widget.page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onSettled(ScrollEndNotification notification) {
    final page = _controller.hasClients ? _controller.page?.round() : null;
    if (page == null || page < 0 || page >= ExperienceShell.pagePaths.length) {
      return false;
    }
    if (!_settled.contains(page)) setState(() => _settled.add(page));
    // العنوان يتبع الصفحة المستقرّة، فيبقى الرابط العميق صادقًا بعد كل سحبة.
    if (page != widget.page) context.go(ExperienceShell.pagePaths[page]);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: _onSettled,
      child: PageView(
        controller: _controller,
        children: [
          _slot(0, const AssistantScreen()),
          _slot(1, const PlanScreen()),
          _slot(2, const SandboxScreen()),
        ],
      ),
    );
  }

  Widget _slot(int index, Widget page) =>
      _settled.contains(index) ? page : const _PageSkeleton();
}

/// ما يُرى في الصفحة التي لم تستقرّ بعد — إطارٌ محايد لدقيقةٍ بصرية واحدة.
/// ليس حالة تحميل: الصفحة لم تُطلب بعد، ولا يُنفَّذ فيها شيء.
class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
