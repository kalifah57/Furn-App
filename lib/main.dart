import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // نقطة الدخول. الـ ProviderScope يفعّل الحقن (Riverpod) — ADR-0001 §4.
  //
  // لا نستبدل `analyticsProvider` هنا: اختيار الـ sink صار داخل المزوّد نفسه
  // (console في التطوير + إرسال حقيقي حين تُضبط ANALYTICS_ENDPOINT). استبداله
  // من هنا كان يُلغي الإرسال الحقيقي بصمت.
  runApp(const ProviderScope(child: FurnApp()));
}
