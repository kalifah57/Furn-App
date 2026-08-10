/// تنفيذ الـ VM (والاختبارات): ذاكرة العملية.
///
/// لا يوجد بناء VM للمستخدمين — التطبيق ويب — فدور هذا الملف أن تبقى الشيفرة
/// قابلة للترجمة وأن تعمل الاختبارات بلا متصفّح. لا يُقصد به بقاء حقيقي.
final Map<String, String> _memory = {};

String? storeRead(String key) => _memory[key];

void storeWrite(String key, String value) => _memory[key] = value;

void storeRemove(String key) => _memory.remove(key);
