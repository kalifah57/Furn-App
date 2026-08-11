import 'package:flutter/material.dart';

import 'plan_controller.dart';

/// **المساعد كورقةٍ داخل «غرفتي»** — لا شاشة يُغادَر إليها.
///
/// يخاطبه المستخدم بلغته («اجعلها أوفر»، «أضف سجادة»، «جاهز»)، فيفهم الأمر
/// (mock الآن، مزوّد LLM لاحقًا) ويُنفّذه المحرّك الحتمي ويعيد سطر نتيجة. الورقة
/// تبقى مفتوحة ليُتبِع أمرًا بأمر — والخطة خلفها تتحدّث فورًا. الـ AI يترجم اللغة
/// إلى نيّة فقط؛ القرار للمحرّك.
Future<void> showAssistantSheet(
    BuildContext context, PlanController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AssistantSheet(controller: controller),
  );
}

class _AssistantSheet extends StatefulWidget {
  const _AssistantSheet({required this.controller});
  final PlanController controller;

  @override
  State<_AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<_AssistantSheet> {
  final _text = TextEditingController();
  CommandResult? _last;

  static const _suggestions = [
    'اجعلها أوفر',
    'أضف طاولة',
    'ميزانيتي ٣٠٠٠',
    'جاهز',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send(String text) {
    final t = text.trim();
    // ضغطةٌ لا تُنتج شيئًا ولا تشرح تُقرأ كعطل في الزرّ. نجيب بنفس قناة
    // الإجابة المعتادة بدل الصمت.
    if (t.isEmpty) {
      setState(() => _last = const CommandResult(
            understood: false,
            message: 'اكتب ما تريد تغييره، أو اختر اقتراحًا من الأعلى.',
          ));
      return;
    }
    final result = widget.controller.runCommand(t);
    setState(() {
      _last = result;
      if (result.understood) _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('المساعد',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text('خاطبني بلغتك وسأعدّل خطتك — والمحرّك يحسب النتيجة.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_last != null) _outcome(theme, _last!),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _suggestions)
                ActionChip(label: Text(s), onPressed: () => _send(s)),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: 'مثال: اجعلها أوفر، أو أضف سجادة',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => _send(_text.text),
              // `Icons.send` سهمٌ يشير يمينًا ولا يعكسه Flutter تلقائيًّا، فيشير
              // في واجهةٍ عربية إلى عكس اتجاه الإرسال. نعكسه بالاتجاه لا بثابت.
              icon: Transform.flip(
                flipX: Directionality.of(context) == TextDirection.rtl,
                child: const Icon(Icons.send),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _outcome(ThemeData theme, CommandResult r) {
    final bg = r.understood
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.errorContainer;
    final fg = r.understood
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onErrorContainer;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(r.understood ? Icons.check_circle_outline : Icons.help_outline,
            size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(r.message, style: TextStyle(color: fg))),
      ]),
    );
  }
}
