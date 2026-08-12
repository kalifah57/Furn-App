import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/router/app_router.dart';
import '../../../domain_engine/plan/plan.dart';
import '../../../domain_engine/plan/unmet_need.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_views.dart';
import '../../ar/ar_button.dart';
import 'assistant_sheet.dart';
import 'plan_controller.dart';

/// رسالةُ خطأ صادقة: إن حملت الطبقة السفلى سببًا معروفًا (`Failure`) عُرِض كما هو،
/// وإلّا عبارةٌ محايدة لا تدّعي سببًا لم يقع (لا «تحقّق من اتصالك» لعطبٍ ليس شبكة).
String _errorMessage(Object error, {required String fallback}) =>
    error is Failure ? error.message : fallback;

/// شاشة الخطة — قلب التطبيق (product_thesis.md): «الخطة» التي يشكّلها المستخدم
/// حتى يثق بها. تعرض حلقة الثقة: ثبّت/ارفض/بدّل/اضبط الميزانية → إعادة توازن فورية
/// مع ضمانات وتفسير ومؤشّر ثقة، ثم «هذه هي خطتي».
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('خطتي'),
        actions: [
          // المساعد يعيش هنا كورقة داخل الغرفة، لا كوجهة يُعاد إليها: يخاطبه
          // المستخدم بلغته فيعدّل خطته دون مغادرتها. يظهر فقط بعد جهوز المحرّك.
          async.maybeWhen(
            data: (controller) => IconButton(
              tooltip: 'المساعد',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => showAssistantSheet(context, controller),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          // المعاينة: الخطة نفسها موضوعة في مساحة الغرفة بمقاسها الحقيقي — يرى
          // المستخدم ما يدخل فعلًا وما لا يدخل قبل أن يدفع.
          IconButton(
            tooltip: 'المعاينة',
            icon: const Icon(Icons.grid_view_outlined),
            onPressed: () => context.push(Routes.preview),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(message: 'جاري بناء خطتك…'),
        // رسالة الخطأ تنقل سبب الطبقة السفلى الحقيقي ولا تخمّن: «تحقّق من اتصالك»
        // كانت تُقال حتى حين كان السبب أصلًا مفقودًا لا انقطاع شبكة (حادثة X9).
        error: (e, _) => ErrorView(
          message: _errorMessage(e, fallback: 'تعذّر تحميل خطتك. أعد المحاولة.'),
          onRetry: () => ref.invalidate(planControllerProvider),
        ),
        data: (controller) => _PlanView(controller: controller),
      ),
    );
  }
}

class _PlanView extends StatefulWidget {
  const _PlanView({required this.controller});
  final PlanController controller;

  @override
  State<_PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<_PlanView> {
  double? _budgetDraft;

  PlanController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.logAbandonedIfUnfinished();
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = c.plan;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              _confidenceCard(context, plan),
              if (plan.confidenceGaps.isNotEmpty) ...[
                const SizedBox(height: 8),
                _nextSteps(context, plan),
              ],
              const SizedBox(height: 8),
              _versionsBar(context),
              const SizedBox(height: 12),
              _assurances(context, plan.assurances),
              _changeBanner(context),
              const SizedBox(height: 12),
              _budgetCard(context, plan),
              if (plan.missingCategories.isNotEmpty) ...[
                const SizedBox(height: 12),
                _completeness(context, plan),
              ],
              if (plan.hasUnmetNeeds) ...[
                const SizedBox(height: 12),
                UnmetNeedsSection(plan: plan),
              ],
              const SizedBox(height: 12),
              _arPreviewCard(context),
              const SizedBox(height: 20),
              // عنوانٌ فوق فراغ أسوأ من فراغ معلن: حين لا قطع، يحلّ محلّ العنوان
              // سطرٌ يقول ما الذي يملأ الخطة.
              if (plan.items.isEmpty)
                _emptyPlan(context)
              else ...[
                Text('قطع خطتك',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final item in plan.items) _itemCard(context, item),
              ],
            ],
          ),
        ),
        _bottomBar(context, plan),
      ],
    );
  }

  /// خطة بلا قطع — تحدث حين تكون الميزانية دون أرخص ما يناسب الغرفة، أو حين
  /// يرفض المستخدم كل ما اقتُرح. الحالة مشروعة، فتُقال ويُقال معها المخرج.
  Widget _emptyPlan(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('لا قطع في خطتك بعد.',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('ارفع سقف ميزانيتك من الشريط أعلاه، أو اطلب قطعة من المساعد.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ---- confidence ---------------------------------------------------------

  Widget _confidenceCard(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    final color = _confColor(plan.confidence, theme.colorScheme);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      value: plan.confidence / 100,
                      strokeWidth: 8,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  Text('${plan.confidence}%',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ثقتك في الخطة',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    plan.confidence >= 80
                        ? 'خطة متكاملة — أنت قريب من القرار.'
                        : 'كل ما تعدّله يقرّبك أكثر من خطة تطمئن لها.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'من أين تأتي الثقة؟',
              onPressed: () => _openConfidenceBreakdown(context, plan),
            ),
          ],
        ),
      ),
    );
  }

  Color _confColor(int v, ColorScheme s) =>
      v >= 80 ? Colors.green : (v >= 50 ? Colors.orange : s.error);

  /// «ماذا تفعل لترفع ثقتك» — الفجوات القابلة للتنفيذ من المحرّك، الأكبر أثرًا
  /// أوّلًا، كلٌّ بنقاطها الحقيقية. تجعل العدّاد قابلًا للفعل لا رقمًا يُحدَّق فيه.
  Widget _nextSteps(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.trending_up, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('لترفع ثقتك',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          for (final g in plan.confidenceGaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('+${g.points}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.label,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        for (final a in g.actions)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('• $a',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- assurances ---------------------------------------------------------

  Widget _assurances(BuildContext context, Assurances a) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _badge(context, a.essentialsComplete, 'مكتملة',
            'كل القطع الأساسية التي طلبتها موجودة في خطتك.'),
        _badge(context, a.withinBudget, 'ضمن الميزانية',
            'إجمالي الخطة ضمن الميزانية التي حدّدتها.'),
        _badge(context, a.fitsRoom, 'تناسب الغرفة',
            'كل قطعة تدخل فعليًا في أبعاد غرفتك.'),
        _badge(context, a.allAvailable, 'متوفّرة',
            'كل القطع متوفّرة للشراء الآن.'),
      ],
    );
  }

  Widget _badge(BuildContext context, bool ok, String label, String explain) {
    final color = ok ? Colors.green : Colors.orange;
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(explain))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }

  // ---- what changed -------------------------------------------------------

  Widget _changeBanner(BuildContext context) {
    final msg = _changeMessage(c.lastChange);
    if (msg == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: theme.textTheme.bodyMedium)),
        ]),
      ),
    );
  }

  String? _changeMessage(PlanDiff? d) {
    if (d == null || d.isEmpty) return null;
    final parts = <String>[];
    if (d.added.isNotEmpty) {
      parts.add('أضفنا ${d.added.map((e) => e.name).join('، ')}');
    }
    if (d.removed.isNotEmpty) {
      parts.add('أزلنا ${d.removed.map((e) => e.name).join('، ')}');
    }
    if (d.deltaTotal > 0) {
      parts.add('زادت التكلفة ${formatSar(d.deltaTotal)}');
    } else if (d.deltaTotal < 0) {
      parts.add('وفّرت ${formatSar(-d.deltaTotal)}');
    }
    return parts.join(' · ');
  }

  // ---- budget -------------------------------------------------------------

  Widget _budgetCard(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    final budget = c.project.budget.maxTotal;
    final double value =
        (_budgetDraft ?? budget).clamp(500.0, 10000.0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // مرنٌ كي لا يفيض الصفّ مع خطٍّ بديل أعرض (حادثة X9): العنوان
              // يتقلّص بنقاط، والقيمة تبقى كاملة.
              Flexible(
                child: Text('الميزانية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              Text(formatSar(value),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
            ]),
            Slider(
              min: 500,
              max: 10000,
              divisions: 19,
              value: value.toDouble(),
              label: formatSar(value),
              onChanged: (v) => setState(() => _budgetDraft = v),
              onChangeEnd: (v) {
                _budgetDraft = null;
                c.setBudget(v);
              },
            ),
            Text('إجمالي الخطة الآن: ${formatSar(plan.total)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: plan.assurances.withinBudget
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }

  // ---- completeness -------------------------------------------------------

  Widget _completeness(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ينقص خطتك:',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final cat in plan.missingCategories)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(cat.arabicLabel),
                    // فئةٌ بلا بديل في الكتالوج كانت تبتلع النقرة. الحدّ يُقال.
                    onPressed: () {
                      if (c.addCheapestOf(cat)) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('لا نوفّر ${cat.arabicLabel} حاليًا.')));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- item ---------------------------------------------------------------

  /// بطاقة تجربة الواقع المعزّز — يفتح المستخدم الكاميرا ويرى قطعة بمقاسها
  /// الحقيقي في غرفته الآن (نموذج تجريبي)، تمهيدًا لنماذج المنتجات الفعلية.
  Widget _arPreviewCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.view_in_ar, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              // مرنٌ كي لا يفيض العنوان مع خطٍّ بديل أعرض (حادثة X9).
              Expanded(
                child: Text('شاهدها في غرفتك',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'طاولة قهوة حقيقية بمقاسها الفعلي (١١٠×٦٠×٤٥ سم). افتح الكاميرا '
              'وضعها على الأرض، لُفّ حولها، وتأكّد أنها تناسب مكانك — دون تثبيت '
              'أي تطبيق.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // FittedBox يقلّص الزرّ ليتّسع حين يكون خطٌّ بديل أعرض من المتوقّع،
            // فلا تفيض عنونته الطويلة (حادثة X9) — بلا لمس مكوّن مسار آخر.
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ArDemoButton(label: 'شاهد الطاولة في غرفتك'),
              ),
            ),
            const SizedBox(height: 6),
            Text('نموذج ثلاثي الأبعاد حقيقي مُولّد بمقاسه الفعلي — نُلحق نماذج '
                'بقية المنتجات تباعًا.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(BuildContext context, PlanItem planItem) {
    final theme = Theme.of(context);
    final item = planItem.item;
    final id = item.productId;
    final product = c.productById(id);
    return Card(
      child: Padding(
        // اتجاهية لا فيزيائية: `fromLTRB` كانت تجعل البداية ٨ والنهاية ١٦ في
        // RTL — معكوسة عن القصد، ولا اختبار يراها لأن الاختبارات كانت LTR.
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(formatSar(item.price),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Chip(
                label: Text(item.category.arabicLabel),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              if (planItem.isPinned) ...[
                const SizedBox(width: 8),
                Text('مثبّتة',
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ]),
            if (item.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(item.reason,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const Divider(height: 16),
            Row(children: [
              TextButton.icon(
                onPressed: id == null
                    ? null
                    : () =>
                        planItem.isPinned ? c.unpin(id) : c.pin(id),
                icon: Icon(
                    planItem.isPinned ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: planItem.isPinned ? Colors.red : null),
                label: Text(planItem.isPinned ? 'مثبّتة' : 'ثبّت'),
              ),
              TextButton.icon(
                onPressed: id == null ? null : () => _openAlternatives(item),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('بدّل'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'أزل',
                onPressed: id == null ? null : () => c.reject(id),
                icon: const Icon(Icons.close),
              ),
            ]),
            if (product?.hasArModel ?? false) ...[
              const Divider(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ArButton(product: product),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// «بدّل» كقرار لا قائمة: القطعة الحالية + حتى ٣ بدائل أعلى نقاطًا ضمن الميزانية
  /// والمقاس، كلٌّ بإيجابياته وسلبياته مقابل الحالية. الاختيار يُحدّث الخطة فورًا
  /// دون مغادرة «غرفتي».
  void _openAlternatives(RecommendedItem item) {
    final id = item.productId;
    if (id == null) return;
    final current = c.productById(id);
    final alts = c.betterAlternatives(item.category, id);
    c.logOptionsOpened(item.category, alts.length);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('بدائل ${item.category.arabicLabel}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'أعلى الخيارات نقاطًا ضمن ميزانيتك ومقاس غرفتك — اختر ما تثق به.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              if (current != null) ...[
                _sheetLabel(theme, 'الحالي'),
                _compareCard(theme, current, isCurrent: true),
                const SizedBox(height: 16),
              ],
              if (alts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'لا يوجد بديل أفضل يدخل في غرفتك ضمن ميزانيتك المتبقّية.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...[
                _sheetLabel(theme, 'بدائل أفضل'),
                for (final o in alts)
                  _compareCard(theme, o.product,
                      pros: o.pros,
                      cons: o.cons,
                      priceDelta: current == null
                          ? null
                          : o.product.price - current.price,
                      onSelect: () {
                        Navigator.of(sheetContext).pop();
                        c.swap(id, o.product.productId);
                      }),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sheetLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );

  /// بطاقة مقارنة موحّدة: القطعة الحالية والبدائل بنفس الشكل — سعر وفرق سعر،
  /// أبعاد، وإيجابيات/سلبيات مقابل الحالية.
  Widget _compareCard(
    ThemeData theme,
    CatalogProduct p, {
    bool isCurrent = false,
    List<String> pros = const [],
    List<String> cons = const [],
    double? priceDelta,
    VoidCallback? onSelect,
  }) {
    final dims = (p.widthCm > 0 && p.depthCm > 0)
        ? '${p.widthCm.toInt()}×${p.depthCm.toInt()}×${p.heightCm.toInt()} سم'
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? BorderSide(color: theme.colorScheme.primary, width: 1.4)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(p.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Text(formatSar(p.price),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (p.brand.isNotEmpty)
                Text(p.brand,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (dims != null) ...[
                if (p.brand.isNotEmpty) const Text('  ·  '),
                Text(dims,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              const Spacer(),
              if (priceDelta != null && priceDelta != 0)
                Text(
                  priceDelta < 0
                      ? '− ${formatSar(-priceDelta)}'
                      : '+ ${formatSar(priceDelta)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: priceDelta < 0
                        ? Colors.green.shade700
                        : theme.colorScheme.error,
                  ),
                ),
            ]),
            for (final s in pros)
              _prosConsRow(theme, s, isPro: true),
            for (final s in cons) _prosConsRow(theme, s, isPro: false),
            if (onSelect != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonalIcon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('اختر هذا'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _prosConsRow(ThemeData theme, String text, {required bool isPro}) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(isPro ? Icons.add_circle_outline : Icons.remove_circle_outline,
              size: 15,
              color: isPro ? Colors.green.shade700 : theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: theme.textTheme.bodySmall)),
        ]),
      );

  // ---- bottom bar ---------------------------------------------------------

  Widget _bottomBar(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          top: false,
          child: plan.isFinalized
              ? Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('خطتك جاهزة. أنت جاهز 👏',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${plan.itemCount} قطع · ${formatSar(plan.total)}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  TextButton(
                      onPressed: () => c.reopen(),
                      child: const Text('تعديل')),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: () => _openShare(plan),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('شارك'),
                  ),
                ])
              // زرٌّ معطّل بلا سبب يُقرأ كعطل. حين لا شيء يُعتمد، يحلّ محلّه
              // السطر الذي يقول لماذا — والسبب مرئي دون تمرير.
              : plan.items.isEmpty
                  ? Text('أضِف قطعةً واحدة على الأقل لتعتمد خطتك.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                  : FilledButton.icon(
                      onPressed: () {
                        c.finalizePlan();
                        _openArrival();
                      },
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('هذه هي خطتي — أنا مطمئن'),
                    ),
        ),
      ),
    );
  }

  void _openShare(Plan plan) {
    c.logShared();
    final b = StringBuffer()
      ..writeln('خطتي — التأثيث الذكي')
      ..writeln();
    for (final it in plan.items) {
      b.writeln('• ${it.item.name} — ${formatSar(it.item.price)}');
    }
    b
      ..writeln()
      ..writeln('الإجمالي: ${formatSar(plan.total)}')
      ..writeln('الثقة: ${plan.confidence}%');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('شارك خطتك'),
        content: SelectableText(b.toString()),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('تم')),
        ],
      ),
    );
  }

  /// The arrival moment — the product's emotional payoff ("you've got this").
  void _openArrival() {
    final plan = c.plan;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.verified, color: Colors.green, size: 40),
              ),
              const SizedBox(height: 16),
              Text('خطتك جاهزة — أنت مطمئن الآن',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  'ثقة ${plan.confidence}% · ${plan.itemCount} قطع · ${formatSar(plan.total)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('تم')),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openShare(plan);
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('شارك'),
            ),
          ],
        );
      },
    );
  }

  // ---- versions: save · compare · revert (build-sequence step 9) ----------

  Widget _versionsBar(BuildContext context) {
    // Wrap لا Row: زرّان معنونان قد يتجاوزان عرض شاشةٍ ضيّقة مع خطٍّ بديل أعرض
    // (حادثة X9)، فينتقل الثاني سطرًا بدل أن يفيض الصفّ.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            c.saveSnapshot();
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('حُفظت نسخة من خطتك')));
          },
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('احفظ نسخة'),
        ),
        OutlinedButton.icon(
          onPressed: c.snapshots.isEmpty ? null : () => _openVersions(context),
          icon: const Icon(Icons.history, size: 18),
          label: Text('النسخ (${c.snapshots.length})'),
        ),
      ],
    );
  }

  void _openVersions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('النسخ المحفوظة',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (var i = 0; i < c.snapshots.length; i++)
              _versionTile(sheetContext, i, c.snapshots[i]),
          ],
        ),
      ),
    );
  }

  Widget _versionTile(BuildContext sheetContext, int i, Plan snap) {
    final theme = Theme.of(sheetContext);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('نسخة ${i + 1}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                    '${snap.itemCount} قطع · ${formatSar(snap.total)} · ثقة ${snap.confidence}%',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              final d = c.compareWith(i);
              Navigator.of(sheetContext).pop();
              _showCompare(i, d);
            },
            child: const Text('قارن'),
          ),
          FilledButton.tonal(
            onPressed: () {
              c.revertTo(i);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('استرجع'),
          ),
        ]),
      ),
    );
  }

  void _showCompare(int i, PlanDiff d) {
    final msg = _changeMessage(d) ?? 'لا فرق عن هذه النسخة.';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('مقارنة بالنسخة ${i + 1}'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('تم')),
        ],
      ),
    );
  }

  void _openConfidenceBreakdown(BuildContext context, Plan plan) {
    final a = plan.assurances;
    final rows = <(String, int, bool)>[
      ('اكتمال الأساسيات', 40, a.essentialsComplete),
      ('ضمن الميزانية', 25, a.withinBudget),
      ('تناسب الغرفة', 20, a.fitsRoom),
      ('توفّر القطع', 10, a.allAvailable),
      ('اختياراتك المثبّتة', 5, plan.pinnedCount > 0),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('من أين تأتي ثقتك؟',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(
                        r.$3
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: r.$3
                            ? Colors.green
                            : Theme.of(sheetContext).colorScheme.outline),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.$1)),
                    Text('${r.$3 ? r.$2 : 0} / ${r.$2}',
                        style: TextStyle(
                            color: r.$3
                                ? Colors.green
                                : Theme.of(sheetContext).colorScheme.outline,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(height: 24),
              Row(children: [
                const Expanded(
                    child: Text('الإجمالي',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Text('${plan.confidence}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}


/// **الفجوات المعلنة** — ما طلبه المستخدم ولا نخدمه، مذكورًا بصوت عالٍ.
///
/// ظهور هذا القسم هو الرسالة: خطة تصمت عن نقصها تبدو كاملة وليست كذلك، وذلك
/// أسرع طريق لفقد الثقة بالأداة.
class UnmetNeedsSection extends StatelessWidget {
  const UnmetNeedsSection({super.key, required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    if (!plan.hasUnmetNeeds) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طلبتها ولا نوفّرها', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('تقديرات سوق (أغسطس ٢٠٢٦) — ليست أسعارنا.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final need in plan.unmetNeeds) _NeedRow(need: need),
            if (plan.effectiveBudgetSar != null) ...[
              const Divider(height: 24),
              Text(
                'ميزانيتك للأثاث بعد الحجز: '
                '${plan.effectiveBudgetSar!.toStringAsFixed(0)} ريال',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({required this.need});
  final UnmetNeed need;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = need.tier;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(need.rawType,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            switch (need.reason) {
              // حدّ معلن — نقولها بلا اعتذار، فهي ليست عيبًا.
              UnmetReason.outOfScope => 'خارج نطاقنا حاليًا.',
              UnmetReason.notStocked => 'ضمن نطاقنا، غير متوفّرة عندنا بعد.',
              UnmetReason.noneFit => 'لا يوجد خيار يناسب غرفتك وميزانيتك.',
            },
            style: theme.textTheme.bodySmall,
          ),
          if (t != null)
            Text(
              'احجز لها ${t.lowSar.toStringAsFixed(0)}–'
              '${t.highSar.toStringAsFixed(0)} ريال · ${t.labelAr}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          // البديل الأرخص يُعرض فقط حين يغيّر النتيجة فعلًا — الفرق بين
          // الشريحتين قد يكون الفرق بين خطة تُنفَّذ وخطة لا تُنفَّذ.
          if (need.hasCheaperAlternative)
            Text(
              'لو تكفيك ${need.cheapestTier!.labelAr}: '
              '${need.cheapestTier!.lowSar.toStringAsFixed(0)}–'
              '${need.cheapestTier!.highSar.toStringAsFixed(0)} ريال — '
              'يبقى لك ${(need.reserveSar - need.cheapestTier!.midSar).toStringAsFixed(0)} '
              'ريال إضافية للأثاث.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
