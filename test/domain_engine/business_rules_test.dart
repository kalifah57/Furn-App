import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/business_rules/business_rules_engine.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  const engine = BusinessRulesEngine();

  FurnishingProject project({
    double w = 4,
    double l = 6,
    double budget = 1800,
    List<RequestedItem> essential = const [RequestedItem(type: 'bed')],
    List<String> style = const ['modern'],
    double confidence = 0.8,
  }) =>
      FurnishingProject(
        projectId: 't',
        room: Room(widthM: w, lengthM: l, roomType: RoomType.bedroom),
        budget: Budget(maxTotal: budget),
        style: StylePreferences(preferred: style),
        items: RequestedItems(essential: essential),
        analysis: RoomAnalysis(confidenceScore: confidence),
      );

  test('complete input needs no follow-up', () {
    final r = engine.apply(project());
    expect(r.analysis.missingInformation, isEmpty);
    expect(r.nextActions.followUpQuestions, isEmpty);
  });

  test('missing dimensions produce follow-up and ask for images', () {
    final r = engine.apply(project(w: 0, l: 0));
    expect(r.analysis.missingInformation.any((m) => m.contains('أبعاد')), isTrue);
    expect(r.nextActions.followUpQuestions, isNotEmpty);
    expect(r.nextActions.askForImages, isTrue);
  });

  test('missing budget is flagged', () {
    final r = engine.apply(project(budget: 0));
    expect(r.analysis.missingInformation.any((m) => m.contains('ميزانية')), isTrue);
  });

  test('illogical dimensions raise a warning', () {
    final r = engine.apply(project(w: 100, l: 100));
    expect(r.analysis.warnings.any((w) => w.contains('غير منطقية')), isTrue);
  });

  test('no essential items produces a follow-up', () {
    final r = engine.apply(project(essential: const []));
    expect(r.analysis.missingInformation.any((m) => m.contains('أساسية')), isTrue);
  });
}
