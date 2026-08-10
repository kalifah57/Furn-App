import 'package:equatable/equatable.dart';

import 'bundle.dart';
import 'json_helpers.dart';
import 'recommended_item.dart';

/// يقابل `recommendations` في json_schema.md.
class Recommendations extends Equatable {
  const Recommendations({
    this.individualItems = const [],
    this.bundles = const [],
  });

  final List<RecommendedItem> individualItems;
  final List<Bundle> bundles;

  bool get isEmpty => individualItems.isEmpty && bundles.isEmpty;

  factory Recommendations.fromJson(Map<String, dynamic> json) => Recommendations(
        individualItems:
            asMapList(json['individual_items']).map(RecommendedItem.fromJson).toList(),
        bundles: asMapList(json['bundles']).map(Bundle.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'individual_items': individualItems.map((e) => e.toJson()).toList(),
        'bundles': bundles.map((e) => e.toJson()).toList(),
      };

  Recommendations copyWith({
    List<RecommendedItem>? individualItems,
    List<Bundle>? bundles,
  }) =>
      Recommendations(
        individualItems: individualItems ?? this.individualItems,
        bundles: bundles ?? this.bundles,
      );

  @override
  List<Object?> get props => [individualItems, bundles];
}
