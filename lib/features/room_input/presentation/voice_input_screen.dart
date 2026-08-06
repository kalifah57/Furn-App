import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import 'flow_controller.dart';

/// شاشة التسجيل الصوتي (تجريبية — تستخدم STT وهميًا في الـ MVP).
class VoiceInputScreen extends ConsumerWidget {
  const VoiceInputScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.voiceTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 64,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.mic,
                    size: 64, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Text(AppStrings.voiceHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.graphic_eq),
                label: const Text(AppStrings.startRecording),
                onPressed: () {
                  ref.read(furnishingFlowControllerProvider.notifier).runVoice();
                  context.go(Routes.assistantThinking);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
