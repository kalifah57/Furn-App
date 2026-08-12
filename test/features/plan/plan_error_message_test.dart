import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/features/plan/presentation/plan_controller.dart';
import 'package:furn_app/features/plan/presentation/plan_screen.dart';
import 'package:furn_app/shared/widgets/status_views.dart';

import '../../support/arabic_app.dart';

/// X9 بند ٤: رسالة الخطأ كانت تقول «تحقّق من اتصالك» أيًّا كان السبب — تخمينٌ
/// لسببٍ لم يقع. القاعدة: الرسالة تنقل سبب الطبقة السفلى الحقيقي، ولا تخترع شبكة.
void main() {
  Future<void> pumpWithError(WidgetTester tester, Object error) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        planControllerProvider.overrideWith(
          (ref) => Future<PlanController>.error(error),
        ),
      ],
      child: arabicApp(const PlanScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('سببٌ معروف (Failure) يُعرَض كما هو، بلا ادّعاء شبكة',
      (tester) async {
    await pumpWithError(
        tester, const NotFoundFailure('لم نعثر على قائمة الأثاث بعد.'));

    expect(find.text('لم نعثر على قائمة الأثاث بعد.'), findsOneWidget);
    expect(find.textContaining('تحقّق من اتصالك'), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
  });

  testWidgets('سببٌ مجهول يُعطي عبارةً محايدة لا تخمّن شبكة', (tester) async {
    await pumpWithError(tester, Exception('boom'));

    expect(find.text('تعذّر تحميل خطتك. أعد المحاولة.'), findsOneWidget);
    expect(find.textContaining('تحقّق من اتصالك'), findsNothing);
    // ولا يُطبع الاستثناء الخام للمستخدم.
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });
}
