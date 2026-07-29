import '../../core/constants/app_strings.dart';

/// تنسيق مبلغ بالريال مع فواصل آلاف. مثال: 1800 → "1,800 ريال".
String formatSar(double amount) {
  final n = amount.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '$buf ${AppStrings.sar}';
}

/// نسبة مئوية مختصرة. 0.42 → "42%".
String formatPercent(double fraction) => '${(fraction * 100).round()}%';
