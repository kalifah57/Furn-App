import '../../shared/models/models.dart';

/// محرّك قواعد العمل الحتمي (ai_pipeline.md §5 / engineering_standards.md).
///
/// مسؤول عن: التحقق من سلامة القيم، رفض الأبعاد غير المنطقية، تحديد نقص
/// البيانات، توليد أسئلة المتابعة، وضبط درجة الثقة — **بلا أي استدعاء AI**.
/// يعمل على نموذج مُستخرَج ويُعيد نموذجًا مُحدّثًا (analysis + next_actions).
class BusinessRulesEngine {
  const BusinessRulesEngine();

  // حدود منطقية للأبعاد (بالمتر).
  static const double minRoomSide = 1.0;
  static const double maxRoomSide = 30.0;
  static const double minCeiling = 2.0;
  static const double maxCeiling = 6.0;

  /// عتبة الثقة التي تحت مقدارها نطلب متابعة (G7 — قابلة للضبط).
  static const double confidenceThreshold = 0.6;

  FurnishingProject apply(FurnishingProject project) {
    final missing = <String>{...project.analysis.missingInformation};
    final warnings = <String>{...project.analysis.warnings};
    final followUps = <String>[];

    final room = project.room;

    // 1) الأبعاد.
    final hasWidth = room.widthM > 0;
    final hasLength = room.lengthM > 0;
    if (!hasWidth || !hasLength) {
      missing.add('أبعاد الغرفة (العرض والطول)');
      followUps.add('كم عرض وطول الغرفة تقريبًا بالمتر؟');
    } else {
      if (_outOfRange(room.widthM, minRoomSide, maxRoomSide) ||
          _outOfRange(room.lengthM, minRoomSide, maxRoomSide)) {
        warnings.add('أبعاد الغرفة تبدو غير منطقية؛ يُرجى التأكد منها.');
      }
    }
    if (room.heightM > 0 && _outOfRange(room.heightM, minCeiling, maxCeiling)) {
      warnings.add('ارتفاع السقف يبدو غير معتاد؛ يُرجى التأكد.');
    }

    // 2) الميزانية.
    if (!project.budget.hasBudget) {
      missing.add('سقف الميزانية');
      followUps.add('ما سقف ميزانيتك التقريبي بالريال؟');
    }

    // 3) العناصر الأساسية.
    if (project.items.essential.isEmpty) {
      missing.add('العناصر الأساسية المطلوبة');
      followUps.add('ما القطع الأساسية التي تريدها (مثل: سرير، كنب، تخزين)؟');
    }

    // 4) النمط (غير حرِج — يُسأل فقط عند غياب كل التفضيلات).
    if (project.style.preferred.isEmpty && project.style.colors.isEmpty) {
      followUps.add('هل لديك نمط مفضّل (مودرن، كلاسيك، مينمال) أو ألوان محددة؟');
    }

    // 5) تعارض مبدئي بين الميزانية والمتطلبات (heuristic حتمي).
    if (project.budget.hasBudget && project.items.essential.isNotEmpty) {
      final essentialCount = project.items.essential
          .fold<int>(0, (sum, e) => sum + e.quantity.clamp(1, 99));
      final perItemFloor = project.budget.maxTotal / essentialCount;
      if (perItemFloor < _minReasonablePerItem) {
        warnings.add(
            'قد لا تكفي الميزانية لكل العناصر الأساسية؛ سنعرض بدائل أو نطلب ترتيب الأولويات.');
      }
    }

    // 6) درجة الثقة النهائية + قرار طلب صور.
    var confidence = project.analysis.confidenceScore;
    if (missing.isNotEmpty) {
      confidence = (confidence - 0.15 * missing.length).clamp(0.0, 1.0);
    }
    final askForImages = !hasWidth || !hasLength;

    final needsFollowUp =
        missing.isNotEmpty || confidence < confidenceThreshold;

    return project.copyWith(
      analysis: project.analysis.copyWith(
        missingInformation: missing.toList(),
        warnings: warnings.toList(),
        confidenceScore: confidence,
      ),
      nextActions: NextActions(
        askForImages: askForImages,
        followUpQuestions: needsFollowUp ? followUps : const [],
      ),
    );
  }

  static const double _minReasonablePerItem = 150; // ريال (تقديري للـ MVP).

  bool _outOfRange(double v, double lo, double hi) => v < lo || v > hi;
}
