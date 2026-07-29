import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json_helpers.dart';

/// يقابل عنصر `recommendations.individual_items` في json_schema.md.
/// يُنتَج من محرّك التوصيات (منطق حتمي)، لا من الـ AI مباشرة.
class RecommendedItem extends Equatable {
  const RecommendedItem({
    required this.name,
    required this.category,
    required this.price,
    this.reason = '',
    this.priority = ItemPriority.optional,
    this.productId,
    this.score = 0,
  });

  final String name;
  final RecommendationCategory category;
  final double price;
  final String reason;
  final ItemPriority priority;

  /// مرجع اختياري لمنتج الكتالوج المصدر.
  final String? productId;

  /// درجة التوصية (0–100) — للترتيب والشفافية، ليست جزءًا من الـ schema الأساسي.
  final double score;

  factory RecommendedItem.fromJson(Map<String, dynamic> json) => RecommendedItem(
        name: asString(json['name']),
        category: RecommendationCategory.fromWire(json['category']),
        price: asDouble(json['price']),
        reason: asString(json['reason']),
        priority: ItemPriority.fromWire(json['priority']),
        productId: json['product_id'] == null ? null : asString(json['product_id']),
        score: asDouble(json['score']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category.wire,
        'price': price,
        'reason': reason,
        'priority': priority.wire,
        if (productId != null) 'product_id': productId,
        'score': score,
      };

  @override
  List<Object?> get props =>
      [name, category, price, reason, priority, productId, score];
}
