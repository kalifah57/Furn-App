import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/core/router/app_router.dart';
import 'package:furn_app/features/plan/data/plan_draft_store.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart';
import 'package:furn_app/features/plan/presentation/plan_screen.dart';
import 'package:furn_app/features/room_input/presentation/assistant_screen.dart';
import 'package:furn_app/shared/services/catalog_repository.dart';
import 'package:go_router/go_router.dart';

import '../../support/arabic_app.dart';

/// **حارس القِمع** — شرط قبول X0.
///
/// الهيكل الثلاثي يضع «غرفتي» على بُعد سحبةٍ واحدة، و`PageView` يبني الصفحة
/// المجاورة أثناء السحب. لو بُني `PlanScreen` هكذا لأُطلق `plan_seeded` قبل أن
/// يصل المستخدم — أي يزيّف القِمع الذي نقيس به التفعيل، وهو نفس ما منعه تسطيح
/// المسارات في ADR-0002.
///
/// السلسلة التي تُثبتها هذه الاختبارات: لا تركيب لـ`PlanScreen` ⇒ لا مراقبة
/// لـ`planControllerProvider` ⇒ لا `PlanController` ⇒ لا `PlanSeeded`.
class _Recorder implements Analytics {
  final events = <AnalyticsEvent>[];

  @override
  void track(AnalyticsEvent event) => events.add(event);
}

void main() {
  late _Recorder analytics;
  late Map<String, String> disk;

  List<PlanSeeded> seeded() =>
      analytics.events.whereType<PlanSeeded>().toList();

  GoRouter routerAt(String location) =>
      GoRouter(initialLocation: location, routes: appRoutes);

  Future<void> pumpAt(WidgetTester tester, GoRouter router) async {
    analytics = _Recorder();
    disk = <String, String>{};
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(analytics),
        // كتالوج فارغ يكفي: الخطة تُبنى وتُبذَر، وهذا كل ما يقيسه الحارس.
        catalogRepositoryProvider
            .overrideWithValue(const InMemoryCatalogRepository([])),
        planDraftStoreProvider.overrideWithValue(PlanDraftStore(
          read: (k) => disk[k],
          write: (k, v) => disk[k] = v,
        )),
      ],
      child: arabicRouterApp(router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('الفتح على المساعد لا يبني «غرفتي» ولا يُطلق plan_seeded',
      (tester) async {
    await pumpAt(tester, routerAt(Routes.assistant));

    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(find.byType(PlanScreen), findsNothing); // لم تُركَّب أصلًا
    expect(seeded(), isEmpty); // ومن ثمّ لا حدث
  });

  testWidgets('البقاء على الصفحة الأولى يبقيه صامتًا', (tester) async {
    await pumpAt(tester, routerAt(Routes.assistant));

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(seeded(), isEmpty);
  });

  testWidgets('حين تستقرّ «غرفتي» صفحةً حالية يُطلق مرّةً واحدة', (tester) async {
    final router = routerAt(Routes.assistant);
    await pumpAt(tester, router);
    expect(seeded(), isEmpty);

    router.go(Routes.room);
    await tester.pumpAndSettle();

    expect(find.byType(PlanScreen), findsOneWidget);
    expect(seeded(), hasLength(1));
  });

  testWidgets('السحب إلى «غرفتي» يبنيها ويحدّث العنوان', (tester) async {
    final router = routerAt(Routes.assistant);
    await pumpAt(tester, router);

    // RTL: الصفحة الأولى يمينًا، فالتالية تُجلب بسحب الإصبع يمينًا.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.byType(PlanScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.room);
    expect(seeded(), hasLength(1));
  });

  testWidgets('الرابط العميق إلى /room يبني «غرفتي» مباشرة', (tester) async {
    await pumpAt(tester, routerAt(Routes.room));

    expect(find.byType(PlanScreen), findsOneWidget);
    expect(find.byType(AssistantScreen), findsNothing); // لم تستقرّ فلم تُركَّب
    expect(seeded(), hasLength(1));
  });

  testWidgets('الباب يُحوّل إلى المساعد بدل أن يسقط في صفحة خطأ', (tester) async {
    final router = routerAt(Routes.onboarding);
    await pumpAt(tester, router);

    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.assistant);
    expect(seeded(), isEmpty);
  });
}
