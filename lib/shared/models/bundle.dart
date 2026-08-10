import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json_helpers.dart';
import 'recommended_item.dart';

/// يقابل عنصر `recommendations.bundles` في json_schema.md.
class Bundle extends Equatable {
  const Bundle({
    required this.tier,
    this.totalPrice = 0,
    this.items = const [],
    this.designNotes = const [],
    this.tradeoffs = const [],
    this.reason = '',
    this.exceedsBudget = false,
  });

  final BundleTier tier;
  final double totalPrice;
  final List<RecommendedItem> items;

  /// ملاحظات التصميم / أبرز ميزة (recommendation_engine.md).
  final List<String> designNotes;

  /// أبرز التنازلات (recommendation_engine.md).
  final List<String> tradeoffs;

  /// سبب اختيار الباقة.
  final String reason;

  /// هل تتجاوز الميزانية؟ (تُعرض premium مع تحذير فقط).
  final bool exceedsBudget;

  factory Bundle.fromJson(Map<String, dynamic> json) => Bundle(
        tier: BundleTier.fromWire(json['tier']),
        totalPrice: asDouble(json['total_price']),
        items: asMapList(json['items']).map(RecommendedItem.fromJson).toList(),
        designNotes: asStringList(json['design_notes']),
        tradeoffs: asStringList(json['tradeoffs']),
        reason: asString(json['reason']),
        exceedsBudget: asBool(json['exceeds_budget']),
      );

  Map<String, dynamic> toJson() => {
        'tier': tier.wire,
        'total_price': totalPrice,
        'items': items.map((e) => e.toJson()).toList(),
        'design_notes': designNotes,
        'tradeoffs': tradeoffs,
        'reason': reason,
        'exceeds_budget': exceedsBudget,
      };

  @override
  List<Object?> get props =>
      [tier, totalPrice, items, designNotes, tradeoffs, reason, exceedsBudget];
}
