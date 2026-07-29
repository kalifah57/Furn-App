import 'package:equatable/equatable.dart';

import 'json_helpers.dart';

/// يقابل `next_actions` في json_schema.md.
class NextActions extends Equatable {
  const NextActions({
    this.askForImages = false,
    this.followUpQuestions = const [],
  });

  final bool askForImages;
  final List<String> followUpQuestions;

  bool get hasFollowUps => followUpQuestions.isNotEmpty;

  factory NextActions.fromJson(Map<String, dynamic> json) => NextActions(
        askForImages: asBool(json['ask_for_images']),
        followUpQuestions: asStringList(json['follow_up_questions']),
      );

  Map<String, dynamic> toJson() => {
        'ask_for_images': askForImages,
        'follow_up_questions': followUpQuestions,
      };

  NextActions copyWith({bool? askForImages, List<String>? followUpQuestions}) =>
      NextActions(
        askForImages: askForImages ?? this.askForImages,
        followUpQuestions: followUpQuestions ?? this.followUpQuestions,
      );

  @override
  List<Object?> get props => [askForImages, followUpQuestions];
}
