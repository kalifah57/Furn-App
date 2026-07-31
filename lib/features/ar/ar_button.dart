import 'package:flutter/material.dart';

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
class ArButton extends StatelessWidget {
  const ArButton({super.key, required this.product});

  final CatalogProduct? product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    if (p == null || !p.hasArModel) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => openArView(
        glbUrl: p.modelGlbUrl,
        usdzUrl: p.modelUsdzUrl,
        title: p.title,
        widthCm: p.widthCm,
        depthCm: p.depthCm,
        heightCm: p.heightCm,
        color: _arColor(p.colorTags),
      ),
      icon: const Icon(Icons.view_in_ar, size: 18),
      label: const Text('شاهدها في غرفتك'),
    );
  }
}

/// زر تجربة الواقع المعزّز بنموذج تجريبي عام (لا يتطلّب بيانات منتج).
/// يثبت أن الكاميرا + الوضع بمقاس حقيقي يعملان قبل توفّر نماذج المنتجات.
class ArDemoButton extends StatelessWidget {
  const ArDemoButton({super.key, this.label = 'جرّب الواقع المعزّز الآن'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () =>
          openArView(glbUrl: '', usdzUrl: '', title: 'نموذج تجريبي'),
      icon: const Icon(Icons.view_in_ar, size: 18),
      label: Text(label),
    );
  }
}
