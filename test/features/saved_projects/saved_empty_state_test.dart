import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/features/saved_projects/domain/project_repository.dart';
import 'package:furn_app/features/saved_projects/presentation/saved_projects_screen.dart';
import 'package:furn_app/shared/models/furnishing_project.dart';
import 'package:furn_app/core/di/providers.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/core/errors/result.dart';

import '../../support/arabic_app.dart';

/// X9 بند ٥: فراغ «مشاريعي المحفوظة» كان سطرًا عاريًا في طريقٍ مسدود. يجب أن
/// يصير بمستوى X1: أيقونة + جملة + مخرجٌ يخرج منه المستخدم.
class _EmptyRepo implements ProjectRepository {
  @override
  Future<Result<void>> save(FurnishingProject project) async => const Ok(null);

  @override
  Future<Result<List<FurnishingProject>>> listProjects() async =>
      const Ok(<FurnishingProject>[]);

  @override
  Future<Result<FurnishingProject>> getById(String projectId) async =>
      const Err(NotFoundFailure());

  @override
  Future<Result<void>> delete(String projectId) async => const Ok(null);
}

void main() {
  testWidgets('الفراغ يعرض أيقونة وجملة ومخرجًا إلى المساعد', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(_EmptyRepo()),
      ],
      child: arabicApp(const SavedProjectsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmarks_outlined), findsOneWidget);
    expect(find.text('ابدأ من المساعد'), findsOneWidget);
    // زرّ المخرج قابل للنقر (طريق غير مسدود).
    final button =
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });
}
