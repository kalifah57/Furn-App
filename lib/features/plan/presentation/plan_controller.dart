import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/parsing/plan_command.dart';
import '../../../ai/parsing/plan_command_parser.dart';
import '../../../analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../domain_engine/plan/plan.dart';
import '../../../domain_engine/plan/plan_workspace.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/formatters.dart';
import '../../room_input/presentation/flow_controller.dart';
import '../data/plan_draft_store.dart';

/// مشروع تجريبي للدخول المباشر إلى مساحة الخطة (من شاشة البداية).
const _demoProject = FurnishingProject(
  projectId: 'demo',
  room: Room(
      name: 'غرفة النوم', widthM: 3, lengthM: 3.5, roomType: RoomType.bedroom),
  budget: Budget(maxTotal: 1800),
  style: StylePreferences(preferred: ['modern'], colors: ['gray', 'white']),
  items: RequestedItems(
    essential: [RequestedItem(type: 'سرير'), RequestedItem(type: 'دولاب')],
    optional: [RequestedItem(type: 'إضاءة'), RequestedItem(type: 'طاولة')],
  ),
);

/// مخزن مسوّدة الخطة — يُستبدَل في الاختبارات بمخزن في الذاكرة.
final planDraftStoreProvider =
    Provider<PlanDraftStore>((ref) => const PlanDraftStore());

/// المشروع الذي تُبنى عليه الخطة، بهذا الترتيب:
/// مشروع التدفّق (input → analysis) إن اكتمل، ثم **المُلخّص المحفوظ** إن وُجد،
/// وإلا المشروع التجريبي.
///
/// المسوّدة قبل التجريبي عمدًا: من حدّث الصفحة بعد أن شكّل خطته يجب أن يرى غرفته
/// هو، لا غرفة عرض. المشروع التجريبي آخر الخيارات لا أوّلها.
final planProjectProvider = Provider<FurnishingProject>((ref) {
  final flowProject = ref.watch(furnishingFlowControllerProvider).project;
  if (flowProject != null) return flowProject;
  return ref.read(planDraftStoreProvider).load()?.brief ?? _demoProject;
});

/// يحمّل الكتالوج، يستعيد المسوّدة إن كانت لنفس المشروع، ثم يبني [PlanController]
/// فوق [PlanWorkspace] (نواة حلقة الثقة).
final planControllerProvider = FutureProvider<PlanController>((ref) async {
  final res = await ref.read(catalogRepositoryProvider).loadProducts();
  final catalog = res.valueOrNull ?? const <CatalogProduct>[];
  final project = ref.read(planProjectProvider);
  final store = ref.read(planDraftStoreProvider);
  final ws = PlanWorkspace(project: project, catalog: catalog);

  // القرارات تُستعاد لنفس المشروع فقط: تثبيتات مشروع سابق فوق مُلخّص جديد ليست
  // استعادة بل تلويث — قد تشير إلى منتجات لا علاقة لها بهذه الغرفة.
  final draft = store.load();
  var restored = false;
  if (draft != null && draft.brief.projectId == project.projectId) {
    ws.restore(draft.state);
    restored = true;
  }

  final controller = PlanController(
    ws,
    analytics: ref.read(analyticsProvider),
    store: store,
    restored: restored,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// يترجم نيّة المستخدم (تثبيت/رفض/تبديل/ميزانية) إلى إعادة بناء للخطة،
/// ويحتفظ بآخر تغيير لعرض «ما الذي تغيّر».
class PlanController extends ChangeNotifier {
  PlanController(
    this._ws, {
    Analytics analytics = const NoopAnalytics(),
    PlanDraftStore? store,
    bool restored = false,
    this.parser = const PlanCommandParser(),
  })  : _analytics = analytics,
        _store = store {
    plan = _ws.build();
    if (restored) {
      final s = _ws.snapshot();
      _analytics.track(PlanRestored(
        confidence: plan.confidence,
        itemCount: plan.itemCount,
        decisions: s.pinned.length + s.rejected.length,
      ));
    } else {
      _analytics.track(PlanSeeded(
        confidence: plan.confidence,
        itemCount: plan.itemCount,
        missingCount: plan.missingCategories.length,
        total: plan.total,
        withinBudget: plan.assurances.withinBudget,
      ));
      // نحفظ البذرة فورًا: من أكمل التدفّق ثم أغلق المتصفّح دون أن يعدّل شيئًا
      // كان سيعود إلى المشروع التجريبي، أي يفقد غرفته لأنه لم يضغط زرًّا.
      _persist();
    }
  }

  final PlanWorkspace _ws;
  final Analytics _analytics;
  final PlanDraftStore? _store;

  /// مُحلِّل لغة المساعد (mock-first) — يُبدَّل بمزوّد حقيقي عبر نفس العقد.
  final PlanCommandParser parser;

  late Plan plan;
  PlanDiff? lastChange;

  /// عدد تعديلات المستخدم قبل الإنهاء (تثبيت/رفض/تبديل/ميزانية) — يعكس التفاعل.
  int _edits = 0;
  bool _abandonLogged = false;

  final List<Plan> _snapshots = [];
  final List<WorkspaceState> _states = [];

  FurnishingProject get project => _ws.project;

  /// Saved versions, newest last (for compare + revert).
  List<Plan> get snapshots => List.unmodifiable(_snapshots);

  void saveSnapshot() {
    _snapshots.add(plan);
    _states.add(_ws.snapshot());
    notifyListeners();
  }

  void revertTo(int index) {
    if (index < 0 || index >= _states.length) return;
    _ws.restore(_states[index]);
    plan = _ws.build();
    lastChange = null;
    _persist();
    notifyListeners();
  }

  /// How the current plan differs from a saved version.
  PlanDiff compareWith(int index) => PlanWorkspace.diff(_snapshots[index], plan);

  /// يكتب المُلخّص + القرارات بعد كل تغيير. المُلخّص يُحفظ أيضًا لأن
  /// [PlanWorkspace.setBudget] يغيّره، فحفظ القرارات وحدها كان سيفقد الميزانية.
  void _persist() => _store?.save(_ws.project, _ws.snapshot());

  void _apply(void Function() op) {
    final before = plan;
    op();
    plan = _ws.build();
    lastChange = PlanWorkspace.diff(before, plan);
    _persist();
    notifyListeners();
  }

  void pin(String id) {
    _apply(() => _ws.pin(id));
    _edits++;
    _analytics.track(ItemPinned(_categoryOf(id)));
  }

  void unpin(String id) => _apply(() => _ws.unpin(id));

  void reject(String id) {
    final category = _categoryOf(id);
    _apply(() => _ws.reject(id));
    _edits++;
    _analytics.track(ItemRejected(category));
  }

  void swap(String outId, String inId) {
    _apply(() => _ws.swap(outProductId: outId, inProductId: inId));
    _edits++;
    _analytics.track(ItemSwapped(_categoryOf(inId)));
  }

  void setBudget(double v) {
    final before = plan.confidence;
    _apply(() => _ws.setBudget(v));
    _edits++;
    _analytics
        .track(BudgetChanged(newMax: v, deltaConfidence: plan.confidence - before));
  }

  /// يضيف أوفر ما يناسب الغرفة في الخانة، ويعيد **هل نجح**.
  ///
  /// النجاح ليس مضمونًا: الكتالوج الحقيقي لا يحوي كل فئة (لا إضاءة ولا سجاد
  /// اليوم). كانت الدالة تصمت عند العجز، فتُقرأ نقرةُ المستخدم كعطل في الزرّ لا
  /// كحدٍّ في المخزون — والحدّ المعلَن أصدق من الصمت.
  bool addCheapestOf(RecommendationCategory category) {
    final alts = _ws.alternativesFor(category);
    if (alts.isEmpty) return false;
    pin(alts.first.productId);
    return true;
  }

  void finalizePlan() {
    _apply(_ws.finalizePlan);
    _analytics.track(PlanFinalized(
      confidence: plan.confidence,
      itemCount: plan.itemCount,
      pinnedCount: plan.pinnedCount,
      edits: _edits,
    ));
  }

  void reopen() => _apply(_ws.reopen);

  List<CatalogProduct> alternativesFor(RecommendationCategory c) =>
      _ws.alternativesFor(c);

  /// أعلى ٣ بدائل نقاطًا في الخانة، ضمن الميزانية والمقاس، مع إيجابيات/سلبيات
  /// مقابل الحالية — «بدّل» يصير قرارًا لا قائمة.
  List<ReplacementOption> betterAlternatives(
          RecommendationCategory c, String currentId) =>
      _ws.betterAlternatives(c, currentId);

  // ---- المساعد داخل «غرفتي»: لغة → نيّة → تنفيذ حتمي ----------------------

  /// نقطة دخول الورقة: يفهم جملة المستخدم (mock الآن) ثم ينفّذها على المحرّك.
  CommandResult runCommand(String text) => applyCommand(parser.parse(text));

  /// ينفّذ أمرًا منظّمًا عبر عملياتٍ **موجودة** (ميزانية/تثبيت/رفض/اعتماد)، فتُحفظ
  /// القرارات وتُرسَل أحداثها كالمعتاد. المساعد يفهم؛ المحرّك يقرّر النتيجة.
  ///
  /// يُرسَل [AssistantCommand] دائمًا (حتى للمجهول) — معدّل «لم نفهم» هو ما يوجّه
  /// أيّ لغةٍ نعلّمها المُحلِّل تاليًا.
  CommandResult applyCommand(PlanCommand cmd) {
    _analytics.track(
        AssistantCommand(intent: cmd.intent, understood: cmd is! UnknownCommand));
    switch (cmd) {
      case SetBudgetCommand(:final amountSar):
        final v = amountSar.clamp(500.0, 10000.0).roundToDouble();
        setBudget(v);
        return CommandResult(
            understood: true,
            message: 'ضبطت ميزانيتك عند ${formatSar(v)} · $_confLine');
      case NudgeBudgetCommand(:final direction):
        final v = (project.budget.maxTotal * (direction < 0 ? 0.85 : 1.15))
            .clamp(500.0, 10000.0)
            .roundToDouble();
        setBudget(v);
        return CommandResult(
            understood: true,
            message: '${direction < 0 ? 'خفّضت' : 'رفعت'} ميزانيتك إلى '
                '${formatSar(v)} · $_confLine');
      case AddCategoryCommand(:final category):
        // نفس صدق الـchip بنفس الجملة: الفهم تمّ، والعجز في المخزون لا في الطلب.
        if (!addCheapestOf(category)) {
          return CommandResult(
              understood: true,
              message: 'لا نوفّر ${category.arabicLabel} حاليًا.');
        }
        return CommandResult(
            understood: true,
            message: 'أضفت ${category.arabicLabel} · $_confLine');
      case RemoveCategoryCommand(:final category):
        final id = _idInCategory(category);
        if (id == null) {
          return CommandResult(
              understood: true,
              message: 'لا توجد ${category.arabicLabel} في خطتك.');
        }
        reject(id);
        return CommandResult(
            understood: true,
            message: 'أزلت ${category.arabicLabel} · $_confLine');
      case FinalizeCommand():
        finalizePlan();
        return const CommandResult(
            understood: true, message: 'اعتمدت خطتك — أنت جاهز 👏');
      case UnknownCommand():
        return const CommandResult(
          understood: false,
          message: 'لم أفهم طلبك. جرّب: «اجعلها أوفر» · «أضف طاولة» · '
              '«ميزانيتي ٣٠٠٠» · «جاهز».',
        );
    }
  }

  String get _confLine => 'ثقتك ${plan.confidence}٪';

  /// معرّف أوّل قطعةٍ في الخطة ضمن فئةٍ ما — لتنفيذ «احذف الطاولة» على المعروض.
  String? _idInCategory(RecommendationCategory category) {
    for (final it in plan.items) {
      final id = it.item.productId;
      if (it.item.category == category && id != null) return id;
    }
    return null;
  }

  /// منتج الكتالوج المصدر لعنصر في الخطة (للوصول إلى نموذج الـ AR ومقاسه).
  CatalogProduct? productById(String? id) {
    if (id == null) return null;
    for (final p in _ws.catalog) {
      if (p.productId == id) return p;
    }
    return null;
  }

  // ---- ملاحظة (analytics فقط — لا تغيّر الحالة) --------------------------
  void logOptionsOpened(RecommendationCategory category, int count) =>
      _analytics.track(OptionsOpened(category: category.wire, optionCount: count));

  void logShared() => _analytics.track(PlanShared(plan.confidence));

  /// يُستدعى عند مغادرة شاشة الخطة دون إنهاء (يُرسَل مرّة واحدة).
  void logAbandonedIfUnfinished() {
    if (_abandonLogged || plan.isFinalized) return;
    _abandonLogged = true;
    _analytics.track(
        SessionAbandoned(lastStep: 'plan', lastConfidence: plan.confidence));
  }

  String _categoryOf(String? id) =>
      productById(id)?.category.wire ?? 'unknown';
}

/// نتيجة أمرٍ لغوي وُجّه للمساعد: هل فُهم، ورسالةٌ موجزة تُعرَض في الورقة. لا حالة
/// هنا — الحالة في الخطة نفسها؛ هذه للعرض الفوري فقط.
class CommandResult {
  const CommandResult({required this.understood, required this.message});
  final bool understood;
  final String message;
}
