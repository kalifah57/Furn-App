import 'package:flutter/material.dart';

/// صف FilterChips لاختيار متعدد من خريطة (label → value).
/// الأب يملك `selected` ويتعامل مع التبديل عبر [onToggle] (مثلًا داخل setState).
class MultiSelectChips extends StatelessWidget {
  const MultiSelectChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final Map<String, String> options;
  final Set<String> selected;
  final void Function(String value, bool isSelected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: options.entries.map((e) {
        return FilterChip(
          label: Text(e.key),
          selected: selected.contains(e.value),
          onSelected: (v) => onToggle(e.value, v),
        );
      }).toList(),
    );
  }
}
