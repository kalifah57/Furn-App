import '../../shared/models/models.dart';
import '../recommendation/category_mapper.dart';
import '../recommendation/recommendation_engine.dart';
import 'plan.dart';
import 'scope_table.dart';
import 'unmet_need.dart';

/// The confidence loop — pure Dart, no Flutter.
///
/// Wraps the deterministic [RecommendationEngine] as the **seed**, then lets the
/// user shape a [Plan] they trust: pin what they love, reject what they don't,
/// swap, and slide the budget — with the plan re-balancing and deriving its own
/// assurances + confidence. This is the product; the recommendation is only its
/// starting point.
class PlanWorkspace {
  PlanWorkspace({
    required this.project,
    required this.catalog,
    RecommendationEngine engine = const RecommendationEngine(),
  }) : _engine = engine;

  FurnishingProject project;
  final List<CatalogProduct> catalog;
  final RecommendationEngine _engine;

  final Set<String> _pinned = {}; // productIds the user locked
  final Set<String> _rejected = {}; // productIds the user refused
  bool _finalized = false;

  // ---- user intent (the system owns the consequences) --------------------

  void pin(String productId) {
    _pinned.add(productId);
    _rejected.remove(productId);
  }

  void unpin(String productId) => _pinned.remove(productId);

  void reject(String productId) {
    _rejected.add(productId);
    _pinned.remove(productId);
  }

  /// Swap = refuse the current pick and lock the chosen alternative.
  void swap({required String outProductId, required String inProductId}) {
    reject(outProductId);
    pin(inProductId);
  }

  void setBudget(double maxTotal) {
    project = project.copyWith(budget: project.budget.copyWith(maxTotal: maxTotal));
  }

  void finalizePlan() => _finalized = true;
  void reopen() => _finalized = false;

  /// Capture the full editable state — enough to reproduce this exact plan.
  WorkspaceState snapshot() => WorkspaceState(
        pinned: {..._pinned},
        rejected: {..._rejected},
        budgetMax: project.budget.maxTotal,
        finalized: _finalized,
      );

  /// Restore a captured state (powers "revert to a saved version").
  void restore(WorkspaceState s) {
    _pinned
      ..clear()
      ..addAll(s.pinned);
    _rejected
      ..clear()
      ..addAll(s.rejected);
    setBudget(s.budgetMax);
    _finalized = s.finalized;
  }

  /// Alternatives the user can swap to in a category: available products of that
  /// category the user hasn't rejected, cheapest-first (transparent).
  List<CatalogProduct> alternativesFor(RecommendationCategory category) {
    final list = _effectiveCatalog()
        .where((p) => p.category == category && p.isAvailable)
        .toList()
      ..sort((a, b) => a.price.compareTo(b.price));
    return list;
  }

  // ---- build the current plan --------------------------------------------

  /// Re-derives the plan: seed from the engine (minus rejects), enforce the
  /// user's pins, then compute assurances + confidence.
  Plan build() {
    final byId = {for (final p in catalog) p.productId: p};
    final recs = _engine.generate(project, _effectiveCatalog());

    final items = <PlanItem>[];
    final pinnedCats = <RecommendationCategory>{};
    final seen = <String>{};

    // 1) the user's locked choices come first and own their category.
    for (final pid in _pinned) {
      final p = byId[pid];
      if (p == null) continue;
      items.add(PlanItem(item: _fromProduct(p, pinned: true), status: PlanItemStatus.pinned));
      pinnedCats.add(p.category);
      seen.add(pid);
    }
    // 2) engine suggestions fill the rest, skipping any category a pin covers.
    for (final ri in recs.individualItems) {
      final pid = ri.productId;
      if (pid != null && seen.contains(pid)) continue;
      if (pinnedCats.contains(ri.category)) continue;
      items.add(PlanItem(item: ri));
      if (pid != null) seen.add(pid);
    }

    final total = items.fold<double>(0, (s, e) => s + e.item.price);
    final covered = items.map((e) => e.item.category).toSet();
    final missing = _missingEssentials(covered);
    final unmet = _unmetNeeds();

    // الميزانية الفعّالة: ما يبقى بعد حجز ما هو خارج نطاقنا. نخطّط عليها لا على
    // الرقم المعلن، وإلا امتلأت الخطة أثاثًا ولم تبقَ سيولة لما طلبه المستخدم
    // فعلًا. تُصفَّر عند السالب — عندها لا شيء داخل الميزانية، وهذا صحيح.
    final reserved = unmet.fold<double>(0, (s, u) => s + u.reserveSar);
    final effective = project.budget.hasBudget && reserved > 0
        ? (project.budget.maxTotal - reserved).clamp(0.0, double.infinity)
        : null;

    final assurances = _assurances(items, byId, total, missing, unmet, effective);
    final engaged = _pinned.isNotEmpty;
    final confidence = _confidence(assurances, engaged);
    final gaps = _confidenceGaps(
        assurances, items, byId, missing, unmet, total, effective, engaged);

    return Plan(
      items: items,
      total: total,
      assurances: assurances,
      confidence: confidence,
      missingCategories: missing,
      isFinalized: _finalized,
      unmetNeeds: unmet,
      effectiveBudgetSar: effective,
      confidenceGaps: gaps,
    );
  }

  /// The difference between two snapshots (for compare + "what changed").
  static PlanDiff diff(Plan before, Plan after) {
    final b = <String, RecommendedItem>{
      for (final i in before.items) i.item.productId ?? i.item.name: i.item,
    };
    final a = <String, RecommendedItem>{
      for (final i in after.items) i.item.productId ?? i.item.name: i.item,
    };
    final added = a.entries.where((e) => !b.containsKey(e.key)).map((e) => e.value).toList();
    final removed = b.entries.where((e) => !a.containsKey(e.key)).map((e) => e.value).toList();
    return PlanDiff(added: added, removed: removed, deltaTotal: after.total - before.total);
  }

  // ---- internals ----------------------------------------------------------

  List<CatalogProduct> _effectiveCatalog() =>
      catalog.where((p) => !_rejected.contains(p.productId)).toList();

  RecommendedItem _fromProduct(CatalogProduct p, {required bool pinned}) => RecommendedItem(
        name: p.title,
        category: p.category,
        price: p.price,
        reason: pinned ? 'ثبّتها بنفسك — نحترم اختيارك' : 'خيار مقترح',
        priority: ItemPriority.essential,
        productId: p.productId,
        score: 100,
      );

  List<RecommendationCategory> _missingEssentials(Set<RecommendationCategory> covered) {
    // الأنواع المجهولة لا مكان لها هنا: مكانها [Plan.unmetNeeds] باسمها الذي
    // كتبه المستخدم، لا كـ«أخرى» في قائمة نواقص لا يمكن سدّها.
    final essentials = <RecommendationCategory>{};
    for (final e in project.items.essential) {
      final c = mapTypeToCategoryOrNull(e.type);
      if (c != null) essentials.add(c);
    }
    return essentials.difference(covered).toList();
  }

  /// الفجوات المعلنة: ما طلبه المستخدم ولا نخدمه.
  ///
  /// ترتيب كلّي بالنصّ — فرز Dart غير مضمون الاستقرار، والناتج يجب أن يكون
  /// واحدًا في كل تشغيل.
  List<UnmetNeed> _unmetNeeds() {
    final seen = <String>{};
    final out = <UnmetNeed>[];
    // RequestedItems فيه قائمتان فقط: essential و optional.
    for (final e in [...project.items.essential, ...project.items.optional]) {
      if (mapTypeToCategoryOrNull(e.type) != null) continue; // نخدمه
      if (e.type.trim().isEmpty) continue;

      // ما لا يعرفه الجدول أيضًا يُعلَن ولا يُسقَط. إسقاطه يعيد الصمت الذي بُنيت
      // هذه الميزة لإنهائه — والفرق أن الصمت الآن كامل، بينما كان «ناقص: أخرى»
      // يُظهر شيئًا على الأقل. الافتراض `notStocked`: نخفض الثقة (فشلنا في
      // خدمة طلب) ونضعه في قائمة التوريد ليصنّفه إنسان — الإفراط في الإبلاغ
      // أأمن من الإسقاط الصامت.
      final need = lookupScope(e.type) ??
          UnmetNeed(rawType: e.type.trim(), reason: UnmetReason.notStocked);
      if (!seen.add(need.rawType)) continue;
      out.add(need);
    }
    out.sort((a, b) => a.rawType.compareTo(b.rawType));
    return out;
  }

  Assurances _assurances(
    List<PlanItem> items,
    Map<String, CatalogProduct> byId,
    double total,
    List<RecommendationCategory> missing,
    List<UnmetNeed> unmet,
    double? effectiveBudget,
  ) {
    final r = project.room;
    var fits = true;
    var available = true;

    final canCheckFit = r.widthM > 0 && r.lengthM > 0;
    final rw = r.widthM * 100, rl = r.lengthM * 100;
    for (final it in items) {
      final pid = it.item.productId;
      final p = pid == null ? null : byId[pid];
      if (p == null) continue;
      if (!p.isAvailable) available = false;
      if (canCheckFit) {
        final ok = (p.widthCm <= rw && p.depthCm <= rl) ||
            (p.depthCm <= rw && p.widthCm <= rl);
        if (!ok) fits = false;
      }
    }

    final ceiling = effectiveBudget ?? project.budget.maxTotal;
    final within = !project.budget.hasBudget || total <= ceiling;
    return Assurances(
      fitsRoom: fits,
      withinBudget: within,
      allAvailable: available,
      // نقص حقيقي فقط يكسر «لم يُنسَ شيء»: `notStocked`/`noneFit` عيب فينا،
      // أما `outOfScope` فحدّ معلن أخبرنا به المستخدم صراحةً — لا يُعاقَب عليه.
      essentialsComplete:
          missing.isEmpty && !unmet.any((u) => u.lowersConfidence),
    );
  }

  /// ماذا يفعل المستخدم ليرفع ثقته — فجوة لكل مكوّن **غير متحقّق** في العدّاد،
  /// بنقاطه الحقيقية والخطوات التي تسدّه، مرتّبةً بالأثر الأكبر أوّلًا.
  ///
  /// كل فرع هنا يقابل سطرًا في [_confidence]، فلا نَعِد بنقاط لا يمنحها العدّاد،
  /// ولا ندرج فجوةً مسدودة أصلًا. المقاسات نفسها التي يفحصها [_assurances].
  List<ConfidenceGap> _confidenceGaps(
    Assurances a,
    List<PlanItem> items,
    Map<String, CatalogProduct> byId,
    List<RecommendationCategory> missing,
    List<UnmetNeed> unmet,
    double total,
    double? effective,
    bool engaged,
  ) {
    final gaps = <ConfidenceGap>[];

    if (!a.essentialsComplete) {
      final actions = <String>[
        for (final c in missing) 'أضِف ${c.arabicLabel}',
        for (final u in unmet.where((u) => u.lowersConfidence))
          'وفّر بديلًا لـ«${u.rawType}» — لا نورّده حاليًا',
      ];
      gaps.add(ConfidenceGap(label: 'أكمل الأساسيات', points: 40, actions: actions));
    }

    if (!a.withinBudget) {
      final ceiling = effective ?? project.budget.maxTotal;
      final over = (total - ceiling).round();
      gaps.add(ConfidenceGap(label: 'ادخل ضمن الميزانية', points: 25, actions: [
        'تجاوزت بـ $over ريال — بدّل قطعة بأرخص، أو أزل واحدة، أو ارفع الميزانية',
      ]));
    }

    if (!a.fitsRoom) {
      gaps.add(ConfidenceGap(
        label: 'اجعلها تناسب الغرفة',
        points: 20,
        actions: [
          for (final name in _oversizedNames(items, byId))
            'بدّل «$name» — أكبر من غرفتك',
        ],
      ));
    }

    if (!a.allAvailable) {
      gaps.add(ConfidenceGap(
        label: 'اجعلها متوفّرة للشراء',
        points: 10,
        actions: [
          for (final name in _unavailableNames(items, byId))
            'بدّل «$name» — غير متوفّرة الآن',
        ],
      ));
    }

    if (!engaged) {
      gaps.add(const ConfidenceGap(
        label: 'اجعلها خطتك',
        points: 5,
        actions: ['ثبّت قطعة تعجبك — اطمئنانك يرتفع حين تشكّلها بنفسك'],
      ));
    }

    // مرتّبة بالأثر (الأكبر أوّلًا) — يفعل المستخدم ما يرفع الثقة أكثر أوّلًا.
    gaps.sort((x, y) => y.points.compareTo(x.points));
    return gaps;
  }

  /// أسماء القطع التي لا تدخل في الغرفة — بنفس فحص [_assurances] تمامًا.
  List<String> _oversizedNames(
      List<PlanItem> items, Map<String, CatalogProduct> byId) {
    final r = project.room;
    if (r.widthM <= 0 || r.lengthM <= 0) return const [];
    final rw = r.widthM * 100, rl = r.lengthM * 100;
    final out = <String>[];
    for (final it in items) {
      final p = it.item.productId == null ? null : byId[it.item.productId];
      if (p == null) continue;
      final ok = (p.widthCm <= rw && p.depthCm <= rl) ||
          (p.depthCm <= rw && p.widthCm <= rl);
      if (!ok) out.add(p.title);
    }
    return out;
  }

  List<String> _unavailableNames(
      List<PlanItem> items, Map<String, CatalogProduct> byId) {
    final out = <String>[];
    for (final it in items) {
      final p = it.item.productId == null ? null : byId[it.item.productId];
      if (p != null && !p.isAvailable) out.add(p.title);
    }
    return out;
  }

  /// Transparent confidence — the sum of what is actually true about the plan,
  /// plus a small nod to ownership. Never a fake 100%.
  int _confidence(Assurances a, bool engaged) {
    var s = 0;
    if (a.essentialsComplete) s += 40; // nothing forgotten (the biggest driver)
    if (a.withinBudget) s += 25; // no budget surprise
    if (a.fitsRoom) s += 20; // it physically works
    if (a.allAvailable) s += 10; // buyable
    if (engaged) s += 5; // the user shaped it (ownership)
    return s > 100 ? 100 : s;
  }
}

/// A capture of everything the user has changed — enough to reproduce a Plan.
class WorkspaceState {
  const WorkspaceState({
    required this.pinned,
    required this.rejected,
    required this.budgetMax,
    required this.finalized,
  });

  final Set<String> pinned;
  final Set<String> rejected;
  final double budgetMax;
  final bool finalized;
}
