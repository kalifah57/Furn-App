import 'package:equatable/equatable.dart';

import 'json_helpers.dart';

/// يقابل `budget` في json_schema.md.
class Budget extends Equatable {
  const Budget({
    this.currency = 'SAR',
    this.maxTotal = 0,
    this.flexible = false,
  });

  final String currency;
  final double maxTotal;
  final bool flexible;

  bool get hasBudget => maxTotal > 0;

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        currency: asString(json['currency'], 'SAR'),
        maxTotal: asDouble(json['max_total']),
        flexible: asBool(json['flexible']),
      );

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'max_total': maxTotal,
        'flexible': flexible,
      };

  Budget copyWith({String? currency, double? maxTotal, bool? flexible}) => Budget(
        currency: currency ?? this.currency,
        maxTotal: maxTotal ?? this.maxTotal,
        flexible: flexible ?? this.flexible,
      );

  @override
  List<Object?> get props => [currency, maxTotal, flexible];
}
