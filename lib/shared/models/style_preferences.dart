import 'package:equatable/equatable.dart';

import 'json_helpers.dart';

/// يقابل `style` في json_schema.md.
class StylePreferences extends Equatable {
  const StylePreferences({
    this.preferred = const [],
    this.colors = const [],
    this.notes = '',
  });

  final List<String> preferred;
  final List<String> colors;
  final String notes;

  factory StylePreferences.fromJson(Map<String, dynamic> json) => StylePreferences(
        preferred: asStringList(json['preferred']),
        colors: asStringList(json['colors']),
        notes: asString(json['notes']),
      );

  Map<String, dynamic> toJson() => {
        'preferred': preferred,
        'colors': colors,
        'notes': notes,
      };

  StylePreferences copyWith({
    List<String>? preferred,
    List<String>? colors,
    String? notes,
  }) =>
      StylePreferences(
        preferred: preferred ?? this.preferred,
        colors: colors ?? this.colors,
        notes: notes ?? this.notes,
      );

  @override
  List<Object?> get props => [preferred, colors, notes];
}
