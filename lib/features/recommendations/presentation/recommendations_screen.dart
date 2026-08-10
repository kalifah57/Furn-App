import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_views.dart';
import '../../room_input/presentation/flow_controller.dart';

/// شاشة التوصيات: قطع فردية + باقات (budget/balanced/premium).
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(furnishingFlowControllerProvider).project;
    if (project == null) {
      return const Scaffold(body: LoadingView(message: AppStrings.recommending));
    }
    final recs = project.recommendations;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.recommendationsTitle),
          bottom: const TabBar(tabs: [
            Tab(text: AppStrings.individualTab),
            Tab(text: AppStrings.bundlesTab),
          ]),
        ),
        body: SafeArea(
          child: recs.isEmpty
              ? _emptyFallback(context, project)
              : TabBarView(children: [
                  _individualTab(recs.individualItems),
                  _bundlesTab(recs.bundles),
                ]),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // الخطة هي المنتج، لا الحفظ: «شكّل خطتك» الفعل الأساسي هنا، والحفظ
              // ثانوي واختياري.
              FilledButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text('شكّل خطتك القابلة للتعديل'),
                onPressed: () => context.go(Routes.room),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text(AppStrings.saveProject),
                onPressed: () async {
                  final res = await ref
                      .read(furnishingFlowControllerProvider.notifier)
                      .saveCurrent();
                  if (!context.mounted) return;
                  final msg = res.isOk
                      ? AppStrings.projectSaved
                      : (res.failureOrNull?.message ?? AppStrings.genericError);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyFallback(BuildContext context, FurnishingProject p) {
    final msg = p.analysis.warnings.isNotEmpty
        ? p.analysis.warnings.last
        : 'لا توجد توصيات كافية. جرّب تعديل الميزانية أو إضافة تفاصيل.';
    return ErrorView(message: msg);
  }

  Widget _individualTab(List<RecommendedItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('لا توجد قطع فردية مطابقة.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => _ItemCard(item: items[i]),
    );
  }

  Widget _bundlesTab(List<Bundle> bundles) {
    if (bundles.isEmpty) {
      return const Center(child: Text('لا توجد باقات متاحة.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bundles.length,
      itemBuilder: (_, i) => _BundleCard(bundle: bundles[i]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final RecommendedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(formatSar(item.price),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              Chip(
                label: Text(item.category.arabicLabel),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(item.priority.arabicLabel),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
              Chip(
                label: Text('الدرجة ${item.score.toStringAsFixed(0)}'),
                visualDensity: VisualDensity.compact,
              ),
            ]),
            if (item.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.reason,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({required this.bundle});
  final Bundle bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('باقة ${bundle.tier.arabicLabel}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(formatSar(bundle.totalPrice),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            if (bundle.exceedsBudget)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(Icons.warning_amber,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(AppStrings.exceedsBudgetWarn,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ]),
              ),
            const Divider(height: 20),
            for (final item in bundle.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.check, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.name)),
                  Text(formatSar(item.price),
                      style: theme.textTheme.bodySmall),
                ]),
              ),
            if (bundle.reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              _bullet(context, AppStrings.bundleReason, bundle.reason),
            ],
            if (bundle.designNotes.isNotEmpty)
              _bullet(context, AppStrings.bundleFeatures,
                  bundle.designNotes.join('، ')),
            if (bundle.tradeoffs.isNotEmpty)
              _bullet(context, AppStrings.bundleTradeoffs,
                  bundle.tradeoffs.join('، ')),
          ],
        ),
      ),
    );
  }

  Widget _bullet(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: value),
            ],
          ),
        ),
      );
}
