/// يفتح معاينة الواقع المعزّز (ar.html) بمعطيات المنتج.
///
/// AR ميزة خاصة بالويب في هذا التطبيق. نستخدم استيرادًا شرطيًا:
/// - على الويب: تنفيذ فعلي عبر `dart:html` ([ar_launcher_web.dart]).
/// - على الـ VM/الاختبارات: عملية لا-شيء ([ar_launcher_stub.dart])، فلا يكسر
///   `flutter test` (لا يوجد `dart:html` هناك).
export 'ar_launcher_stub.dart' if (dart.library.html) 'ar_launcher_web.dart';
