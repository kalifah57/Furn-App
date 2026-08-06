/// تواقيع التخزين، منفصلة عن التنفيذ كي تُحقن في الاختبارات بلا متصفّح — نفس
/// فكرة `AnalyticsPost` في `http_analytics.dart`.
///
/// تعيش هنا لا داخل الملفّين الشرطيّين: تعريفها مرّتين هو الطريق المضمون إلى
/// توقيعين يفترقان بصمت بين الويب والـ VM.
typedef StoreRead = String? Function(String key);
typedef StoreWrite = void Function(String key, String value);
typedef StoreRemove = void Function(String key);
