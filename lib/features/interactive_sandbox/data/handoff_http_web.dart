// dart:html is intentional: this file is only compiled on web via the
// conditional export in handoff_http.dart.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// تنفيذ المتصفّح. الصفحة والـ API من نفس الأصل (الخادم المحلّي يخدم البناء
/// أيضًا)، فلا يوجد CORS ولا محتوى مختلط.
Future<String?> handoffGet(Uri url) async {
  try {
    return await html.HttpRequest.getString(url.toString());
  } on html.ProgressEvent {
    return null; // 404 = الجوال لم يكتب بعد
  }
}

Future<void> handoffPost(Uri url, String body) async {
  await html.HttpRequest.request(
    url.toString(),
    method: 'POST',
    requestHeaders: const {'Content-Type': 'application/json'},
    sendData: body,
  );
}
