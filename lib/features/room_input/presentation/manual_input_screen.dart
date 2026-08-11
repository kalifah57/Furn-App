import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/input_options.dart';
import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/multi_select_chips.dart';
import '../../../shared/widgets/status_views.dart';
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

  String? _dimsError;
  String? _itemsError;

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _budget.dispose();
    super.dispose();
  }

  /// نموذجٌ فارغ كان يمرّ بعرض ٠ وطول ٠ ثم يعبر شاشتين ليعود المحرّك سائلًا عمّا
  /// كان أمام المستخدم. التحقّق يقع هنا: عند الحقل، قبل الترحيل.
  void _submit() {
    final w = double.tryParse(_width.text.trim()) ?? 0;
    final l = double.tryParse(_length.text.trim()) ?? 0;
    final dimsError = (w <= 0 || l <= 0)
        ? 'أدخل مقاس الغرفة بالمتر — رقمًا أكبر من صفر.'
        : null;
    final itemsError =
        _essential.isEmpty ? 'اختر قطعةً أساسية واحدة على الأقل.' : null;

    setState(() {
      _dimsError = dimsError;
      _itemsError = itemsError;
    });
    if (dimsError != null || itemsError != null) return;

    final draft = FurnishingProject(
      projectId: ref.read(uuidProvider).v4(),
      room: Room(
        widthM: w,
        lengthM: l,
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
    // النموذج مدفوعٌ فوق الهيكل، فالعودة إلى المحادثة تكفي: هي التي تعرض التفكير
    // وتقود ما بعده. الحارس للرابط العميق المباشر حيث لا شيء تحته.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.assistant);
    }
  }

  void _toggle(Set<String> set, String value, bool isSelected) =>
      setState(() => isSelected ? set.add(value) : set.remove(value));

  Widget _fieldError(String message) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          message,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.manualTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(AppStrings.roomType),
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
                Expanded(
                    child: AppNumberField(controller: _width, label: AppStrings.widthM)),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        AppNumberField(controller: _length, label: AppStrings.lengthM)),
              ],
            ),
            if (_dimsError != null) _fieldError(_dimsError!),
            const SizedBox(height: 12),
            AppNumberField(controller: _budget, label: AppStrings.budgetMax),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.budgetFlexible),
              value: _flexible,
              onChanged: (v) => setState(() => _flexible = v),
            ),
            const SectionHeader(AppStrings.preferredStyle),
            MultiSelectChips(
              options: styleOptions,
              selected: _styles,
              onToggle: (v, sel) => _toggle(_styles, v, sel),
            ),
            const SectionHeader(AppStrings.essentialItems),
            MultiSelectChips(
              options: itemTypeOptions,
              selected: _essential,
              onToggle: (v, sel) => _toggle(_essential, v, sel),
            ),
            if (_itemsError != null) _fieldError(_itemsError!),
            const SectionHeader(AppStrings.optionalItems),
            MultiSelectChips(
              options: itemTypeOptions,
              selected: _optional,
              onToggle: (v, sel) => _toggle(_optional, v, sel),
            ),
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
}
