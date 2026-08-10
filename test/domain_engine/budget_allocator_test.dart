import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/budget/budget_allocator.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  const allocator = BudgetAllocator();

  test('bedroom distribution matches the documented example', () {
    final a = allocator.allocate(
      const Room(widthM: 4, lengthM: 6, roomType: RoomType.bedroom),
      const Budget(maxTotal: 1800),
    );
    expect(a.percentages[RecommendationCategory.bed], 0.40);
    expect(a.percentages[RecommendationCategory.sofa], 0.20);
    expect(a.percentages[RecommendationCategory.storage], 0.15);
    // السقف بالريال = النسبة × الإجمالي.
    expect(a.ceilings[RecommendationCategory.bed], 720);
  });

  test('percentages sum to 1.0 for every room type', () {
    for (final type in RoomType.values) {
      final a = allocator.allocate(
        Room(widthM: 4, lengthM: 5, roomType: type),
        const Budget(maxTotal: 1000),
      );
      final sum = a.percentages.values.fold<double>(0, (s, v) => s + v);
      expect(sum, closeTo(1.0, 1e-9), reason: 'room type: $type');
    }
  });
}
