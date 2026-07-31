import 'package:equatable/equatable.dart';

import '../../shared/models/enums.dart';

/// نوع القرار على مسار قرارات المشروع (Decision Timeline).
enum DecisionKind { seeded, pinned, rejected, swapped, budgetSet, approved, reopened }

/// قرار واحد على مسار الزمن — سجلّ نيّة المستخدم (append-only، لا يُعدَّل).
class Decision extends Equatable {
  const Decision({
    required this.kind,
    required this.at,
    this.productId,
    this.category,
    this.value, // مثلًا: الحد الأقصى الجديد للميزانية
    this.confidenceAfter, // 0..100 — لقطة الثقة بعد هذا القرار
  });

  final DecisionKind kind;
  final DateTime at;
  final String? productId;
  final RecommendationCategory? category;
  final double? value;
  final int? confidenceAfter;

  @override
  List<Object?> get props =>
      [kind, at, productId, category, value, confidenceAfter];
}

/// مسار القرارات — قائمة غير قابلة للتعديل (append-only) هي «تاريخ» المشروع
/// وسبب ثقة المستخدم: كل قرار مرئيّ ومُبرَّر.
class DecisionTimeline extends Equatable {
  const DecisionTimeline([this.entries = const []]);

  final List<Decision> entries;

  DecisionTimeline add(Decision d) => DecisionTimeline([...entries, d]);

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;
  Decision? get last => entries.isEmpty ? null : entries.last;

  /// عدد تعديلات المستخدم (يستثني البذرة والاعتماد) — إشارة التفاعل/الملكية.
  int get edits => entries
      .where((e) =>
          e.kind == DecisionKind.pinned ||
          e.kind == DecisionKind.rejected ||
          e.kind == DecisionKind.swapped ||
          e.kind == DecisionKind.budgetSet)
      .length;

  @override
  List<Object?> get props => [entries];
}
