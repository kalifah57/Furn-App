import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics.dart';
import '../../core/di/providers.dart';
import '../../shared/models/models.dart';
import 'ar_launcher.dart';

/// أسماء ألوان عربية للوسم الإنجليزي الشائع (لعرض «اللون» في معاينة AR).
const _colorAr = <String, String>{
  'white': 'أبيض', 'black': 'أسود', 'gray': 'رمادي', 'grey': 'رمادي',
  'beige': 'بيج', 'brown': 'بنّي', 'blue': 'أزرق', 'green': 'أخضر',
  'red': 'أحمر', 'yellow': 'أصفر', 'silver': 'فضّي', 'gold': 'ذهبي',
  'walnut': 'جوزي', 'oak': 'بلوطي', 'natural': 'طبيعي',
};

String? _arColor(List<String> tags) {
  if (tags.isEmpty) return null;
  final t = tags.first.toLowerCase();
  return _colorAr[t] ?? tags.first;
}

/// زر «شاهدها في غرفتك» — يظهر فقط للمنتجات التي لها نموذج ثلاثي الأبعاد جاهز.
/// يفتح معاينة الواقع المعزّز (ar.html) بمقاس القطعة الحقيقي ولونها.
class ArButton extends ConsumerWidget {
  const ArButton({super.key, required this.product});

  final CatalogProduct? product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    if (p == null || !p.hasArModel) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () {
        ref.read(analyticsProvider).track(ArOpened(p.productId));
        openArView(
          glbUrl: p.modelGlbUrl,
          usdzUrl: p.modelUsdzUrl,
          title: p.title,
          widthCm: p.widthCm,
          depthCm: p.depthCm,
          heightCm: p.heightCm,
          color: _arColor(p.colorTags),
        );
      },
      icon: const Icon(Icons.view_in_ar, size: 18),
      label: const Text('شاهدها في غرفتك'),
    );
  }
}

/// زر تجربة الواقع المعزّز بنموذج جاهز (افتراضيًا الطاولة الحقيقية بمقاسها).
/// يفتح الكاميرا مباشرة دون الحاجة لعنصر منتج مُختار.
class ArDemoButton extends ConsumerWidget {
  const ArDemoButton({
    super.key,
    this.label = 'شاهدها في غرفتك',
    this.glbUrl = kDemoTableGlb,
    this.usdzUrl = '',
    this.title = 'طاولة قهوة خشبية',
    this.widthCm = 110,
    this.depthCm = 60,
    this.heightCm = 45,
    this.color = 'walnut',
  });

  final String label;
  final String glbUrl;
  final String usdzUrl;
  final String title;
  final double? widthCm;
  final double? depthCm;
  final double? heightCm;
  final String? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: () {
        ref.read(analyticsProvider).track(const ArOpened('demo'));
        openArView(
          glbUrl: glbUrl,
          usdzUrl: usdzUrl,
          title: title,
          widthCm: widthCm,
          depthCm: depthCm,
          heightCm: heightCm,
          color: color != null ? _colorAr[color!] ?? color : null,
        );
      },
      icon: const Icon(Icons.view_in_ar, size: 18),
      label: Text(label),
    );
  }
}

/// النموذج الحقيقي المولّد بمقاسه (tools/generate_furniture_glb.py) — يُخدَم من
/// نفس النشر على GitHub Pages؛ المسار نسبي ليُحَل مقابل `<base href>`.
const kDemoTableGlb = 'models/coffee_table_walnut.glb';
