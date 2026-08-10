import '../../shared/models/models.dart';
import 'unmet_need.dart';

/// The confidence loop's core objects (pure Dart · no Flutter).
/// A [Plan] is the product: a living, ownable artifact the user shapes and
/// comes to trust. The engine's recommendation is only its seed.

enum PlanItemStatus { suggested, pinned }

/// One line in the plan. Wraps a [RecommendedItem] with the user's stance.
class PlanItem {
  const PlanItem({required this.item, this.status = PlanItemStatus.suggested});

  final RecommendedItem item;
  final PlanItemStatus status;

  bool get isPinned => status == PlanItemStatus.pinned;
}

/// The four objective guarantees behind the plan — the "no embarrassing
/// mistake" assurance that manufactures trust in the tool.
class Assurances {
  const Assurances({
    required this.fitsRoom,
    required this.withinBudget,
    required this.allAvailable,
    required this.essentialsComplete,
  });

  final bool fitsRoom;
  final bool withinBudget;
  final bool allAvailable;
  final bool essentialsComplete;

  bool get allGood =>
      fitsRoom && withinBudget && allAvailable && essentialsComplete;
}

/// فجوة ثقة واحدة: نقصٌ **غير مسدود** يخفض الثقة، ونقاطه الحقيقية، والخطوات
/// الملموسة التي تسدّه.
///
/// الثقة مركّبة شفّافة (لا عدّاد مزيّف)، فكل فجوة هنا تقابل مكوّنًا واحدًا لم
/// يتحقّق بعد — و[points] هي بالضبط ما يكسبه المستخدم بسدّها، لا وعدًا معمّمًا.
/// الفجوات المتحقّقة لا تُدرَج: لا نطلب من المستخدم فعل ما هو مفعول.
class ConfidenceGap {
  const ConfidenceGap({
    required this.label,
    required this.points,
    required this.actions,
  });

  /// عنوان الفجوة («أكمل الأساسيات»، «ادخل ضمن الميزانية»).
  final String label;

  /// كم يرفع سدُّها الثقة (0..100).
  final int points;

  /// خطوات ملموسة تسدّها («أضِف سرير»، «بدّل الأريكة — أكبر من غرفتك»).
  final List<String> actions;
}

/// بديلٌ مقترح لقطعة في الخطة — أعلى نقاطًا في خانته ضمن الميزانية والمقاس —
/// مع **سبب تفضيله وما يُفقده** مقارنةً بالقطعة الحالية، كي تكون المقارنة قرارًا
/// لا قائمة. لا صفحة مقارنة منفصلة: هذا يُعرض في المكان ويُحدِّث الخطة فورًا.
class ReplacementOption {
  const ReplacementOption({
    required this.product,
    this.pros = const [],
    this.cons = const [],
  });

  final CatalogProduct product;

  /// إيجابيات مقابل القطعة الحالية («أوفر بـ ٢٠٠ ريال»، «تقييم أعلى»).
  final List<String> pros;

  /// سلبيات مقابل الحالية («أغلى بـ ١٥٠ ريال»، «تقييم أقل»).
  final List<String> cons;
}

/// A snapshot of the plan the user is shaping.
class Plan {
  const Plan({
    required this.items,
    required this.total,
    required this.assurances,
    required this.confidence,
    required this.missingCategories,
    this.isFinalized = false,
    this.unmetNeeds = const [],
    this.effectiveBudgetSar,
    this.confidenceGaps = const [],
  });

  final List<PlanItem> items;
  final double total;
  final Assurances assurances;

  /// 0..100 — a transparent composite, never a fake meter (see PlanWorkspace).
  final int confidence;

  /// Requested essentials not yet covered — the "nothing forgotten" checklist.
  final List<RecommendationCategory> missingCategories;

  final bool isFinalized;

  /// ما طلبه المستخدم ولم نستطع تلبيته — معلنًا لا مسكوتًا عنه.
  final List<UnmetNeed> unmetNeeds;

  /// الميزانية بعد حجز ما هو خارج نطاقنا. `null` = لا حجز.
  ///
  /// زبون بـ3000 يطلب ثلاجة يجب أن تُبنى خطته على ما يبقى، لا على 3000 —
  /// وإلا اشترى أثاثًا لا تبقى معه سيولة لما يحتاجه فعلًا.
  final double? effectiveBudgetSar;

  /// **ماذا يفعل ليرفع ثقته** — الفجوات غير المسدودة مرتّبة بالأثر (الأكبر أوّلًا).
  /// فارغة ⇒ الخطة مكتملة الثقة. تجعل العدّاد قابلًا للتنفيذ لا رقمًا صمّاء.
  final List<ConfidenceGap> confidenceGaps;

  /// المحجوز إجمالًا لما هو خارج النطاق.
  double get reservedSar =>
      unmetNeeds.fold<double>(0, (s, u) => s + u.reserveSar);

  bool get hasUnmetNeeds => unmetNeeds.isNotEmpty;

  int get itemCount => items.length;
  int get pinnedCount => items.where((e) => e.isPinned).length;
}

/// The difference between two plan snapshots — powers "compare versions" and
/// the plain-language "what changed" line after every edit.
class PlanDiff {
  const PlanDiff({
    required this.added,
    required this.removed,
    required this.deltaTotal,
  });

  final List<RecommendedItem> added;
  final List<RecommendedItem> removed;
  final double deltaTotal;

  bool get isEmpty => added.isEmpty && removed.isEmpty && deltaTotal == 0;
}
