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
  final String source; // onboarding | plan-demo
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

class PlanShared extends AnalyticsEvent {
  const PlanShared(this.confidence);
  final int confidence;
  @override
  String get name => 'plan_shared';
  @override
  Map<String, Object?> get params => {'confidence': confidence};
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
