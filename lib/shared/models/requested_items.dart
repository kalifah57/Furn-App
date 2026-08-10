import 'package:equatable/equatable.dart';

import 'json_helpers.dart';

/// عنصر مطلوب داخل `items.essential` أو `items.optional` في json_schema.md.
class RequestedItem extends Equatable {
  const RequestedItem({
    required this.type,
    this.constraints = const [],
    this.quantity = 1,
  });

  final String type;
  final List<String> constraints;
  final int quantity;

  factory RequestedItem.fromJson(Map<String, dynamic> json) => RequestedItem(
        type: asString(json['type']),
        constraints: asStringList(json['constraints']),
        quantity: asInt(json['quantity'], 1),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'constraints': constraints,
        'quantity': quantity,
      };

  @override
  List<Object?> get props => [type, constraints, quantity];
}

/// يقابل `items` (essential + optional) في json_schema.md.
class RequestedItems extends Equatable {
  const RequestedItems({
    this.essential = const [],
    this.optional = const [],
  });

  final List<RequestedItem> essential;
  final List<RequestedItem> optional;

  factory RequestedItems.fromJson(Map<String, dynamic> json) => RequestedItems(
        essential: asMapList(json['essential']).map(RequestedItem.fromJson).toList(),
        optional: asMapList(json['optional']).map(RequestedItem.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'essential': essential.map((e) => e.toJson()).toList(),
        'optional': optional.map((e) => e.toJson()).toList(),
      };

  RequestedItems copyWith({
    List<RequestedItem>? essential,
    List<RequestedItem>? optional,
  }) =>
      RequestedItems(
        essential: essential ?? this.essential,
        optional: optional ?? this.optional,
      );

  @override
  List<Object?> get props => [essential, optional];
}
