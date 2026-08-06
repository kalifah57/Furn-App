/// تخزين محلّي بسيط و**متزامن** — `localStorage` في المتصفّح، وذاكرة العملية
/// على الـ VM والاختبارات. نفس نمط `http_post.dart` و`ar_launcher.dart`.
///
/// متزامن عن قصد: القراءة تقع داخل provider متزامن لحظة إقلاع شاشة الخطة، وجعلها
/// غير متزامنة كان سيفرض حالة تحميل إضافية على أهمّ شاشة في التطبيق مقابل لا شيء —
/// `localStorage` نفسه متزامن.
export 'key_value_store_io.dart'
    if (dart.library.html) 'key_value_store_web.dart';
