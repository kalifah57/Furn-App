import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/input_options.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/models.dart';
import '../../consent/presentation/consent_banner.dart';
import 'assistant_chat.dart';
import 'flow_controller.dart';
import 'flow_state.dart';
import 'native_text_field.dart';

/// **المساعد** — سطح محادثة واحد، وهو أوّل ما يُفتح عليه التطبيق.
///
/// النصّ هو الطريق الأساسي؛ الصوت والصورة زرّان في شريط الإدخال لا شاشتان.
/// «التفكير» حالةٌ داخل المحادثة (مؤشّر كتابة) لا وجهة تُغادَر إليها، وبعد أن
/// يبني المحرّك أوّل خطة ينتقل المستخدم تلقائيًّا إلى «غرفتي» — والمساعد بعدها
/// يعيش كورقة داخل الغرفة.
///
/// تحويلٌ لا بناء: نداءات التدفّق (`runText`/`runVoice`/`runImages`) وحارس «لا
/// إرسال بلا وصف» كما كانت؛ العرض وحده تغيّر.
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

  AssistantChat get _chat => ref.read(assistantChatProvider.notifier);
  FurnishingFlowController get _flow =>
      ref.read(furnishingFlowControllerProvider.notifier);

  /// لصقٌ صريح بزرّ — لا يعتمد على قائمة ضغطٍ مطوّل قد لا يظهرها متصفح الجوال
  /// فوق حقلٍ مرسوم (حادثة dogfood). يُدرج عند المؤشّر ويستبدل التحديد إن وُجد.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final pasted = data?.text;
    if (!mounted) return;
    if (pasted == null || pasted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الحافظة فارغة — أو رفض المتصفح الإذن بقراءتها.')));
      return;
    }
    final v = _text.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    _text.value = TextEditingValue(
      text: v.text.replaceRange(sel.start, sel.end, pasted),
      selection: TextSelection.collapsed(offset: sel.start + pasted.length),
    );
  }

  void _sendText() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _chat.user(t);
    _text.clear();
    _flow.runText(t);
  }

  void _sendVoice() {
    _chat.user('🎙 رسالة صوتية');
    _flow.runVoice();
  }

  void _sendImage() {
    _chat.user('📷 صورة الغرفة');
    _flow.runImages(const ['room_photo']);
  }

  /// نتيجة المحرّك تُقال في المحادثة، ثم تُحرّك المستخدم إلى حيث يكمل عمله.
  void _onFlowChanged(FurnishingFlowState? before, FurnishingFlowState after) {
    if (before?.status == after.status) return;
    switch (after.status) {
      case FlowStatus.ready:
        _chat.assistant('خطتك الأولى جاهزة — أفتح لك غرفتك الآن.');
        context.go(Routes.room);
      case FlowStatus.needsFollowUp:
        // X8: السؤال يعيش فقاعةً في الشات بخياراتٍ قابلة للنقر (`_FollowUpBubble`)،
        // لا شاشةً تُدفَع. الشات سطح الإدخال الوحيد.
        _chat.assistant('أحتاج تفصيلًا بسيطًا لأكمل خطتك — اختر أو تخطَّ:');
      case FlowStatus.error:
        _chat.assistant(after.failure?.message ??
            'تعذّر تحليل طلبك. جرّب أن تصفه بكلماتٍ أخرى.');
      case FlowStatus.idle:
      case FlowStatus.extracting:
      case FlowStatus.recommending:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<FurnishingFlowState>(
        furnishingFlowControllerProvider, _onFlowChanged);

    final messages = ref.watch(assistantChatProvider);
    final flow = ref.watch(furnishingFlowControllerProvider);
    final busy = flow.isBusy;
    // فقاعة المتابعة تظهر بدل مؤشّر الكتابة حين ينتظر المحرّك تفصيلًا — واحدةٌ
    // منهما فقط في المقدّمة، فكلاهما «عنصرٌ قائد» في القائمة المقلوبة.
    final followUp =
        flow.status == FlowStatus.needsFollowUp && flow.project != null;
    final hasLeading = busy || followUp;

    return Scaffold(
      appBar: AppBar(title: const Text('المساعد')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ConsentBanner(),
            ),
            Expanded(
              child: ListView.builder(
                // الأحدث أسفل بلا متحكّم تمرير: القائمة مقلوبة، فالفهرس ٠ آخر سطر.
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: messages.length + (hasLeading ? 1 : 0),
                itemBuilder: (context, i) {
                  if (hasLeading && i == 0) {
                    return busy
                        ? const _TypingBubble()
                        : _FollowUpBubble(project: flow.project!);
                  }
                  final m =
                      messages[messages.length - 1 - (hasLeading ? i - 1 : i)];
                  return _Bubble(message: m);
                },
              ),
            ),
            _composer(context),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'أضِف صورة الغرفة (تجريبي)',
                onPressed: _sendImage,
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton(
                tooltip: 'سجّل صوتك (تجريبي)',
                onPressed: _sendVoice,
                icon: const Icon(Icons.mic_none),
              ),
              IconButton(
                tooltip: 'ألصق من الحافظة',
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_outlined),
              ),
              Expanded(
                // عنصر DOM أصلي على الويب (لصق/تحديد/لوحة مفاتيح المتصفح
                // نفسها)، وTextField في بيئة الاختبار — درس خمس محاولات لصق.
                child: NativeChatInput(
                  controller: _text,
                  hint: 'صف غرفتك وميزانيتك…',
                  onSubmitted: _sendText,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'أرسل',
                onPressed: _canSend ? _sendText : null,
                // سهم الإرسال لا يعكسه Flutter تلقائيًّا، فيشير في واجهة عربية
                // إلى عكس اتجاه الإرسال.
                icon: Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: const Icon(Icons.send),
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => context.push(Routes.assistantManual),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('إدخال مفصّل بالحقول'),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.author == ChatAuthor.user;
    return Align(
      alignment:
          isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isUser
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// «التفكير» — حالةٌ داخل المحادثة لا شاشة تُغادَر إليها.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('أفكّر في خطتك…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// **سؤال المتابعة داخل المحادثة (X8)** — فقاعةٌ بخياراتٍ قابلة للنقر بدل نافذة.
///
/// النقرة الواحدة تُجيب وتُكمل التدفّق تلقائيًّا: تُضيف القطعة أو تضبط النمط ثم
/// `proceedAfterFollowUp`، فتتحوّل الحالة إلى «يفكّر» ثم إلى غرفتي. «تخطَّ» يمضي
/// على المتوفّر. القرار كلّه للمحرّك؛ هذه الفقاعة تجمع الإجابة فحسب.
///
/// الأرقام (المقاس، مبلغ الميزانية) لا تُختصر في نقرة، فتُترك لغرفتي (المؤشّر
/// والفجوات) — وعقد الخيارات المنظّم لكل سؤال يُنسَّق مع مسار ٣ حين يلزم.
class _FollowUpBubble extends ConsumerWidget {
  const _FollowUpBubble({required this.project});

  final FurnishingProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final flow = ref.read(furnishingFlowControllerProvider.notifier);

    // نقرأ الحاجة من الحقول لا من مطابقة نصّ المحرّك — أصدق وأمتن.
    final needItems = project.items.essential.isEmpty;
    final needStyle =
        project.style.preferred.isEmpty && project.style.colors.isEmpty;

    void addItem(String value) => flow.proceedAfterFollowUp(
          project.copyWith(
            items: project.items.copyWith(
              essential: [
                ...project.items.essential,
                RequestedItem(type: value),
              ],
            ),
          ),
        );

    void setStyle(String value) => flow.proceedAfterFollowUp(
          project.copyWith(style: project.style.copyWith(preferred: [value])),
        );

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needItems) ...[
              Text('أيّ قطعة أساسية أبدأ بها؟',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in itemTypeOptions.entries)
                    ActionChip(
                      label: Text(e.key),
                      onPressed: () => addItem(e.value),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (needStyle) ...[
              Text(needItems ? 'أو نمطٌ يعجبك؟' : 'أيّ نمطٍ يعجبك؟',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in styleOptions.entries)
                    ActionChip(
                      label: Text(e.key),
                      onPressed: () => setStyle(e.value),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (!needItems && !needStyle)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('يمكنك ضبط الميزانية داخل غرفتك.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => flow.skipFollowUp(),
                child: const Text('تخطَّ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
