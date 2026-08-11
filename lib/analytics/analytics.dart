import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// طبقة القياس (Analytics) — تُلاحظ حلقة الثقة فقط، ولا تغيّرها.
///
/// مبنيّة على نفس نمط المستودعات في المشروع (واجهة + تنفيذ mock + provider):
/// نبدّل الـ sink دون لمس نقاط النداء. **محرّك القرار النقي
/// (`lib/domain_engine/*`) يجب ألّا يستورد هذا الملف أبدًا** (اختبار حارس يفرض ذلك).
abstract interface class Analytics {
  void track(AnalyticsEvent event);
}

/// أحداث قِمع الثقة — مكتوبة بأنواع صريحة، بلا خرائط حرّة في نقاط النداء.
sealed class AnalyticsEvent {
  const AnalyticsEvent();

  /// الاسم المستقر للحدث (snake_case) — عقد التتبّع.
  String get name;

  /// خصائص الحدث (قيَم بدائية فقط — بلا PII).
  Map<String, Object?> get params;
}

class FlowStarted extends AnalyticsEvent {
  const FlowStarted(this.source);
  final String source; // onboarding | sample_plan
  @override
  String get name => 'flow_started';
  @override
  Map<String, Object?> get params => {'source': source};
}

class InputSubmitted extends AnalyticsEvent {
  const InputSubmitted({
    required this.roomType,
    required this.hasBudget,
    required this.essentialCount,
    required this.optionalCount,
    required this.inputMode,
  });
  final String roomType;
  final bool hasBudget;
  final int essentialCount;
  final int optionalCount;
  final String inputMode; // manual | text | voice | image
  @override
  String get name => 'input_submitted';
  @override
  Map<String, Object?> get params => {
        'roomType': roomType,
        'hasBudget': hasBudget,
        'essentialCount': essentialCount,
        'optionalCount': optionalCount,
        'inputMode': inputMode,
      };
}

class PlanSeeded extends AnalyticsEvent {
  const PlanSeeded({
    required this.confidence,
    required this.itemCount,
    required this.missingCount,
    required this.total,
    required this.withinBudget,
  });
  final int confidence;
  final int itemCount;
  final int missingCount;
  final double total;
  final bool withinBudget;
  @override
  String get name => 'plan_seeded';
  @override
  Map<String, Object?> get params => {
        'confidence': confidence,
        'itemCount': itemCount,
        'missingCount': missingCount,
        'total': total,
        'withinBudget': withinBudget,
      };
}

/// المستخدم عاد إلى خطة كانت محفوظة (تحديث الصفحة، أو زيارة لاحقة).
///
/// **ليس** [PlanSeeded]: التحديث ليس بذرة جديدة، وعدّه كذلك يضخّم بسط قِمع
/// التفعيل كذبًا — وهذا بالضبط نوع الرقم الذي يقود إلى قرار خاطئ. وهو بذاته
/// مقياس لم يكن عندنا: **كم واحدًا يعود إلى خطته فعلًا** — أوضح إشارة ملكية.
class PlanRestored extends AnalyticsEvent {
  const PlanRestored({
    required this.confidence,
    required this.itemCount,
    required this.decisions,
  });
  final int confidence;
  final int itemCount;

  /// عدد القرارات المستعادة (تثبيت + رفض) — خطة بلا قرارات لم يشتغل عليها أحد.
  final int decisions;

  @override
  String get name => 'plan_restored';
  @override
  Map<String, Object?> get params => {
        'confidence': confidence,
        'itemCount': itemCount,
        'decisions': decisions,
      };
}

class ItemPinned extends AnalyticsEvent {
  const ItemPinned(this.category);
  final String category;
  @override
  String get name => 'item_pinned';
  @override
  Map<String, Object?> get params => {'category': category};
}

class ItemRejected extends AnalyticsEvent {
  const ItemRejected(this.category);
  final String category;
  @override
  String get name => 'item_rejected';
  @override
  Map<String, Object?> get params => {'category': category};
}

class ItemSwapped extends AnalyticsEvent {
  const ItemSwapped(this.category);
  final String category;
  @override
  String get name => 'item_swapped';
  @override
  Map<String, Object?> get params => {'category': category};
}

class BudgetChanged extends AnalyticsEvent {
  const BudgetChanged({required this.newMax, required this.deltaConfidence});
  final double newMax;
  final int deltaConfidence;
  @override
  String get name => 'budget_changed';
  @override
  Map<String, Object?> get params =>
      {'newMax': newMax, 'deltaConfidence': deltaConfidence};
}

class OptionsOpened extends AnalyticsEvent {
  const OptionsOpened({required this.category, required this.optionCount});
  final String category;
  final int optionCount;
  @override
  String get name => 'options_opened';
  @override
  Map<String, Object?> get params =>
      {'category': category, 'optionCount': optionCount};
}

class ArOpened extends AnalyticsEvent {
  const ArOpened(this.target);
  final String target; // productId | "demo"
  @override
  String get name => 'ar_opened';
  @override
  Map<String, Object?> get params => {'target': target};
}

class PlanFinalized extends AnalyticsEvent {
  const PlanFinalized({
    required this.confidence,
    required this.itemCount,
    required this.pinnedCount,
    required this.edits,
  });
  final int confidence;
  final int itemCount;
  final int pinnedCount;
  final int edits;
  @override
  String get name => 'plan_finalized';
  @override
  Map<String, Object?> get params => {
        'confidence': confidence,
        'itemCount': itemCount,
        'pinnedCount': pinnedCount,
        'edits': edits,
      };
}

/// المستخدم فتح رابط المنتج في المتجر — أوّل إشارة نيّة شراء. بها يصير **قِمع
/// الإيراد مرئيًّا**: قبلها كنّا عميانًا عن أهم خطوة فيه، فلا سقف للنقرة المدفوعة
/// نعرفه ولا نسبة تحوّل نقيسها. يحترم الموافقة كبقية الأحداث (يُسقَط بلا موافقة).
class MerchantClicked extends AnalyticsEvent {
  const MerchantClicked(this.productId, {this.category});
  final String productId;
  final String? category;
  @override
  String get name => 'merchant_click';
  @override
  Map<String, Object?> get params => {
        'product_id': productId,
        if (category != null) 'category': category,
      };
}

class PlanShared extends AnalyticsEvent {
  const PlanShared(this.confidence);
  final int confidence;
  @override
  String get name => 'plan_shared';
  @override
  Map<String, Object?> get params => {'confidence': confidence};
}

/// المستخدم خاطب المساعد داخل «غرفتي» بأمرٍ لغوي. [understood] يفصل ما فهمناه
/// عمّا لم نفهمه: تجميع `understood=false` يكشف **أيّ لغةٍ نعلّمها المُحلِّل بعد**،
/// وهو ما يوجّه تطوير الفهم بأثر حقيقي لا بالحدس.
class AssistantCommand extends AnalyticsEvent {
  const AssistantCommand({required this.intent, required this.understood});

  /// نيّة الأمر: set_budget | nudge_budget | add | remove | finalize | unknown.
  final String intent;
  final bool understood;

  @override
  String get name => 'assistant_command';
  @override
  Map<String, Object?> get params =>
      {'intent': intent, 'understood': understood};
}

/// طلب المستخدم شيئًا لا نخدمه. تجميع هذا الحدث يحوّل الشكوى إلى **قائمة
/// تسوّق مرتّبة بالطلب الحقيقي** — وهو ما يقرّر ماذا نورّد بعد ذلك.
///
/// **بلا PII (إصلاح G1/GAP-2):** لا يحمل نصّ المستخدم الخام — فقد يحوي اسمًا أو
/// مكانًا أو رقمًا. الطلب يُلتقط كـ[requestedCategory] من مفردات مغلقة (فئة
/// معروفة بصيغة `wire`، أو `other` لِما يقع خارج فئاتنا)، فيبقى مقياس «ماذا
/// نورّد بعد» قابلًا للتجميع دون تسريب ما كتبه المستخدم.
class NeedUnmet extends AnalyticsEvent {
  const NeedUnmet({
    required this.requestedCategory,
    required this.reason,
    this.reserveSar,
  });

  /// فئة الطلب من مفردات مغلقة (`wire`) — أو `other` لِما يقع خارج فئاتنا.
  /// ليست نصًّا حرًّا: يُطبَّع من طرف المُنتِج قبل الإطلاق (نداء يملكه المسار المعني).
  final String requestedCategory;

  /// `out_of_scope` | `not_stocked` | `none_fit`
  final String reason;

  /// مبلغ محجوز اختياري — قيمة مُجمَّعة غير معرِّفة، لا هوية.
  final double? reserveSar;

  @override
  String get name => 'need_unmet';

  @override
  Map<String, Object?> get params => {
        'requested_category': requestedCategory,
        'reason': reason,
        if (reserveSar != null) 'reserve_sar': reserveSar,
      };
}

class SessionAbandoned extends AnalyticsEvent {
  const SessionAbandoned({required this.lastStep, required this.lastConfidence});
  final String lastStep;
  final int lastConfidence;
  @override
  String get name => 'session_abandoned';
  @override
  Map<String, Object?> get params =>
      {'lastStep': lastStep, 'lastConfidence': lastConfidence};
}

// ---- sinks -----------------------------------------------------------------

/// الافتراضي: يُسقِط كل شيء (الإنتاج قبل اختيار sink حقيقي، أو عند رفض الموافقة).
class NoopAnalytics implements Analytics {
  const NoopAnalytics();
  @override
  void track(AnalyticsEvent event) {}
}

/// sink للتطوير/الاختبار: يسجّل الأحداث (ويطبعها اختياريًا). يحترم الموافقة.
class DebugAnalytics implements Analytics {
  DebugAnalytics({this.consent = true, this.log = true, String? sessionId})
      : sessionId = sessionId ?? const Uuid().v4();

  /// مفتاح الموافقة/الإيقاف (PDPL) — إن كان false لا يُسجَّل أي حدث.
  final bool consent;
  final bool log;

  /// معرّف جلسة مجهول (بلا PII) — يُربط لاحقًا بمستخدم المصادقة المجهول.
  final String sessionId;

  final List<AnalyticsEvent> events = [];

  List<String> get names => [for (final e in events) e.name];

  @override
  void track(AnalyticsEvent event) {
    if (!consent) return;
    events.add(event);
    if (log) debugPrint('[analytics:$sessionId] ${event.name} ${event.params}');
  }
}

/// جذع الـ sink الحقيقي المستقبلي — نفس الواجهة، بلا شبكة بعد.
class RemoteAnalytics implements Analytics {
  RemoteAnalytics({this.consent = true, String? sessionId})
      : sessionId = sessionId ?? const Uuid().v4();

  final bool consent;
  final String sessionId;

  @override
  void track(AnalyticsEvent event) {
    if (!consent) return;
    // TODO(remote): جمّع الأحداث وأرسلها POST بشكل {sessionId, name, params, ts}
    // إلى خدمة القياس. لا PII — معرّف جلسة مجهول فقط.
  }
}
