import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../shared/models/furnishing_project.dart';
import 'flow_state.dart';

final furnishingFlowControllerProvider =
    NotifierProvider<FurnishingFlowController, FurnishingFlowState>(
  FurnishingFlowController.new,
);

/// يقود رحلة التأثيث عبر: (استخراج AI أو إدخال يدوي) → قواعد العمل → التوصيات.
class FurnishingFlowController extends Notifier<FurnishingFlowState> {
  @override
  FurnishingFlowState build() => const FurnishingFlowState();

  /// إدخال يدوي منظّم: بلا استدعاء LLM (cost control) — قواعد العمل فقط.
  Future<void> submitManualDraft(FurnishingProject draft) async {
    state = state.copyWith(status: FlowStatus.extracting, project: draft);
    final finalized = ref.read(analysisRepositoryProvider).finalizeManual(draft);
    await _afterAnalysis(finalized);
  }

  Future<void> runText(String text) =>
      _handle(() => ref.read(analysisRepositoryProvider).analyzeFromText(text));

  Future<void> runVoice() => _handle(
      () => ref.read(analysisRepositoryProvider).analyzeFromVoice('mock_audio'));

  Future<void> runImages(List<String> refs, {String text = ''}) => _handle(() =>
      ref.read(analysisRepositoryProvider).analyzeFromImages(refs, text: text));

  /// بعد إجابة أسئلة المتابعة: إعادة تطبيق القواعد ثم التوصية.
  Future<void> proceedAfterFollowUp(FurnishingProject updated) async {
    final finalized = ref.read(analysisRepositoryProvider).finalizeManual(updated);
    await _recommend(finalized);
  }

  /// تخطّي أسئلة المتابعة والمضي بالتوصيات على المتوفّر.
  Future<void> skipFollowUp() async {
    final p = state.project;
    if (p != null) await _recommend(p);
  }

  /// حفظ المشروع الحالي (PRD — حفظ المشاريع).
  Future<Result<void>> saveCurrent() async {
    final p = state.project;
    if (p == null) {
      return const Err<void>(ValidationFailure('لا يوجد مشروع نشط للحفظ.'));
    }
    return ref.read(projectRepositoryProvider).save(p);
  }

  void reset() => state = const FurnishingFlowState();

  // ---- داخلي ----

  Future<void> _handle(
      Future<Result<FurnishingProject>> Function() run) async {
    state = state.copyWith(status: FlowStatus.extracting);
    final res = await run();
    switch (res) {
      case Ok(:final value):
        await _afterAnalysis(value);
      case Err(:final failure):
        state = state.copyWith(status: FlowStatus.error, failure: failure);
    }
  }

  Future<void> _afterAnalysis(FurnishingProject project) async {
    if (project.nextActions.hasFollowUps) {
      state = state.copyWith(status: FlowStatus.needsFollowUp, project: project);
      return;
    }
    await _recommend(project);
  }

  Future<void> _recommend(FurnishingProject project) async {
    state = state.copyWith(status: FlowStatus.recommending, project: project);
    final res = await ref.read(recommendationRepositoryProvider).recommend(project);
    state = switch (res) {
      Ok(:final value) => state.copyWith(status: FlowStatus.ready, project: value),
      Err(:final failure) =>
        state.copyWith(status: FlowStatus.error, failure: failure),
    };
  }

}
