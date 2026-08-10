// dart:html مقصود: هذا الملف لا يُترجم إلا على الويب عبر التصدير الشرطي في
// key_value_store.dart.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// `localStorage` قد يرمي لا أن يعيد null: وضع التصفّح الخاص في Safari يرفض
/// الكتابة (QuotaExceededError)، وبعض السياقات المضمّنة ترفض حتى القراءة.
/// فشل التخزين يجب ألّا يُسقط شاشة الخطة — أسوأ ما يحدث أن الخطة لا تُحفظ.
String? storeRead(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void storeWrite(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {
    // لا شيء نفعله: المستخدم يواصل العمل على خطته، بلا بقاء.
  }
}

void storeRemove(String key) {
  try {
    html.window.localStorage.remove(key);
  } catch (_) {
    // كما في الكتابة.
  }
}
