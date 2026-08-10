import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'consent_controller.dart';

/// يُعرض حتى يختار المستخدم، ثم يختفي. قبل اختياره لا يُجمَع أي حدث — فالبانر
/// ليس تجميلًا بل **البوّابة** التي تفصل «لم يُسأل» عن «وافق».
class ConsentBanner extends ConsumerWidget {
  const ConsentBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decided = ref.watch(consentControllerProvider) != null;
    if (decided) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final controller = ref.read(consentControllerProvider.notifier);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('نحسّن التطبيق بقياس مجهول',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'نقيس خطواتٍ مجهولة (بلا اسمك ولا بياناتك) لنعرف أين نحسّن الخطة. '
              'يمكنك الرفض، ويظلّ كل شيء يعمل كما هو.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => controller.decide(granted: false),
                  child: const Text('لا، شكرًا'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => controller.decide(granted: true),
                  child: const Text('أوافق'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
