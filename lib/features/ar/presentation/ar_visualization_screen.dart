import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain_engine/spatial/ar_spatial_engine.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/formatters.dart';
import '../ar_button.dart';
import 'ar_providers.dart';

/// شاشة «شاهدها في غرفتك» — بوّابة الواقع المعزّز.
///
/// لا تفتح الكاميرا على أي قطعة: [ArSpatialEngine] يقرّر أولًا ما الذي *يدخل
/// فعلًا* في الغرفة الممسوحة بعد ما وُضع فيها. القطع غير المطابقة تبقى معروضة
/// مع سببها بدل أن تختفي بصمت — الشفافية هي ما يبني الثقة بالقياس.
class ArVisualizationScreen extends ConsumerWidget {
  const ArVisualizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(arFitResultsProvider);
    final room = ref.watch(arRoomProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('شاهدها في غرفتك')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('تعذّر تحميل الكتالوج: $e', textAlign: TextAlign.center),
          ),
        ),
        data: (results) => _ArView(results: results, room: room),
      ),
    );
  }
}

class _ArView extends ConsumerWidget {
  const _ArView({required this.results, required this.room});

  final List<ArFitResult> results;
  final Room room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fitting = results.where((r) => r.canPlace).toList();
    final blocked = results.where((r) => !r.canPlace).toList();
    final placed = ref.watch(arPlacedProvider);
    final space = RoomSpace.fromRoom(room);
    final usedRatio = space.areaCm2 <= 0
        ? 0.0
        : placed
                .fold<double>(0, (s, e) => s + e.widthCm * e.depthCm) /
            space.areaCm2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RoomHeader(room: room, usedRatio: usedRatio, placedCount: placed.length),
        const SizedBox(height: 16),
        _SectionTitle('تدخل في غرفتك', count: fitting.length),
        if (fitting.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('لا تدخل أي قطعة بالمساحة المتبقّية. أزل قطعة لتحرير مساحة.'),
          ),
        for (final r in fitting)
          _FitCard(
            result: r,
            isPlaced: placed.contains(r.product),
            onToggle: () => _togglePlaced(ref, r.product),
          ),
        if (blocked.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionTitle('لا تدخل — والسبب', count: blocked.length),
          for (final r in blocked) _BlockedTile(result: r),
        ],
      ],
    );
  }

  void _togglePlaced(WidgetRef ref, CatalogProduct p) {
    final notifier = ref.read(arPlacedProvider.notifier);
    final current = notifier.state;
    notifier.state = current.contains(p)
        ? [for (final e in current) if (e != p) e]
        : [...current, p];
  }
}

/// ملخّص الغرفة ونسبة الإشغال — الرقم الذي تُبنى عليه كل قرارات المحرّك.
class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.room,
    required this.usedRatio,
    required this.placedCount,
  });

  final Room room;
  final double usedRatio;
  final int placedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (usedRatio * 100).clamp(0, 100).toStringAsFixed(0);
    final over = usedRatio > kMaxFloorOccupancy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('غرفتك: ${room.widthM}×${room.lengthM} م '
                '(${room.areaM2.toStringAsFixed(1)} م²)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: usedRatio.clamp(0.0, 1.0),
              minHeight: 8,
              color: over ? theme.colorScheme.error : null,
            ),
            const SizedBox(height: 8),
            Text(
              'الإشغال $pct٪ من الأرضية · $placedCount قطعة مثبّتة · '
              'الحدّ ${(kMaxFloorOccupancy * 100).toInt()}٪ ليبقى ممرّ حركة',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.count});
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$text ($count)',
            style: Theme.of(context).textTheme.titleMedium),
      );
}

/// قطعة تدخل: تُعرض بأبعادها الحقيقية مع زر فتح الكاميرا بمقاسها.
class _FitCard extends StatelessWidget {
  const _FitCard({
    required this.result,
    required this.isPlaced,
    required this.onToggle,
  });

  final ArFitResult result;
  final bool isPlaced;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = result.product;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${p.widthCm.toInt()}×${p.depthCm.toInt()}×${p.heightCm.toInt()} سم'
              ' · ${formatSar(p.price)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ArButton(product: p),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(isPlaced ? Icons.remove_circle_outline
                      : Icons.add_circle_outline, size: 18),
                  label: Text(isPlaced ? 'أزل من الغرفة' : 'ثبّت في الغرفة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// قطعة لا تدخل: نعرضها مع السبب بدل إخفائها — هكذا يتعلّم المستخدم حدود غرفته.
class _BlockedTile extends StatelessWidget {
  const _BlockedTile({required this.result});
  final ArFitResult result;

  @override
  Widget build(BuildContext context) {
    final p = result.product;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.block, size: 20),
      title: Text(p.title),
      subtitle: Text('${p.widthCm.toInt()}×${p.depthCm.toInt()} سم — '
          '${result.reasonAr}'),
    );
  }
}
