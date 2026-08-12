import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// نسخة الويب: `<textarea>` حقيقي داخل [HtmlElementView].
///
/// عنصر متصفح أصلي ⇒ الضغط المطوّل يعرض قائمة المتصفح **الأصلية** (لصق/تحديد/
/// إملاء) لأنها قائمته على عنصره — لا Flutter في المنتصف ولا إذن حافظة برمجي.
/// المزامنة باتجاهين: إدخال المستخدم → controller (فيتحدّث زرّ الإرسال)،
/// وتغيير الـcontroller (مسح بعد الإرسال، زرّ اللصق الاحتياطي) → العنصر.
class NativeChatInput extends StatefulWidget {
  const NativeChatInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmitted;

  @override
  State<NativeChatInput> createState() => _NativeChatInputState();
}

class _NativeChatInputState extends State<NativeChatInput> {
  late final String _viewType;
  html.TextAreaElement? _area;

  @override
  void initState() {
    super.initState();
    // اسم فريد لكل تركيب: السجلّ عالمي، وإعادة تسجيل الاسم نفسه بعد إعادة
    // فتح الشاشة تُسقط المصنع القديم بصمت.
    _viewType = 'native-chat-input-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final area = html.TextAreaElement()
        ..value = widget.controller.text
        ..placeholder = widget.hint
        ..dir = 'rtl'
        ..rows = 1;
      area.style
        ..width = '100%'
        ..height = '100%'
        ..resize = 'none'
        ..border = 'none'
        ..outline = 'none'
        ..background = 'transparent'
        ..fontSize = '16px' // أقل من 16px يجعل iOS يقرّب الصفحة عند التركيز
        ..fontFamily = 'inherit'
        ..lineHeight = '24px'
        ..padding = '12px 16px'
        ..boxSizing = 'border-box';
      area.onInput.listen((_) {
        final v = area.value ?? '';
        if (widget.controller.text != v) widget.controller.text = v;
      });
      area.onKeyDown.listen((e) {
        if (e.key == 'Enter' && !(e.shiftKey)) {
          e.preventDefault();
          widget.onSubmitted();
        }
      });
      _area = area;
      return area;
    });
    widget.controller.addListener(_syncFromController);
  }

  void _syncFromController() {
    final area = _area;
    if (area != null && area.value != widget.controller.text) {
      area.value = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
