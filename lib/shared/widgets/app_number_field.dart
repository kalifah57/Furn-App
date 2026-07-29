import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// حقل إدخال رقمي موحّد (يقبل الأرقام والفاصلة العشرية).
/// يستبدل التكرار بين شاشتي الإدخال اليدوي والتحليل.
class AppNumberField extends StatelessWidget {
  const AppNumberField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(labelText: label),
    );
  }
}
