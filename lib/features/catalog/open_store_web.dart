// dart:html مقصود وآمن هنا: هذا الملف لا يُترجَم إلا على الويب (عبر الاستيراد
// الشرطي في open_store.dart)؛ على الـVM يُستعمل الجذع.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// يفتح رابط المتجر في تبويب جديد. `noopener,noreferrer` يمنع الصفحة المفتوحة
/// من الوصول إلى نافذتنا (حماية من reverse tabnabbing).
void openStore(String url) {
  html.window.open(url, '_blank', 'noopener,noreferrer');
}
