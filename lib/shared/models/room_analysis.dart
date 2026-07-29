import 'package:equatable/equatable.dart';

import 'json_helpers.dart';

/// يقابل `analysis` في json_schema.md — مخرجات استخراج الـ AI (بيانات منظمة فقط).
class RoomAnalysis extends Equatable {
  const RoomAnalysis({
    this.summary = '',
    this.missingInformation = const [],
    this.warnings = const [],
    this.confidenceScore = 0,
  });

  final String summary;
  final List<String> missingInformation;
  final List<String> warnings;

  /// درجة ثقة الاستخراج بين 0 و 1.
  final double confidenceScore;

  bool get hasMissingInformation => missingInformation.isNotEmpty;

  factory RoomAnalysis.fromJson(Map<String, dynamic> json) => RoomAnalysis(
        summary: asString(json['summary']),
        missingInformation: asStringList(json['missing_information']),
        warnings: asStringList(json['warnings']),
        confidenceScore: asDouble(json['confidence_score']),
      );

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'missing_information': missingInformation,
        'warnings': warnings,
        'confidence_score': confidenceScore,
      };

  RoomAnalysis copyWith({
    String? summary,
    List<String>? missingInformation,
    List<String>? warnings,
    double? confidenceScore,
  }) =>
      RoomAnalysis(
        summary: summary ?? this.summary,
        missingInformation: missingInformation ?? this.missingInformation,
        warnings: warnings ?? this.warnings,
        confidenceScore: confidenceScore ?? this.confidenceScore,
      );

  @override
  List<Object?> get props =>
      [summary, missingInformation, warnings, confidenceScore];
}
