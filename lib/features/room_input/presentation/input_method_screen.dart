import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';

/// شاشة اختيار طريقة الإدخال (صوت/صور/يدوي).
class InputMethodScreen extends StatelessWidget {
  const InputMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.chooseInputMethod)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MethodCard(
              icon: Icons.edit_note,
              title: AppStrings.inputManual,
              subtitle: AppStrings.inputManualSub,
              recommended: true,
              onTap: () => context.go(Routes.assistantManual),
            ),
            _MethodCard(
              icon: Icons.mic_none,
              title: AppStrings.inputVoice,
              subtitle: AppStrings.inputVoiceSub,
              onTap: () => context.go(Routes.assistantVoice),
            ),
            _MethodCard(
              icon: Icons.add_a_photo_outlined,
              title: AppStrings.inputImage,
              subtitle: AppStrings.inputImageSub,
              onTap: () => context.go(Routes.assistantPhoto),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.recommended = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('موصى'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: theme.colorScheme.secondaryContainer,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}
