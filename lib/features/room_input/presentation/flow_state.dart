import 'package:equatable/equatable.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/furnishing_project.dart';

/// حالات رحلة التأثيث (تعكس initial/loading/success/error — ADR-0001 §2).
enum FlowStatus {
  idle,
  extracting, // تشغيل STT/Vision/LLM
  needsFollowUp, // نقص بيانات → أسئلة متابعة
  recommending, // تشغيل محرّك التوصيات
  ready, // اكتملت التوصيات
  error,
}

class FurnishingFlowState extends Equatable {
  const FurnishingFlowState({
    this.status = FlowStatus.idle,
    this.project,
    this.failure,
  });

  final FlowStatus status;
  final FurnishingProject? project;
  final Failure? failure;

  bool get isBusy =>
      status == FlowStatus.extracting || status == FlowStatus.recommending;

  FurnishingFlowState copyWith({
    FlowStatus? status,
    FurnishingProject? project,
    Failure? failure,
  }) =>
      FurnishingFlowState(
        status: status ?? this.status,
        project: project ?? this.project,
        failure: failure,
      );

  @override
  List<Object?> get props => [status, project, failure];
}
