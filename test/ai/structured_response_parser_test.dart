import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/parsing/structured_response_parser.dart';
import 'package:furn_app/core/errors/failure.dart';
import 'package:furn_app/shared/models/models.dart';

/// The parser turns a real LLM's messy output into a structured project.
/// The cases that matter are the ones that would otherwise pass garbage to the
/// user as if it were understood.
void main() {
  const parser = StructuredResponseParser();

  final validJson = jsonEncode({
    'project_id': 'p1',
    'room': {'width_m': 4, 'length_m': 6, 'room_type': 'bedroom'},
    'budget': {'max_total': 1800},
    'analysis': {'confidence_score': 0.8},
  });

  group('clean and near-clean input', () {
    test('parses valid JSON into a structured model', () {
      final r = parser.parse(validJson);
      expect(r.isOk, isTrue);
      expect(r.valueOrNull?.room.roomType, RoomType.bedroom);
      expect(r.valueOrNull?.budget.maxTotal, 1800);
    });

    test('repairs markdown-fenced JSON (```json ... ```)', () {
      final r = parser.parse('```json\n$validJson\n```');
      expect(r.isOk, isTrue);
      expect(r.valueOrNull?.room.lengthM, 6);
    });

    test('extracts a JSON object embedded in prose', () {
      final r = parser.parse('Here is the result: $validJson . Done.');
      expect(r.isOk, isTrue);
      expect(r.valueOrNull?.projectId, 'p1');
    });

    test('a trailing sentence with a brace does not get swallowed', () {
      // The old lastIndexOf('}') would have reached into this tail.
      final r = parser.parse('$validJson thanks! {note: ignore this}');
      expect(r.isOk, isTrue);
      expect(r.valueOrNull?.projectId, 'p1');
    });

    test('nested objects are balanced, not truncated at the first close', () {
      final nested = jsonEncode({
        'project_id': 'p2',
        'room': {'width_m': 3, 'length_m': 3},
        'style': {'preferred': ['modern'], 'colors': ['gray']},
      });
      final r = parser.parse('prefix $nested suffix');
      expect(r.valueOrNull?.projectId, 'p2');
      expect(r.valueOrNull?.style.preferred, contains('modern'));
    });
  });

  group('input that must fail loudly', () {
    test('returns AiParsingFailure on unparsable input', () {
      final r = parser.parse('not json at all');
      expect(r.isErr, isTrue);
      expect(r.failureOrNull, isA<AiParsingFailure>());
    });

    test('valid JSON that is not a project is rejected, not blank-accepted', () {
      // The core guard: {"foo":1} decodes fine, but fromJson would yield a
      // blank project with an empty id and zero dimensions — silently wrong.
      final r = parser.parse('{"foo": 1, "bar": [1,2,3]}');
      expect(r.isErr, isTrue);
      expect(r.failureOrNull, isA<AiParsingFailure>());
    });

    test('an empty project_id is treated as not-a-project', () {
      final r = parser.parse(jsonEncode({'project_id': '  ', 'room': {}}));
      expect(r.isErr, isTrue);
    });

    test('a JSON array is not a project', () {
      final r = parser.parse('[1, 2, 3]');
      expect(r.isErr, isTrue);
    });

    test('an unbalanced object fails rather than half-parsing', () {
      final r = parser.parse('{"project_id": "p1", "room": {');
      expect(r.isErr, isTrue);
    });
  });

  test('parsing is deterministic', () {
    expect(parser.parse(validJson).valueOrNull?.projectId,
        parser.parse(validJson).valueOrNull?.projectId);
  });
}
