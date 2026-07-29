import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/input_options.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/multi_select_chips.dart';
import '../../../shared/widgets/status_views.dart';
import '../../room_input/presentation/flow_controller.dart';
import '../../room_input/presentation/flow_state.dart';

/// شاشة التحليل: تعرض التحميل، أسئلة المتابعة عند نقص البيانات، وملخص الطلب.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  final _width = TextEditingController();
  final _length = TextEditingController();
  final _budget = TextEditingController();
  final _styles = <String>{};
  final _essential = <String>{};

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(furnishingFlowControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.requestSummary)),
      body: SafeArea(child: _body(state)),
    );
  }

  Widget _body(FurnishingFlowState state) {
    switch (state.status) {
      case FlowStatus.extracting:
      case FlowStatus.idle:
        return const LoadingView(message: AppStrings.analyzing);
      case FlowStatus.recommending:
        return const LoadingView(message: AppStrings.recommending);
      case FlowStatus.error:
        return ErrorView(
          message: state.failure?.message ?? AppStrings.genericError,
          onRetry: () => context.go(Routes.inputMethod),
        );
      case FlowStatus.needsFollowUp:
        return _followUp(state.project!);
      case FlowStatus.ready:
        return _summary(state.project!);
    }
  }

  // ---- أسئلة المتابعة ----
  Widget _followUp(FurnishingProject p) {
    final missing = p.analysis.missingInformation;
    final needDims = missing.any((m) => m.contains('أبعاد'));
    final needBudget = missing.any((m) => m.contains('ميزانية'));
    final needItems = missing.any((m) => m.contains('أساسية'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(AppStrings.followUpTitle,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(AppStrings.followUpHint,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        for (final q in p.nextActions.followUpQuestions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.help_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(q)),
            ]),
          ),
        const SizedBox(height: 12),
        if (needDims)
          Row(children: [
            Expanded(
                child: AppNumberField(controller: _width, label: AppStrings.widthM)),
            const SizedBox(width: 12),
            Expanded(
                child:
                    AppNumberField(controller: _length, label: AppStrings.lengthM)),
          ]),
        if (needBudget) ...[
          const SizedBox(height: 12),
          AppNumberField(controller: _budget, label: AppStrings.budgetMax),
        ],
        if (needItems) ...[
          const SizedBox(height: 12),
          const SectionHeader(AppStrings.essentialItems),
          MultiSelectChips(
            options: itemTypeOptions,
            selected: _essential,
            onToggle: (v, sel) => _toggle(_essential, v, sel),
          ),
        ],
        const SizedBox(height: 12),
        const SectionHeader(AppStrings.preferredStyle),
        MultiSelectChips(
          options: styleOptions,
          selected: _styles,
          onToggle: (v, sel) => _toggle(_styles, v, sel),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _continueWith(p),
          child: const Text(AppStrings.continueBtn),
        ),
        TextButton(
          onPressed: () =>
              ref.read(furnishingFlowControllerProvider.notifier).skipFollowUp(),
          child: const Text(AppStrings.skip),
        ),
      ],
    );
  }

  void _continueWith(FurnishingProject p) {
    var updated = p;
    final w = double.tryParse(_width.text.trim());
    final l = double.tryParse(_length.text.trim());
    if (w != null || l != null) {
      updated = updated.copyWith(
        room: updated.room.copyWith(
          widthM: w ?? updated.room.widthM,
          lengthM: l ?? updated.room.lengthM,
        ),
      );
    }
    final b = double.tryParse(_budget.text.trim());
    if (b != null) {
      updated = updated.copyWith(budget: updated.budget.copyWith(maxTotal: b));
    }
    if (_essential.isNotEmpty) {
      updated = updated.copyWith(
        items: updated.items.copyWith(
          essential: [
            ...updated.items.essential,
            for (final t in _essential) RequestedItem(type: t),
          ],
        ),
      );
    }
    if (_styles.isNotEmpty) {
      updated = updated.copyWith(
          style: updated.style.copyWith(preferred: _styles.toList()));
    }
    ref
        .read(furnishingFlowControllerProvider.notifier)
        .proceedAfterFollowUp(updated);
  }

  // ---- ملخص الطلب ----
  Widget _summary(FurnishingProject p) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.requestSummary,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(p.analysis.summary.isEmpty ? '—' : p.analysis.summary),
                const Divider(height: 24),
                _row('نوع الغرفة', p.room.roomType.arabicLabel),
                if (p.room.areaM2 > 0)
                  _row('الأبعاد',
                      '${p.room.widthM} × ${p.room.lengthM} م (${p.room.areaM2.toStringAsFixed(0)} م²)'),
                if (p.budget.hasBudget)
                  _row(AppStrings.budgetMax, formatSar(p.budget.maxTotal)),
                _row(AppStrings.confidence, formatPercent(p.analysis.confidenceScore)),
              ],
            ),
          ),
        ),
        if (p.items.essential.isNotEmpty) ...[
          const SectionHeader(AppStrings.essentialItems),
          _itemWrap(p.items.essential),
        ],
        if (p.items.optional.isNotEmpty) ...[
          const SectionHeader(AppStrings.optionalItems),
          _itemWrap(p.items.optional),
        ],
        if (p.analysis.warnings.isNotEmpty) ...[
          const SectionHeader(AppStrings.warnings, icon: Icons.warning_amber),
          for (final w in p.analysis.warnings)
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(w),
            ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.recommend),
          label: const Text(AppStrings.viewRecommendations),
          onPressed: () => context.go(Routes.recommendations),
        ),
      ],
    );
  }

  Widget _itemWrap(List<RequestedItem> items) => Wrap(
        spacing: 8,
        children: [
          for (final i in items) Chip(label: Text(i.type)),
        ],
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  void _toggle(Set<String> set, String value, bool isSelected) =>
      setState(() => isSelected ? set.add(value) : set.remove(value));
}
