import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../analytics/analytics.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';

/// شاشة البداية (onboarding عربي — ضمن الـ MVP).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.chair_alt_outlined,
                  size: 88, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(AppStrings.appTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(AppStrings.appTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 32),
              ...AppStrings.onboardingPoints.map(
                (p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Text(p, style: theme.textTheme.bodyLarge)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  ref.read(analyticsProvider).track(const FlowStarted('onboarding'));
                  await ref.read(authRepositoryProvider).signInAnonymously();
                  if (context.mounted) context.go(Routes.inputMethod);
                },
                child: const Text(AppStrings.onboardingStart),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(Routes.saved),
                child: const Text(AppStrings.onboardingSaved),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(analyticsProvider).track(const FlowStarted('plan-demo'));
                  context.go(Routes.plan);
                },
                icon: const Icon(Icons.tune),
                label: const Text('جرّب مساحة الخطة (تجريبي)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
