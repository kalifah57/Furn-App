import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // نقطة الدخول. الـ ProviderScope يفعّل الحقن (Riverpod) — ADR-0001 §4.
  //
  // لا نستبدل `analyticsProvider` هنا: اختيار الـ sink صار داخل المزوّد نفسه
  // (console في التطوير + إرسال حقيقي حين تُضبط ANALYTICS_ENDPOINT). استبداله
  // من هنا كان يُلغي الإرسال الحقيقي بصمت.
  //
  // على الويب يترك Flutter قوائم النص لقائمة المتصفح — التي لا تظهر أصلًا فوق
  // حقولٍ مرسومة على متصفحات الجوال، فيصير «لصق» مستحيلًا (حادثة dogfood
  // حقيقية). نعطّل قائمة المتصفح ليعرض Flutter قائمته (نسخ/لصق/تحديد الكل)
  // بالضغط المطوّل في كل حقول التطبيق.
  if (kIsWeb) {
    WidgetsFlutterBinding.ensureInitialized();
    BrowserContextMenu.disableContextMenu();
  }
  runApp(const ProviderScope(child: FurnApp()));
}
