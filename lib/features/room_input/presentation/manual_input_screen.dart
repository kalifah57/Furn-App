import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/models.dart';
import 'flow_controller.dart';

/// نموذج الإدخال اليدوي المنظّم — المسار الأساسي (بلا استدعاء LLM).
class ManualInputScreen extends ConsumerStatefulWidget {
  const ManualInputScreen({super.key});

  @override
  ConsumerState<ManualInputScreen> createState() => _ManualInputScreenState();
}

class _ManualInputScreenState extends ConsumerState<ManualInputScreen> {
  final _width = TextEditingController();
  final _length = TextEditingController();
  final _budget = TextEditingController();

  RoomType _roomType = RoomType.bedroom;
  bool _flexible = false;
  final _styles = <String>{};
  final _essential = <String>{};
  final _optional = <String>{};

  static const _styleOptions = {'مودرن': 'modern', 'مينمال': 'minimal', 'كلاسيك': 'classic'};
  static const _itemOptions = {
    'سرير': 'bed',
    'كنب/كرسي': 'sofa',
    'تخزين': 'storage',
    'طاولة': 'table',
    'إضاءة': 'lamp',
    'سجادة': 'rug',
  };

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _submit() {
    final draft = FurnishingProject(
      projectId: ref.read(uuidProvider).v4(),
      room: Room(
        widthM: double.tryParse(_width.text.trim()) ?? 0,
        lengthM: double.tryParse(_length.text.trim()) ?? 0,
        roomType: _roomType,
      ),
      budget: Budget(
        maxTotal: double.tryParse(_budget.text.trim()) ?? 0,
        flexible: _flexible,
      ),
      style: StylePreferences(preferred: _styles.toList()),
      items: RequestedItems(
        essential:
            _essential.map((t) => RequestedItem(type: t)).toList(growable: false),
        optional:
            _optional.map((t) => RequestedItem(type: t)).toList(growable: false),
      ),
    );
    ref.read(furnishingFlowControllerProvider.notifier).submitManualDraft(draft);
    context.go(Routes.analysis);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.manualTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label(AppStrings.roomType),
            DropdownButtonFormField<RoomType>(
              value: _roomType,
              items: RoomType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.arabicLabel)))
                  .toList(),
              onChanged: (v) => setState(() => _roomType = v ?? RoomType.other),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numberField(_width, AppStrings.widthM)),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_length, AppStrings.lengthM)),
              ],
            ),
            const SizedBox(height: 12),
            _numberField(_budget, AppStrings.budgetMax),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.budgetFlexible),
              value: _flexible,
              onChanged: (v) => setState(() => _flexible = v),
            ),
            _label(AppStrings.preferredStyle),
            _chips(_styleOptions, _styles),
            _label(AppStrings.essentialItems),
            _chips(_itemOptions, _essential),
            _label(AppStrings.optionalItems),
            _chips(_itemOptions, _optional),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Text(AppStrings.analyzeRequest),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _numberField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label),
      );

  Widget _chips(Map<String, String> options, Set<String> selected) => Wrap(
        spacing: 8,
        children: options.entries.map((e) {
          final isSel = selected.contains(e.value);
          return FilterChip(
            label: Text(e.key),
            selected: isSel,
            onSelected: (v) => setState(() {
              v ? selected.add(e.value) : selected.remove(e.value);
            }),
          );
        }).toList(),
      );
}
