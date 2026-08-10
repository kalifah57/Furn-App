// dart:html is intentional and safe here: this file is only ever compiled on
// web (selected via the conditional import in ar_launcher.dart); on the VM the
// stub is used instead. The lint is a false positive for that pattern.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// ينفّذ فتح ar.html في تبويب جديد بمعطيات المنتج (تنفيذ الويب).
///
/// نحلّ المسار مقابل `document.baseUri` (الذي يعكس `<base href>` = /Furn-App/)
/// حتى يعمل الرابط بصرف النظر عن استراتيجية توجيه Flutter (hash أو path).
void openArView({
  required String glbUrl,
  required String usdzUrl,
  required String title,
  double? widthCm,
  double? depthCm,
  double? heightCm,
  String? color,
}) {
  String? cm(double? v) => (v != null && v > 0) ? v.toStringAsFixed(0) : null;

  final params = <String, String>{
    if (glbUrl.isNotEmpty) 'glb': glbUrl,
    if (usdzUrl.isNotEmpty) 'usdz': usdzUrl,
    if (title.isNotEmpty) 'title': title,
    if (cm(widthCm) != null) 'w': cm(widthCm)!,
    if (cm(depthCm) != null) 'd': cm(depthCm)!,
    if (cm(heightCm) != null) 'h': cm(heightCm)!,
    if (color != null && color.isNotEmpty) 'color': color,
  };

  final base = html.document.baseUri ?? html.window.location.href;
  final target = Uri.parse(base).resolve('ar.html').replace(queryParameters: params);

  // Opened from a button tap (a user gesture), so this is not popup-blocked.
  html.window.open(target.toString(), '_blank');
}
