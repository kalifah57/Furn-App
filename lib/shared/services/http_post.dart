/// إرسال HTTP آمن على المنصّتين — نفس نمط `ar_launcher.dart`:
/// `dart:html` في المتصفّح، و`dart:io` على الـ VM والاختبارات.
export 'http_post_io.dart' if (dart.library.html) 'http_post_web.dart';
