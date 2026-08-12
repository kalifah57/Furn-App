import '../../core/constants/app_strings.dart';

/// يعزل رقمًا لاتينيًّا اتجاهيًّا داخل نصٍّ عربي.
///
/// خوارزمية bidi تعيد ترتيب الأرقام والفواصل حين تجاور نصًّا يمينيًّا، فتُعرض
/// «1,800» كـ«800,1» (حادثة dogfood ١٢/٠٨). محرِفا العزل LRI (U+2066) …
/// PDI (U+2069) يجعلان الرقم وحدةً يسارية-يمينية مستقلّة عمّا حولها، فيبقى
/// ترتيبه سليمًا أينما وقع في الجملة — من مصدرٍ واحد، فيشفى كل موضعٍ يستدعيه.
String bidiIsolateNumber(String ltr) => '⁦$ltr⁩';

/// تنسيق مبلغ بالريال مع فواصل آلاف. مثال: 1800 → «⁦1,800⁩ ريال».
/// الرقم معزول اتجاهيًّا كي لا ينقلب داخل جملة عربية.
String formatSar(double amount) {
  final n = amount.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${bidiIsolateNumber(buf.toString())} ${AppStrings.sar}';
}

/// نسبة مئوية مختصرة، معزولة اتجاهيًّا كذلك. 0.42 → «⁦42%⁩».
String formatPercent(double fraction) =>
    bidiIsolateNumber('${(fraction * 100).round()}%');
