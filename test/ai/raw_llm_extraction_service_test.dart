import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/models/normalized_input.dart';
import 'package:furn_app/ai/services/raw_llm_extraction_service.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/shared/models/models.dart';

/// The real LLM path, driven without a network: an injected completion
/// function stands in for the provider, so the whole seam — prompt in, raw
/// out, parsed project — is testable end to end.
void main() {
  const input = NormalizedInput(rawText: 'غرفة نوم 4 في 6، ميزانية 1800');

  RawLlmExtractionService serviceReturning(String raw) =>
      RawLlmExtractionService(complete: (_) async => raw);

  final projectJson = jsonEncode({
    'project_id': 'p1',
    'room': {'width_m': 4, 'length_m': 6, 'room_type': 'bedroom'},
    'budget': {'max_total': 1800},
  });

  test('a provider that returns clean JSON yields a structured project',
      () async {
    final r = await serviceReturning(projectJson).extract(input);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull?.budget.maxTotal, 1800);
  });

  test('a provider that wraps JSON in prose still parses', () async {
    final r =
        await serviceReturning('Sure! ```json\n$projectJson\n```').extract(input);
    expect(r.valueOrNull?.room.roomType, RoomType.bedroom);
  });

  test('the prompt carries the user text and reaches the provider', () async {
    late String seenPrompt;
    final service = RawLlmExtractionService(complete: (p) async {
      seenPrompt = p;
      return projectJson;
    });
    await service.extract(input);
    expect(seenPrompt, contains('غرفة نوم 4 في 6'));
  });

  test('vision signals are included when present', () async {
    late String seenPrompt;
    final service = RawLlmExtractionService(complete: (p) async {
      seenPrompt = p;
      return projectJson;
    });
    await service.extract(const NormalizedInput(
        rawText: 'أثّث', visionSummary: 'غرفة مضيئة بنافذة واحدة'));
    expect(seenPrompt, contains('Vision Signals'));
    expect(seenPrompt, contains('نافذة واحدة'));
  });

  test('a provider throwing is a clean failure, not an escaping exception',
      () async {
    final service = RawLlmExtractionService(
        complete: (_) async => throw Exception('network down'));
    final r = await service.extract(input);
    expect(r.isErr, isTrue);
    expect(r.failureOrNull, isA<AiParsingFailure>());
  });

  test('a provider returning non-project JSON fails rather than blank-accepts',
      () async {
    final r = await serviceReturning('{"unexpected": true}').extract(input);
    expect(r.isErr, isTrue);
  });

  test('the extractor never fills recommendations (engine owns those)',
      () async {
    final r = await serviceReturning(projectJson).extract(input);
    expect(r.valueOrNull?.recommendations.isEmpty, isTrue);
  });
}
