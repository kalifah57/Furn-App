import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../domain_engine/plan/plan.dart';
import '../../../domain_engine/plan/unmet_need.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/formatters.dart';
import '../../ar/ar_button.dart';
import '../../options/option_card.dart';
import 'plan_controller.dart';

/// شاشة الخطة — قلب التطبيق (product_thesis.md): «الخطة» التي يشكّلها المستخدم
/// حتى يثق بها. تعرض حلقة الثقة: ثبّت/ارفض/بدّل/اضبط الميزانية → إعادة توازن فورية
/// مع ضمانات وتفسير ومؤشّر جاهزية، ثم «هذه هي خطتي».
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('خطتي'),
        actions: [
          // بوّابة الواقع المعزّز على مستوى الكتالوج: تعرض ما يدخل في الغرفة
          // فعلًا (ArSpatialEngine) قبل فتح الكاميرا.
          IconButton(
            tooltip: 'شاهدها في غرفتك',
            icon: const Icon(Icons.view_in_ar),
            onPressed: () => context.push(Routes.ar),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذّر تحميل الكتالوج: $e', textAlign: TextAlign.center),
        )),
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
              Text('قطع خطتك',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final item in plan.items) _itemCard(context, item),
            ],
          ),
        ),
        _bottomBar(context, plan),
      ],
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
                  Text('جاهزية خطتك',
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
              tooltip: 'من أين تأتي الجاهزية؟',
              onPressed: () => _openConfidenceBreakdown(context, plan),
            ),
          ],
        ),
      ),
    );
  }

  Color _confColor(int v, ColorScheme s) =>
      v >= 80 ? Colors.green : (v >= 50 ? Colors.orange : s.error);

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
              Text('الميزانية', style: theme.textTheme.titleMedium),
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
                    onPressed: () => c.addCheapestOf(cat),
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
              Text('شاهدها في غرفتك',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
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
            const ArDemoButton(label: 'شاهد الطاولة في غرفتك'),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
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
                icon: const Icon(Icons.grid_view_outlined, size: 18),
                label: Text(() {
                  final n = c.alternativesFor(item.category).length;
                  return n > 1 ? 'الخيارات ($n)' : 'بدّل';
                }()),
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

  /// متصفّح الخيارات الغنيّ — «أرِني الخيارات»: كل خيارات الفئة المتاحة
  /// (المتجر، السعر، الأبعاد + هل تناسب غرفتك، الألوان، الخامات، التقييم،
  /// الواقع المعزّز) في ورقة قابلة للتمرير، مع تمييز الخيار الحالي.
  void _openAlternatives(RecommendedItem item) {
    final id = item.productId;
    if (id == null) return;
    final options = c.alternativesFor(item.category);
    final room = c.project.room;
    c.logOptionsOpened(item.category, options.length);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Icon(Icons.grid_view, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'خيارات ${item.category.arabicLabel} — ${options.length}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'قارن وجرّبها في غرفتك، ثم اختر ما تثق به.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: options.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('لا توجد خيارات متاحة ضمن هذه الفئة.'),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: options.length,
                        itemBuilder: (_, i) {
                          final p = options[i];
                          final current = p.productId == id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OptionCard(
                              product: p,
                              room: room,
                              isCurrent: current,
                              onSelect: current
                                  ? null
                                  : () {
                                      Navigator.of(sheetContext).pop();
                                      c.swap(id, p.productId);
                                    },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

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
              : FilledButton.icon(
                  onPressed: plan.items.isEmpty
                      ? null
                      : () {
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
      ..writeln('الجاهزية: ${plan.confidence}%');
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
                  'جاهزية ${plan.confidence}% · ${plan.itemCount} قطع · ${formatSar(plan.total)}',
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
    return Row(children: [
      OutlinedButton.icon(
        onPressed: () {
          c.saveSnapshot();
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('حُفظت نسخة من خطتك')));
        },
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('احفظ نسخة'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: c.snapshots.isEmpty ? null : () => _openVersions(context),
        icon: const Icon(Icons.history, size: 18),
        label: Text('النسخ (${c.snapshots.length})'),
      ),
    ]);
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
                    '${snap.itemCount} قطع · ${formatSar(snap.total)} · جاهزية ${snap.confidence}%',
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
              Text('من أين تأتي جاهزيتك؟',
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
