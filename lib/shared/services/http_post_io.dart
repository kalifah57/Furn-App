import 'dart:io';

/// تنفيذ الـ VM (والاختبارات).
Future<void> httpPostJson(Uri url, String body) async {
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
