import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics/analytics.dart';
import 'app/app.dart';
import 'core/di/providers.dart';

void main() {
  // نقطة الدخول. الـ ProviderScope يفعّل الحقن (Riverpod) — ADR-0001 §4.
  // لتفعيل التنفيذات الحقيقية لاحقًا: مرّر overrides هنا دون تغيير الشاشات.
  //
  // نختار sink القياس هنا (خطوة «اختيار الـ sink»): DebugAnalytics يطبع أحداث
  // قِمع الثقة في وحدة تحكّم المتصفّح لتكون قابلة للملاحظة. الإنتاج يستبدله
  // بـ RemoteAnalytics عبر نفس السطر دون لمس أي شاشة.
  runApp(
    ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(DebugAnalytics()),
      ],
      child: const FurnApp(),
    ),
  );
}
