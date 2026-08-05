/// نقل HTTP آمن على المنصّتين — نفس نمط `ar_launcher.dart`:
/// - الويب: `dart:html` (الوحيد المتاح داخل المتصفّح).
/// - الـ VM/الاختبارات: `dart:io`، فلا ينكسر `flutter test`.
export 'handoff_http_io.dart' if (dart.library.html) 'handoff_http_web.dart';
