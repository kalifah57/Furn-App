import 'package:flutter/material.dart';

import '../../shared/models/models.dart';
import '../../shared/utils/formatters.dart';
import '../ar/ar_button.dart';

/// ألوان تقريبية للوسوم الإنجليزية الشائعة (لعرض عيّنات اللون على البطاقة).
const _swatch = <String, Color>{
  'white': Color(0xFFF5F5F5), 'black': Color(0xFF2A2A2A),
  'gray': Color(0xFF9E9E9E), 'grey': Color(0xFF9E9E9E),
  'beige': Color(0xFFE4D5B7), 'brown': Color(0xFF8B5E3C),
  'blue': Color(0xFF3F6FB0), 'green': Color(0xFF4C8C4A),
  'red': Color(0xFFC0392B), 'yellow': Color(0xFFE6C200),
  'silver': Color(0xFFC0C0C0), 'gold': Color(0xFFC9A227),
  'walnut': Color(0xFF5B3A29), 'oak': Color(0xFFC8A165),
  'natural': Color(0xFFD8C3A5),
};

const _colorAr = <String, String>{
  'white': 'أبيض', 'black': 'أسود', 'gray': 'رمادي', 'grey': 'رمادي',
  'beige': 'بيج', 'brown': 'بنّي', 'blue': 'أزرق', 'green': 'أخضر',
  'red': 'أحمر', 'yellow': 'أصفر', 'silver': 'فضّي', 'gold': 'ذهبي',
  'walnut': 'جوزي', 'oak': 'بلوطي', 'natural': 'طبيعي',
};

const _materialAr = <String, String>{
  'wood': 'خشب', 'fabric': 'قماش', 'leather': 'جلد', 'metal': 'معدن',
  'glass': 'زجاج', 'plastic': 'بلاستيك', 'velvet': 'مخمل', 'rattan': 'خيزران',
};

/// بطاقة «خيار» غنيّة بالتفاصيل — الجوهر الذي طلبه المستخدم: خيارات حقيقية
/// يقارنها ويجرّبها. تعرض: المتجر/العلامة، السعر، الأبعاد الثلاثة مع فحص
/// «هل تناسب غرفتك؟»، الألوان كعيّنات، الخامات، التقييم، زر الواقع المعزّز،
/// ورابط المتجر متى توفّر — ثم «اختر هذا الخيار».
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.product,
    required this.room,
    this.isCurrent = false,
    this.onSelect,
  });

  final CatalogProduct product;
  final Room room;
  final bool isCurrent;
  final VoidCallback? onSelect;

  bool? _fitsRoom() {
    final rw = room.widthM * 100, rl = room.lengthM * 100;
    if (rw <= 0 || rl <= 0) return null;
    final w = product.widthCm, d = product.depthCm;
    if (w <= 0 || d <= 0) return null;
    return (w <= rw && d <= rl) || (d <= rw && w <= rl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fits = _fitsRoom();
    final dims = (product.widthCm > 0 && product.depthCm > 0)
        ? '${_n(product.widthCm)}×${_n(product.depthCm)}×${_n(product.heightCm)} سم'
        : null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(product.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Text(formatSar(product.price),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
            ]),
            if (product.brand.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.storefront_outlined,
                    size: 15, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(product.brand,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  _tag(theme, 'الخيار الحالي'),
                ],
              ]),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (dims != null) _spec(theme, Icons.straighten, dims),
              if (fits != null)
                _spec(
                  theme,
                  fits ? Icons.check_circle : Icons.error_outline,
                  fits ? 'تناسب غرفتك' : 'أكبر من مساحتك',
                  color: fits ? Colors.green.shade700 : theme.colorScheme.error,
                ),
              if (product.ratingOptional != null)
                _spec(theme, Icons.star,
                    product.ratingOptional!.toStringAsFixed(1),
                    color: Colors.amber.shade800),
              if (!product.isAvailable)
                _spec(theme, Icons.inventory_2_outlined, 'غير متوفّرة الآن',
                    color: theme.colorScheme.error),
            ]),
            if (product.colorTags.isNotEmpty || product.materialTags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                for (final c in product.colorTags.take(4)) ...[
                  _dot(c),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    [
                      if (product.colorTags.isNotEmpty)
                        _arList(product.colorTags, _colorAr),
                      if (product.materialTags.isNotEmpty)
                        _arList(product.materialTags, _materialAr),
                    ].join('  •  '),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ]),
            ],
            const Divider(height: 20),
            Row(children: [
              ArButton(product: product),
              const Spacer(),
              if (onSelect != null && !isCurrent)
                FilledButton.tonalIcon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('اختر هذا'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  static String _n(double v) => v.toStringAsFixed(0);

  static String _arList(List<String> tags, Map<String, String> map) =>
      tags.map((t) => map[t.toLowerCase()] ?? t).join('، ');

  Widget _dot(String tag) {
    final color = _swatch[tag.toLowerCase()] ?? const Color(0xFFBDBDBD);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
    );
  }

  Widget _spec(ThemeData theme, IconData icon, String label, {Color? color}) {
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c)),
      ]),
    );
  }

  Widget _tag(ThemeData theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.primary)),
      );
}
