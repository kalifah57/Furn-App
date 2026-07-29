import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/parsing/structured_response_parser.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  const parser = StructuredResponseParser();

  final validJson = jsonEncode({
    'project_id': 'p1',
    'room': {'width_m': 4, 'length_m': 6, 'room_type': 'bedroom'},
    'budget': {'max_total': 1800},
    'analysis': {'confidence_score': 0.8},
  });

  test('parses valid JSON into a structured model', () {
    final r = parser.parse(validJson);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull?.room.roomType, RoomType.bedroom);
    expect(r.valueOrNull?.budget.maxTotal, 1800);
  });

  test('repairs markdown-fenced JSON (```json ... ```)', () {
    final fenced = '```json\n$validJson\n```';
    final r = parser.parse(fenced);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull?.room.lengthM, 6);
  });

  test('extracts a JSON object embedded in prose', () {
    final r = parser.parse('Here is the result: $validJson . Done.');
    expect(r.isOk, isTrue);
  });

  test('returns AiParsingFailure on unparsable input', () {
    final r = parser.parse('not json at all');
    expect(r.isErr, isTrue);
    expect(r.failureOrNull, isA<AiParsingFailure>());
  });
}
