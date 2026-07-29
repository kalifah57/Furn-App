/// توحيد أولي للنص قبل الاستخراج (ai_pipeline.md §2 — Input Normalization).
/// تنظيف المسافات وتوحيد بعض الوحدات الشائعة. (توحيد الأرقام يتم داخل مستخرِج الـ AI.)
String normalizeInput(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  // توحيد وحدات شائعة إلى صيغة موحّدة.
  s = s.replaceAll(RegExp(r'\bمتر مربع\b'), 'م²');
  s = s.replaceAll(RegExp(r'\bمتر\b'), 'م');
  s = s.replaceAll(RegExp(r'\bسنتيمتر\b|\bسم\b'), 'سم');
  s = s.replaceAll('ر.س', 'ريال');
  return s;
}
