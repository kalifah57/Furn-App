import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/models/normalized_input.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/core/errors/result.dart';
import 'package:furn_app/features/recommendations/domain/recommendation_repository.dart';
import 'package:furn_app/features/room_analysis/domain/analysis_repository.dart';
import 'package:furn_app/features/room_input/presentation/assistant_screen.dart';
import 'package:furn_app/features/room_input/presentation/flow_controller.dart';
import 'package:furn_app/shared/models/models.dart';

import '../../support/arabic_app.dart';

/// X8 — أسئلة المتابعة داخل المحادثة، لا نافذة. حين ينقص المحرّك تفصيلٌ، يسأل
/// فقاعةً في الشات بخياراتٍ قابلة للنقر، والنقرة تُجيب وتُكمل التدفّق تلقائيًّا.

/// مشروعٌ يُعيده التحليل ناقصًا (بلا قطع أساسية ولا نمط) فيطلب المحرّك متابعة.
const _followUpProject = FurnishingProject(
  projectId: 'p',
  budget: Budget(maxTotal: 3000),
  nextActions:
      NextActions(followUpQuestions: ['ما القطع الأساسية التي تريدها؟']),
);

class _FollowUpAnalysis implements AnalysisRepository {
  const _FollowUpAnalysis(this.project);
  final FurnishingProject project;

  @override
  Future<Result<FurnishingProject>> analyzeFromText(String text,
          {InputSource source = InputSource.text}) async =>
      Ok(project);

  @override
  Future<Result<FurnishingProject>> analyzeFromVoice(String audioRef) async =>
      Ok(project);

  @override
  Future<Result<FurnishingProject>> analyzeFromImages(List<String> imageRefs,
          {String text = ''}) async =>
      Ok(project);

  @override
  FurnishingProject finalizeManual(FurnishingProject draft) => draft;
}

/// توصيةٌ لا تكتمل: تُبقي الحالة على «يفكّر» بعد الإجابة، فنرصد التقدّم دون أن
/// يقفز التدفّق إلى غرفتي (الذي يحتاج راوترًا).
class _PendingRecommend implements RecommendationRepository {
  const _PendingRecommend();
  @override
  Future<Result<FurnishingProject>> recommend(FurnishingProject project) =>
      Completer<Result<FurnishingProject>>().future;
}

void main() {
  ProviderContainer container() => ProviderContainer(overrides: [
        analyticsProvider.overrideWithValue(const NoopAnalytics()),
        analysisRepositoryProvider
            .overrideWithValue(const _FollowUpAnalysis(_followUpProject)),
        recommendationRepositoryProvider
            .overrideWithValue(const _PendingRecommend()),
      ]);

  Future<ProviderContainer> pumpToFollowUp(WidgetTester tester) async {
    final c = container();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: arabicApp(const AssistantScreen()),
    ));
    await c.read(furnishingFlowControllerProvider.notifier).runText('غرفة نوم');
    await tester.pump();
    await tester.pump();
    return c;
  }

  testWidgets('السؤال يظهر فقاعةً بخياراتٍ داخل الشات، لا نافذة', (tester) async {
    await pumpToFollowUp(tester);

    // خيارات قابلة للنقر داخل المحادثة نفسها + «تخطَّ».
    expect(find.text('سرير'), findsOneWidget); // قطعة أساسية
    expect(find.text('مودرن'), findsOneWidget); // نمط
    expect(find.text('تخطَّ'), findsOneWidget);
    // والمحرّك خاطبنا في الشات بدل أن يدفع شاشة.
    expect(find.text('أحتاج تفصيلًا بسيطًا لأكمل خطتك — اختر أو تخطَّ:'),
        findsOneWidget);
  });

  testWidgets('نقرة الخيار تُجيب وتُكمل التدفّق', (tester) async {
    final c = await pumpToFollowUp(tester);

    await tester.tap(find.text('سرير'));
    await tester.pump();

    // الخيارات اختفت وظهر مؤشّر الكتابة — أي أن النقرة أجابت ومضت بالتدفّق.
    expect(find.text('سرير'), findsNothing);
    expect(find.text('أفكّر في خطتك…'), findsOneWidget);
    // والقطعة المختارة دخلت المشروع (بقيمتها التي يفهمها المحرّك).
    final project = c.read(furnishingFlowControllerProvider).project!;
    expect(project.items.essential.any((e) => e.type == 'bed'), isTrue);
  });

  testWidgets('«تخطَّ» يمضي على المتوفّر دون إضافة', (tester) async {
    final c = await pumpToFollowUp(tester);

    await tester.tap(find.text('تخطَّ'));
    await tester.pump();

    expect(find.text('سرير'), findsNothing);
    expect(find.text('أفكّر في خطتك…'), findsOneWidget);
    final project = c.read(furnishingFlowControllerProvider).project!;
    expect(project.items.essential, isEmpty); // لم يُضَف شيء
  });
}
