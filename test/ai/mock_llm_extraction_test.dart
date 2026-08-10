import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/models/normalized_input.dart';
import 'package:furn_app/ai/mock/mock_llm_extraction_service.dart';
import 'package:furn_app/core/errors/result.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  const service = MockLlmExtractionService();

  Future<FurnishingProject> extract(String text) async {
    final res = await service.extract(NormalizedInput(rawText: text));
    return (res as Ok<FurnishingProject>).value;
  }

  test('extracts dimensions, budget, and items from the PRD example', () async {
    final p = await extract(
      'غرفة نوم 4 في 6، أبي سرير وكنب صغير، وإذا الميزانية تسمح أضيف سجادة، '
      'وميزانيتي 1800 ريال',
    );

    expect(p.room.roomType, RoomType.bedroom);
    expect(p.room.widthM, 4);
    expect(p.room.lengthM, 6);
    expect(p.budget.maxTotal, 1800);
    expect(p.budget.flexible, isTrue);
    expect(p.items.essential.map((e) => e.type), containsAll(['bed', 'sofa']));
    expect(p.items.optional.map((e) => e.type), contains('rug'));
    // الـ LLM لا يُنتج توصيات — يملؤها المحرّك لاحقًا.
    expect(p.recommendations.isEmpty, isTrue);
  });

  test('normalizes Arabic-Indic digits', () async {
    final p = await extract('غرفة ٣ في ٤ وميزانيتي ٩٠٠ ريال');
    expect(p.room.widthM, 3);
    expect(p.room.lengthM, 4);
    expect(p.budget.maxTotal, 900);
  });

  test('small bed constraint is captured', () async {
    final p = await extract('أبي سرير صغير');
    final bed = p.items.essential.firstWhere((e) => e.type == 'bed');
    expect(bed.constraints, contains('small'));
  });
}
