// dart:html مقصود: هذا الملف لا يُصرَّف إلا على الويب عبر التصدير الشرطي.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// تنفيذ المتصفّح.
Future<void> httpPostJson(Uri url, String body) async {
  await html.HttpRequest.request(
    url.toString(),
    method: 'POST',
    requestHeaders: const {'Content-Type': 'application/json'},
    sendData: body,
  );
}
