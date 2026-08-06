import 'dart:convert';

import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/store_types.dart';
import '../../../domain_engine/plan/plan_workspace.dart';
import '../../../shared/models/models.dart';

/// كل ما يلزم لإعادة إنتاج خطة المستخدم **بالضبط**.
///
/// الخطة نفسها لا تُحفظ، بل تُشتقّ: المحرّك حتمي، فـ(المُلخّص + حالة المساحة +
/// الكتالوج) تُنتج الخطة ذاتها في كل مرة. حفظ الخطة كان سيعني نسختين من نفس
/// الحقيقة، وأولاهما تتقادم بصمت يوم يتغيّر المحرّك.
class PlanDraft {
  const PlanDraft({required this.brief, required this.state});

  /// مدخل المستخدم: الغرفة، الميزانية، النمط، الاحتياج.
  final FurnishingProject brief;

  /// قراراته: ما ثبّته، ما رفضه، الميزانية التي ضبطها، وهل أنهى الخطة.
  final WorkspaceState state;
}

/// يحفظ مسوّدة الخطة الحالية ويستعيدها عبر إغلاق المتصفّح.
///
/// **لا يرمي أبدًا.** تخزين تالف أو مخطّط من إصدار سابق يعني «لا مسوّدة»، لا
/// شاشة خطأ: المستخدم الذي فقد خطته لا يُعوَّض بـ stack trace.
class PlanDraftStore {
  const PlanDraftStore({
    this.read = storeRead,
    this.write = storeWrite,
    this.remove = storeRemove,
  });

  final StoreRead read;
  final StoreWrite write;
  final StoreRemove remove;

  static const key = 'furn.plan_draft';

  /// رقم المخطّط. رفعه يُبطل المسوّدات القديمة بدل أن يستعيدها ناقصة — استعادة
  /// نصف صحيحة أسوأ من لا استعادة، لأن المستخدم لا يرى ما ضاع.
  static const version = 1;

  PlanDraft? load() {
    final raw = read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != version) return null;
      return PlanDraft(
        brief: FurnishingProject.fromJson(
            (map['brief'] as Map).cast<String, dynamic>()),
        state: _stateFromJson((map['state'] as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      // تخزين تالف: نمسحه بدل أن نُعيد الفشل عليه كل إقلاع.
      remove(key);
      return null;
    }
  }

  void save(FurnishingProject brief, WorkspaceState state) {
    try {
      write(
        key,
        jsonEncode({
          'v': version,
          'brief': brief.toJson(),
          'state': {
            // مرتّبة كي يكون المخزَّن حتميًا: نفس الحالة ⇒ نفس النصّ.
            'pinned': state.pinned.toList()..sort(),
            'rejected': state.rejected.toList()..sort(),
            'budget_max': state.budgetMax,
            'finalized': state.finalized,
          },
        }),
      );
    } catch (_) {
      // الحصّة ممتلئة أو التخزين مرفوض — الخطة تبقى تعمل، لا تُحفظ فقط.
    }
  }

  void clear() => remove(key);

  /// `budget_max` مطلوب: غيابه يعني تخزينًا تالفًا، ولو عوّضناه بصفر لاستعاد
  /// المستخدم خطته بميزانية صفر دون أن يعرف السبب. الرمي هنا يعني «لا مسوّدة».
  static WorkspaceState _stateFromJson(Map<String, dynamic> j) => WorkspaceState(
        pinned: _ids(j['pinned']),
        rejected: _ids(j['rejected']),
        budgetMax: (j['budget_max'] as num).toDouble(),
        finalized: j['finalized'] == true,
      );

  static Set<String> _ids(Object? v) => v is List
      ? {
          for (final e in v)
            if (e is String) e
        }
      : <String>{};
}
