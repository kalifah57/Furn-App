import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';

/// حارس الخصوصية للـ params (إصلاح G1/GAP-6).
///
/// عقد [AnalyticsEvent] ينصّ على «قيَم بدائية فقط — بلا PII»، لكن هذا الثبات كان
/// **بلا حارس** — ولهذا تسلّل `need_unmet.raw_type` (نصّ المستخدم الخام) وحتى
/// أُكِّد كسلوك متوقَّع. هذا الاختبار يحوّل «لا PII» من نيّة إلى ضمان يفشل CI عند
/// كسره. أي حدث جديد يجب أن يُدرَج هنا (كما يُدرَج في `analytics_events.md`).
void main() {
  // مثيل تمثيليّ لكل حدث في الكتالوج (١٦).
  const all = <AnalyticsEvent>[
    FlowStarted('onboarding'),
    InputSubmitted(
      roomType: 'bedroom',
      hasBudget: true,
      essentialCount: 2,
      optionalCount: 1,
      inputMode: 'manual',
    ),
    PlanSeeded(
      confidence: 80,
      itemCount: 3,
      missingCount: 0,
      total: 1200,
      withinBudget: true,
    ),
    PlanRestored(confidence: 70, itemCount: 3, decisions: 2),
    ItemPinned('bed'),
    ItemRejected('sofa'),
    ItemSwapped('table'),
    BudgetChanged(newMax: 1800, deltaConfidence: 5),
    OptionsOpened(category: 'bed', optionCount: 4),
    ArOpened('demo'),
    MerchantClicked('prod_1', category: 'sofa'),
    PlanFinalized(confidence: 85, itemCount: 3, pinnedCount: 1, edits: 2),
    PlanShared(80),
    AssistantCommand(intent: 'add', understood: true),
    NeedUnmet(requestedCategory: 'other', reason: 'out_of_scope'),
    SessionAbandoned(lastStep: 'plan', lastConfidence: 60),
  ];

  test('the catalog covers all 16 events with stable, unique snake_case names',
      () {
    final names = all.map((e) => e.name).toList();
    expect(names.toSet(), hasLength(16),
        reason: 'expected 16 distinct event names, got: $names');
    final snake = RegExp(r'^[a-z][a-z0-9_]*$');
    for (final name in names) {
      expect(snake.hasMatch(name), isTrue, reason: '"$name" is not snake_case');
    }
  });

  test('every param value is a primitive — no nested maps/lists/objects', () {
    for (final e in all) {
      for (final entry in e.params.entries) {
        final v = entry.value;
        final ok = v == null || v is String || v is int || v is double || v is bool;
        expect(ok, isTrue,
            reason:
                '${e.name}.${entry.key} is ${v.runtimeType}, not a primitive — '
                'params must stay serialisable and PII-free.');
      }
    }
  });

  test('no param key names a raw-content / identity field (PII guard)', () {
    // أسماء حقول تنمّ عن نصّ خام أو هوية — أبواب تسرّب PII. `raw_type` هنا عمدًا:
    // اختبار انحدار لـ GAP-2 كي لا يعود نصّ المستخدم الخام إلى الأحداث.
    const forbidden = <String>{
      'raw_type', 'raw', 'text', 'query', 'utterance', 'message', 'note',
      'comment', 'name', 'email', 'phone', 'address', 'user_id', 'userid',
      'session_id', // يُلحق كسياق نقل في المصرف، لا كمحتوى حدث
    };
    for (final e in all) {
      final hits = e.params.keys
          .where((k) => forbidden.contains(k.toLowerCase()))
          .toList();
      expect(hits, isEmpty,
          reason: '${e.name} carries forbidden key(s): $hits');
    }
  });

  test('need_unmet no longer carries raw user text (GAP-2 regression)', () {
    final e = all.whereType<NeedUnmet>().single;
    expect(e.params.containsKey('raw_type'), isFalse);
    expect(e.params['requested_category'], isA<String>());
  });
}
