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
            const SizedBox(height: 12),
            // زرّان مبنيّان من عناصر أوّلية مضمونة الرسم على محرّك HTML: حاوية
            // بلونٍ صريح ونصّ فوقها — لا طبقات Material قد لا تُطلى. حادثة X9:
            // «أوافق/لا شكرًا» كانا يحجزان المساحة ولا يظهران، فيبقى بانر PDPL
            // أبديًّا ويموت القياس. عريضان بارتفاع ٤٨ (هدف لمسٍ آمن).
            Row(
              children: [
                Expanded(
                  child: _ConsentAction(
                    label: 'لا، شكرًا',
                    filled: false,
                    onTap: () => controller.decide(granted: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ConsentAction(
                    label: 'أوافق',
                    filled: true,
                    onTap: () => controller.decide(granted: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// فعلُ موافقةٍ مرسومٌ بعناصر أوّلية: `GestureDetector` فوق حاوية ملوّنة صريحة
/// ونصّ صريح اللون. يتجاوز أي عطبٍ في طلاء أزرار Material على محرّك HTML، ويبقى
/// زرًّا دلاليًّا لقارئ الشاشة وهدف لمسٍ لا يقلّ عن ٤٨ بكسل.
class _ConsentAction extends StatelessWidget {
  const _ConsentAction({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = filled ? cs.primary : cs.surface;
    final fg = filled ? cs.onPrimary : cs.primary;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: filled ? null : Border.all(color: cs.outline),
          ),
          child: Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
