import 'package:flutter/material.dart';

/// نسخة بيئة الاختبار (VM): TextField عادي بنفس العقد — تبقى اختبارات
/// `enterText`/`find.byType(TextField)` صادقةً على منطق الشاشة، بينما يأخذ
/// الويب العنصر الأصلي من `native_text_field_web.dart`.
class NativeChatInput extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
