import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/handoff_session.dart';

/// سطح الاقتران على المتصفّح: يعرض **رمزًا من ست خانات** يُكتب على الجوال، ثم
/// يتابع مراحل المسح حتى تصل القياسات.
///
/// لا رمز QR في هذه المرحلة عن قصد: توليد QR يحتاج حزمة جديدة، والرابط الشامل
/// (Universal Link) الذي يفتحه يحتاج نطاقًا وحسابًا مدفوعًا — وكلاهما يؤجّل
/// الاختبار أيامًا. الرمز المكتوب يعمل اليوم، وهو الاحتياط المطلوب على أي حال
/// حين ترفض الكاميرا التقاط الرمز.
class PairingSheet extends StatelessWidget {
  const PairingSheet({
    super.key,
    required this.session,
    required this.serverUrl,
    this.onCancel,
  });

  final HandoffSession session;

  /// عنوان الماك على الشبكة المحلّية كما يُكتب في الجوال.
  final String serverUrl;

  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('امسح غرفتك بجوالك',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'هذا الجهاز لا يملك مستشعر LiDAR. افتح تطبيق فرن على جوالك، '
              'وأدخل هذا الرمز:',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _CodeBlock(code: session.pairingCode),
            const SizedBox(height: 16),
            _Field(label: 'عنوان الجهاز', value: serverUrl),
            const SizedBox(height: 20),
            _StageList(status: session.status),
            if (session.status == HandoffStatus.failed &&
                session.failureMessage != null) ...[
              const SizedBox(height: 12),
              Text(session.failureMessage!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                  textAlign: TextAlign.center),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onCancel, child: const Text('إلغاء')),
            ],
          ],
        ),
      ),
    );
  }
}

/// الرمز بخط عريض متباعد — يُقرأ عبر الغرفة ويُنسخ بضغطة.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Clipboard.setData(ClipboardData(text: code)),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          code,
          textAlign: TextAlign.center,
          // Latin digits/letters: the code is typed on a phone keyboard, so it
          // stays LTR even in an RTL layout.
          textDirection: TextDirection.ltr,
          style: theme.textTheme.displaySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label: ', style: theme.textTheme.bodySmall),
        SelectableText(
          value,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// المراحل مرئية: المستخدم يمشي إلى الغرفة، ودوّارة صامتة دقيقتين تُقرأ كتعليق.
class _StageList extends StatelessWidget {
  const _StageList({required this.status});
  final HandoffStatus status;

  static const _stages = <HandoffStatus, String>{
    HandoffStatus.pending: 'بانتظار الجوال',
    HandoffStatus.linked: 'تم الاقتران',
    HandoffStatus.scanning: 'جارٍ المسح',
    HandoffStatus.processing: 'معالجة القياسات',
    HandoffStatus.completed: 'وصلت القياسات',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _stages.keys.toList();
    final currentIndex = order.indexOf(status);

    return Column(
      children: [
        for (var i = 0; i < order.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  i < currentIndex
                      ? Icons.check_circle
                      : i == currentIndex
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  size: 18,
                  color: i <= currentIndex
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  _stages[order[i]]!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        i == currentIndex ? FontWeight.bold : FontWeight.normal,
                    color: i <= currentIndex
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
