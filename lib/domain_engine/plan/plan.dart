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
