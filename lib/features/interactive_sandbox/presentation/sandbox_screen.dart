import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain_engine/spatial/replacement_finder.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_views.dart';
import '../../ar/ar_button.dart';
import '../../catalog/open_store.dart';
import 'sandbox_controller.dart';
import 'sandbox_scene_view.dart';

/// **الصندوق المكاني التفاعلي** — الغرفة الممسوحة مفروشة بباقة كاملة، يمكن نقر
/// أي قطعة لرؤية تفاصيلها واستبدالها، مع تحديث السعر الإجمالي في نفس اللحظة.
class SandboxScreen extends ConsumerWidget {
  const SandboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sandboxControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('صمّم غرفتك'),
        actions: [
          IconButton(
            tooltip: 'امسح غرفتي',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => _rescan(context, ref),
          ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(message: 'جاري وضع خطتك في غرفتك…'),
        error: (_, __) => ErrorView(
          message: 'تعذّر بناء المشهد. أعد المحاولة.',
          onRetry: () => ref.invalidate(sandboxControllerProvider),
        ),
        // مشهدٌ بلا قطع ليس خطأً بل خطةٌ لم تُشكَّل بعد — يُقال ذلك ويُقال معه
        // الطريق إلى المكان الذي تُشكَّل فيه.
        data: (s) => s.items.isEmpty
            ? const _EmptyScene()
            : Column(
                children: [
                  _BudgetBar(state: s),
                  if (s.plan.unplaced.isNotEmpty)
                    _UnplacedNotice(count: s.plan.unplaced.length),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      // تكبير/تحريك المشهد ليتفحّص المستخدم المطابقة عن قرب.
                      // النقر يبقى اختيارًا: الإزاحة تُحرّك، والنقرة تصل إلى
                      // مُحدِّد القطعة بإحداثيات القطعة نفسها (يُعيد Flutter
                      // موضع النقر إلى فضاء الطفل عبر التحويل)، فلا يفسد
                      // الاختيار مع التكبير.
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: SandboxSceneView(
                          room: s.space,
                          placements: s.items,
                          selectedProductId: s.selectedProductId,
                          onTapItem: (id) => _onTap(context, ref, id),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// يعيد بناء المشهد من خدمة المسح (محاكاة اليوم — تُعيد غرفة تمثيلية).
  ///
  /// نُبقي المشهد الحالي معروضًا أثناء الانتظار: إفراغ الشاشة بينما تُعاد القياسات
  /// يبدو كتعطّل. يوم يدخل مسحٌ حقيقي النطاق، يُستبدل مزوّد الخدمة وحده.
  Future<void> _rescan(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(sandboxControllerProvider.notifier).rescan();
    final failure = result.failureOrNull;
    if (failure == null) return;
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }

  void _onTap(BuildContext context, WidgetRef ref, String? productId) {
    final controller = ref.read(sandboxControllerProvider.notifier);
    if (productId == null) {
      controller.clearSelection();
      return;
    }
    controller.selectItem(productId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(productId: productId),
    ).whenComplete(controller.clearSelection);
  }
}

/// المعاينة هي «أن يرى» — وحين لا شيء ليُرى، الفعل الوحيد المفيد هو العودة إلى
/// المكان الذي تُشكَّل فيه الخطة.
class _EmptyScene extends StatelessWidget {
  const _EmptyScene();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('لا شيء لنعرضه بعد.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('شكّل خطتك في غرفتي ثم عد لترى كيف تتوزّع في مساحتك.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.go(Routes.room),
              child: const Text('إلى غرفتي'),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط الميزانية — يُعاد حسابه من حالة المشهد، فيتحرّك لحظة أي استبدال.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.state});
  final SandboxState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = state.isOverBudget;
    final ratio = state.totalBudget <= 0
        ? 0.0
        : (state.spent / state.totalBudget).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${state.items.length} قطعة',
                  style: theme.textTheme.bodyMedium),
              Text(
                over
                    ? 'تجاوزت بـ ${formatSar(-state.remaining)}'
                    : 'المتبقّي ${formatSar(state.remaining)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: over ? theme.colorScheme.error : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: over ? theme.colorScheme.error : null,
          ),
          const SizedBox(height: 4),
          Text('${formatSar(state.spent)} من ${formatSar(state.totalBudget)}',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// لا نُسقط قطعة بصمت: إن لم يجد الحلّال لها مكانًا، يعرف المستخدم.
class _UnplacedNotice extends StatelessWidget {
  const _UnplacedNotice({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 16, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$count قطعة لم تجد مكانًا في هذه الغرفة',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
}

/// ورقة تفاصيل القطعة المنقورة: السعر، العلامة، المقاس، المصدر، والاستبدال.
class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sandboxControllerProvider).valueOrNull;
    final slot = s?.plan.byProductId(productId);
    // ورقة تُفتح فارغة تمامًا تُقرأ كعطل. يحدث هذا حين تُزال القطعة من تحتها —
    // فتُقال الحقيقة بدل أن يُترك المستخدم أمام مستطيل أبيض.
    if (s == null || slot == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('لم تعد هذه القطعة في المشهد.', textAlign: TextAlign.center),
      );
    }

    final p = slot.product;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(formatSar(p.price),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            _Detail(label: 'العلامة', value: p.brand.isEmpty ? '—' : p.brand),
            _Detail(
              label: 'المقاس',
              value: '${p.widthCm.toInt()} × ${p.depthCm.toInt()} × '
                  '${p.heightCm.toInt()} سم',
            ),
            _Detail(label: 'الفئة', value: p.category.arabicLabel),
            // زر حقيقي لا نصٌّ خام: يُظهر نيّة الشراء ويُطلق merchant_click.
            // يظهر فقط لمنتج له رابط متجر — فهو خامد على البيانات الوهمية،
            // ويضيء لحظة وصول كاتلوج آيكيا الحقيقي (product_link).
            if (p.productUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(analyticsProvider).track(
                      MerchantClicked(p.productId, category: p.category.wire));
                  openStore(p.productUrl);
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('افتح في المتجر'),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                ArButton(product: p),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    ref
                        .read(sandboxControllerProvider.notifier)
                        .removeItem(productId);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('أزل'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showAlternatives(context, ref, productId),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('بدّل'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAlternatives(BuildContext context, WidgetRef ref, String id) {
    final alternatives =
        ref.read(sandboxControllerProvider.notifier).alternativesFor(id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AlternativesSheet(productId: id, options: alternatives),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
                child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

/// البدائل الصالحة فقط: ما يدخل في الخانة وضمن الميزانية المُحرَّرة.
class _AlternativesSheet extends ConsumerWidget {
  const _AlternativesSheet({required this.productId, required this.options});

  final String productId;
  final List<ReplacementCandidate> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'لا يوجد بديل يدخل في نفس المكان ضمن ميزانيتك المتبقّية.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: options.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final c = options[i];
          final delta = c.priceDelta;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.product.title),
            subtitle: Text(
              '${c.product.widthCm.toInt()}×${c.product.depthCm.toInt()} سم · '
              '${formatSar(c.product.price)}',
            ),
            trailing: Text(
              delta == 0
                  ? '—'
                  : (delta < 0 ? '− ${formatSar(-delta)}' : '+ ${formatSar(delta)}'),
              style: theme.textTheme.labelLarge?.copyWith(
                color: delta <= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
            ),
            onTap: () {
              ref.read(sandboxControllerProvider.notifier).replaceItem(
                    productId: productId,
                    replacementProductId: c.product.productId,
                  );
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }
}
