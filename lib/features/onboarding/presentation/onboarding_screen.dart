import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../analytics/analytics.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/di/providers.dart';
import '../../../core/errors/result.dart';
import '../../../core/router/app_router.dart';
import '../../consent/presentation/consent_banner.dart';

/// شاشة البداية (onboarding عربي — ضمن الـ MVP).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// الدخول المجهول غير متزامن — وكان يجري خلف زرٍّ حيّ بلا أثر مرئي: نافذةٌ
  /// صامتة يستطيع فيها المستخدم أن يبدأ دخولين.
  bool _signingIn = false;

  Future<void> _start() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    ref.read(analyticsProvider).track(const FlowStarted('onboarding'));

    final result = await ref.read(authRepositoryProvider).signInAnonymously();
    if (!mounted) return;

    // العقد يسمح بالفشل، وكانت النتيجة تُهمَل فيُرحَّل المستخدم على أي حال.
    // المحاكاة لا تفشل اليوم، لكن مزوّدًا حقيقيًّا بلا شبكة يفشل — وصمتُ الفشل
    // أسوأ من الفشل.
    switch (result) {
      case Ok():
        context.go(Routes.assistant);
      case Err(:final failure):
        setState(() => _signingIn = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ConsentBanner(),
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
                onPressed: _signingIn ? null : _start,
                child: _signingIn
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text(AppStrings.onboardingStart),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(Routes.roomSaved),
                child: const Text(AppStrings.onboardingSaved),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(analyticsProvider).track(const FlowStarted('sample_plan'));
                  context.go(Routes.room);
                },
                icon: const Icon(Icons.tune),
                label: const Text('شاهد نموذج خطة جاهزة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
