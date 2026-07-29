import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // نقطة الدخول. الـ ProviderScope يفعّل الحقن (Riverpod) — ADR-0001 §4.
  // لتفعيل التنفيذات الحقيقية لاحقًا: مرّر overrides هنا دون تغيير الشاشات.
  runApp(const ProviderScope(child: FurnApp()));
}
