/// يفتح رابط المنتج في المتجر — نفس نمط `ar_launcher`: تنفيذ ويب حقيقي عبر
/// `dart:html`، ولا-شيء على الـVM/الاختبارات (فلا يكسر `flutter test`).
export 'open_store_stub.dart' if (dart.library.html) 'open_store_web.dart';
