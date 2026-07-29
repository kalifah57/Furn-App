import 'package:equatable/equatable.dart';

import 'budget.dart';
import 'json_helpers.dart';
import 'next_actions.dart';
import 'recommendations.dart';
import 'requested_items.dart';
import 'room.dart';
import 'room_analysis.dart';
import 'style_preferences.dart';

/// النموذج الجذري المطابق بالكامل لـ `json_schema.md`.
///
/// يمثّل مشروع تأثيث واحدًا عبر كامل الرحلة:
/// - `room/budget/style/items` تُملأ من الإدخال + استخراج الـ AI.
/// - `analysis` مخرجات استخراج الـ AI.
/// - `recommendations` مخرجات محرّك التوصيات الحتمي (domain_engine).
/// - `nextActions` أسئلة المتابعة عند نقص البيانات.
class FurnishingProject extends Equatable {
  const FurnishingProject({
    required this.projectId,
    this.locale = 'ar-SA',
    this.room = const Room(),
    this.budget = const Budget(),
    this.style = const StylePreferences(),
    this.items = const RequestedItems(),
    this.analysis = const RoomAnalysis(),
    this.recommendations = const Recommendations(),
    this.nextActions = const NextActions(),
    this.updatedAt,
  });

  final String projectId;
  final String locale;
  final Room room;
  final Budget budget;
  final StylePreferences style;
  final RequestedItems items;
  final RoomAnalysis analysis;
  final Recommendations recommendations;
  final NextActions nextActions;

  /// حقل تشغيلي (خارج الـ schema) لترتيب المشاريع المحفوظة.
  final DateTime? updatedAt;

  factory FurnishingProject.fromJson(Map<String, dynamic> json) => FurnishingProject(
        projectId: asString(json['project_id']),
        locale: asString(json['locale'], 'ar-SA'),
        room: Room.fromJson(_map(json['room'])),
        budget: Budget.fromJson(_map(json['budget'])),
        style: StylePreferences.fromJson(_map(json['style'])),
        items: RequestedItems.fromJson(_map(json['items'])),
        analysis: RoomAnalysis.fromJson(_map(json['analysis'])),
        recommendations: Recommendations.fromJson(_map(json['recommendations'])),
        nextActions: NextActions.fromJson(_map(json['next_actions'])),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.tryParse(asString(json['updated_at'])),
      );

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'locale': locale,
        'room': room.toJson(),
        'budget': budget.toJson(),
        'style': style.toJson(),
        'items': items.toJson(),
        'analysis': analysis.toJson(),
        'recommendations': recommendations.toJson(),
        'next_actions': nextActions.toJson(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  FurnishingProject copyWith({
    String? projectId,
    String? locale,
    Room? room,
    Budget? budget,
    StylePreferences? style,
    RequestedItems? items,
    RoomAnalysis? analysis,
    Recommendations? recommendations,
    NextActions? nextActions,
    DateTime? updatedAt,
  }) =>
      FurnishingProject(
        projectId: projectId ?? this.projectId,
        locale: locale ?? this.locale,
        room: room ?? this.room,
        budget: budget ?? this.budget,
        style: style ?? this.style,
        items: items ?? this.items,
        analysis: analysis ?? this.analysis,
        recommendations: recommendations ?? this.recommendations,
        nextActions: nextActions ?? this.nextActions,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : const {};

  @override
  List<Object?> get props => [
        projectId,
        locale,
        room,
        budget,
        style,
        items,
        analysis,
        recommendations,
        nextActions,
        updatedAt,
      ];
}
