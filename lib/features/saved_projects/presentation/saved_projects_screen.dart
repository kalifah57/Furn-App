import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/furnishing_project.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_views.dart';

/// يجلب المشاريع المحفوظة (يُعاد الجلب عند كل دخول).
final savedProjectsProvider =
    FutureProvider.autoDispose<List<FurnishingProject>>((ref) async {
  final res = await ref.read(projectRepositoryProvider).listProjects();
  return res.fold((list) => list, (failure) => throw failure);
});

/// شاشة المشاريع المحفوظة (PRD — حفظ المشاريع والرجوع إليها).
class SavedProjectsScreen extends ConsumerWidget {
  const SavedProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedProjectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.savedTitle)),
      body: SafeArea(
        child: async.when(
          loading: () => const LoadingView(message: 'جاري فتح مشاريعك…'),
          error: (e, _) => ErrorView(
            message: AppStrings.genericError,
            onRetry: () => ref.invalidate(savedProjectsProvider),
          ),
          data: (projects) => projects.isEmpty
              ? const _NoSavedProjects()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: projects.length,
                  itemBuilder: (_, i) => _ProjectTile(project: projects[i]),
                ),
        ),
      ),
    );
  }
}

/// فراغٌ بمستوى X1: أيقونة + جملة + مخرج، لا سطرٌ عارٍ في طريقٍ مسدود.
class _NoSavedProjects extends StatelessWidget {
  const _NoSavedProjects();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmarks_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(AppStrings.noSavedProjects,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('اِبنِ خطةً من المساعد، ثم احفظها لتعود إليها هنا.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.go(Routes.assistant),
              child: const Text('ابدأ من المساعد'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});
  final FurnishingProject project;

  @override
  Widget build(BuildContext context) {
    final bundles = project.recommendations.bundles;
    final cheapest = bundles.isEmpty
        ? null
        : bundles
            .map((b) => b.totalPrice)
            .reduce((a, b) => a < b ? a : b);
    final title = project.analysis.summary.isEmpty
        ? project.room.roomType.arabicLabel
        : project.analysis.summary;

    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.chair_alt_outlined)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          project.room.roomType.arabicLabel,
          if (cheapest != null) 'من ${formatSar(cheapest)}',
        ].join(' · ')),
        trailing: Text(
          '${project.recommendations.individualItems.length} قطعة',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
