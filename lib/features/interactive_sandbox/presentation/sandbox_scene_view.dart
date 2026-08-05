import 'package:flutter/material.dart';

import '../../../domain_engine/spatial/ar_spatial_engine.dart';
import '../../../domain_engine/spatial/placement_solver.dart';
import '../../../shared/models/models.dart';

/// **وصلة العارض (seam)** — كل ما تحتاجه أي تقنية عرض ثلاثي الأبعاد من التطبيق:
/// مشهد من [Placement] بمقاسات حقيقية، ونداء عند نقر المستخدم على مجسّم.
///
/// استبدال هذا المكوّن بـ `model_viewer_plus` أو غلاف ARKit لا يمسّ أي شيء آخر:
/// المواضع تأتي جاهزة من [PlacementSolver]، والاختيار يعود عبر [onTapItem].
/// لذلك لا تُضاف حزمة ثلاثية الأبعاد إلى `pubspec` قبل الحاجة — بناء الويب الذي
/// يُنشر منه التطبيق يبقى كما هو.
///
/// التنفيذ الحالي مسقط علوي **بمقياس حقيقي**: يرسم الغرفة والقطع بأبعادها
/// الفعلية ويدعم النقر لاختيار قطعة. هو ليس ثلاثي الأبعاد، لكنه ليس واجهة
/// صوريّة: نفس بيانات المشهد، ونفس حلقة التفاعل التي سيستخدمها العارض الحقيقي.
class SandboxSceneView extends StatelessWidget {
  const SandboxSceneView({
    super.key,
    required this.room,
    required this.placements,
    required this.onTapItem,
    this.selectedProductId,
  });

  final RoomSpace room;
  final List<Placement> placements;
  final ValueChanged<String?> onTapItem;
  final String? selectedProductId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = _SceneTransform(
          room: room,
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onTapItem(_hitTest(view, d.localPosition)),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ScenePainter(
              view: view,
              placements: placements,
              selectedProductId: selectedProductId,
              scheme: scheme,
            ),
          ),
        );
      },
    );
  }

  /// نظير الـ raycast في مستوى الأرضية: نحوّل نقطة اللمس إلى إحداثيات الغرفة
  /// ونأخذ أصغر قطعة تحتويها — فتُختار الأباجورة فوق السجادة لا السجادة.
  String? _hitTest(_SceneTransform view, Offset local) {
    final p = view.toRoom(local);
    final hits = placements
        .where((e) =>
            p.dx >= e.minX && p.dx <= e.maxX && p.dy >= e.minZ && p.dy <= e.maxZ)
        .toList()
      // ترتيب كلّي: المساحة ثم المعرّف — لا يعتمد على استقرار الفرز.
      ..sort((a, b) {
        final byArea = (a.spanXCm * a.spanZCm).compareTo(b.spanXCm * b.spanZCm);
        return byArea != 0
            ? byArea
            : a.product.productId.compareTo(b.product.productId);
      });
    return hits.isEmpty ? null : hits.first.product.productId;
  }
}

/// تحويل بين سنتيمترات الغرفة وبكسلات اللوحة — يحفظ النسبة ويوسّط المشهد.
class _SceneTransform {
  _SceneTransform({required this.room, required this.size})
      : scale = _scaleFor(room, size);

  static double _scaleFor(RoomSpace room, Size size) {
    if (!room.isMeasured) return 1.0;
    final sx = size.width / room.widthCm;
    final sz = size.height / room.lengthCm;
    return sx < sz ? sx : sz;
  }

  final RoomSpace room;
  final Size size;
  final double scale;

  Offset toCanvas(double xCm, double zCm) => Offset(
        size.width / 2 + xCm * scale,
        size.height / 2 + zCm * scale,
      );

  Offset toRoom(Offset canvas) => Offset(
        (canvas.dx - size.width / 2) / scale,
        (canvas.dy - size.height / 2) / scale,
      );

  Rect rectFor(Placement p) => Rect.fromLTRB(
        toCanvas(p.minX, p.minZ).dx,
        toCanvas(p.minX, p.minZ).dy,
        toCanvas(p.maxX, p.maxZ).dx,
        toCanvas(p.maxX, p.maxZ).dy,
      );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.view,
    required this.placements,
    required this.selectedProductId,
    required this.scheme,
  });

  final _SceneTransform view;
  final List<Placement> placements;
  final String? selectedProductId;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final room = view.room;
    if (!room.isMeasured) return;

    final floor = Rect.fromLTRB(
      view.toCanvas(-room.widthCm / 2, -room.lengthCm / 2).dx,
      view.toCanvas(-room.widthCm / 2, -room.lengthCm / 2).dy,
      view.toCanvas(room.widthCm / 2, room.lengthCm / 2).dx,
      view.toCanvas(room.widthCm / 2, room.lengthCm / 2).dy,
    );

    canvas.drawRect(floor, Paint()..color = scheme.surfaceContainerHighest);
    canvas.drawRect(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.outline,
    );

    // السجاد أولًا ليقع تحت الأثاث، ثم البقية بترتيب المشهد.
    final ordered = [
      ...placements.where((p) => p.product.category == RecommendationCategory.rug),
      ...placements.where((p) => p.product.category != RecommendationCategory.rug),
    ];

    for (final p in ordered) {
      final rect = view.rectFor(p);
      final isSelected = p.product.productId == selectedProductId;
      final mount = mountOf(p.product);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = switch (mount) {
            ArMount.ceiling => scheme.tertiaryContainer.withOpacity(0.55),
            ArMount.tabletop => scheme.secondaryContainer,
            ArMount.floor =>
              p.product.category == RecommendationCategory.rug
                  ? scheme.surfaceContainer
                  : scheme.primaryContainer,
          },
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3 : 1
          ..color = isSelected ? scheme.primary : scheme.outlineVariant,
      );

      _label(canvas, rect, p.product.title, isSelected);
    }
  }

  void _label(Canvas canvas, Rect rect, String text, bool selected) {
    if (rect.width < 44 || rect.height < 18) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 8);
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.placements != placements ||
      old.selectedProductId != selectedProductId ||
      old.view.scale != view.scale;
}
