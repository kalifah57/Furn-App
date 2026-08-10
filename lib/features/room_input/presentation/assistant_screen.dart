import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import 'flow_controller.dart';

/// **المساعد** — مدخلٌ واحد يحلّ محلّ مُنتقي الطريقة وشاشتَي الصوت والصورة.
///
/// النصّ هو الطريق الأساسي: يصف المستخدم غرفته بكلماته، فيستخرج المحرّك الوهمي
/// (لاحقًا مزوّد حقيقي) البيانات المنظّمة. الصوت والصورة والإدخال المفصّل بدائل،
/// لا شاشات. بعد الإرسال ينتقل إلى خطوة «التفكير» ثم إلى «غرفتي» — والمساعد بعدها
/// يعيش كورقة داخل الغرفة، لا كوجهة يُعاد إليها.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _text = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final can = _text.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _run(Future<void> Function() start) {
    start();
    context.go(Routes.assistantThinking);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flow = ref.read(furnishingFlowControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('المساعد')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('صف غرفتك وميزانيتك',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('بكلماتك — وأبني لك أوّل خطة تشكّلها حتى تثق بها.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText:
                    'مثال: غرفة نوم ٤×٣٫٧، ميزانيتي ٣٠٠٠، أبي سرير وكنب صغير وطاولة تلفزيون.',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _canSend
                  ? () => _run(() => flow.runText(_text.text.trim()))
                  : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('ابنِ خطتي'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('أو',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _run(flow.runVoice),
                  icon: const Icon(Icons.mic_none),
                  label: const Text('بالصوت'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _run(() => flow.runImages(const ['room_photo'])),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('بصورة'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.go(Routes.assistantManual),
              icon: const Icon(Icons.tune),
              label: const Text('إدخال مفصّل بالحقول'),
            ),
          ],
        ),
      ),
    );
  }
}
