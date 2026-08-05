import 'dart:convert';
import 'dart:io';

/// تنفيذ الـ VM (والاختبارات). يعيد `null` عند 404 = لا جلسة بعد.
Future<String?> handoffGet(Uri url) async {
  final client = HttpClient();
  try {
    final response = await client.getUrl(url).then((r) => r.close());
    if (response.statusCode == HttpStatus.notFound) return null;
    return response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

Future<void> handoffPost(Uri url, String body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(url);
    request.headers.contentType = ContentType.json;
    request.write(body);
    await request.close();
  } finally {
    client.close(force: true);
  }
}
