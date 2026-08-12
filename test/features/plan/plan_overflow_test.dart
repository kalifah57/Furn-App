import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/analytics/analytics.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/features/plan/data/plan_draft_store.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart';
import 'package:furn_app/features/plan/presentation/plan_screen.dart';
import 'package:furn_app/shared/services/catalog_repository.dart';

import '../../support/arabic_app.dart';

/// X9 بند ٣: بلا الخطّ المتوقّع تنهار الصفوف غير المرنة (بطاقة الثقة، صفوف
/// غرفتي). التخطيط يجب أن يتحمّل أيّ خطٍّ بديل بلا فيضان — نُثبته على عرضٍ ضيّق:
/// أيّ صفٍّ ذي عرضٍ ثابت يتجاوز المساحة يرمي استثناء overflow نلتقطه هنا.
class _Noop implements Analytics {
  @override
  void track(AnalyticsEvent event) {}
}

void main() {
  testWidgets('غرفتي لا تفيض على عرضٍ ضيّق (٣٢٠)', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final disk = <String, String>{};
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(_Noop()),
        catalogRepositoryProvider
            .overrideWithValue(const InMemoryCatalogRepository([])),
        planDraftStoreProvider.overrideWithValue(PlanDraftStore(
          read: (k) => disk[k],
          write: (k, v) => disk[k] = v,
        )),
      ],
      child: arabicApp(const PlanScreen()),
    ));
    await tester.pumpAndSettle();

    // بطاقة الثقة والميزانية تُصيَّران دائمًا؛ عرضٌ ضيّق يكشف أيّ صفٍّ غير مرن.
    expect(find.text('ثقتك في الخطة'), findsOneWidget);
    expect(find.text('الميزانية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
