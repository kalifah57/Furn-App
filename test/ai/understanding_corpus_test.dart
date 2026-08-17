import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/ai/mock/mock_llm_extraction_service.dart';
import 'package:furn_app/ai/models/normalized_input.dart';
import 'package:furn_app/ai/parsing/plan_command.dart';
import 'package:furn_app/ai/parsing/plan_command_parser.dart';
import 'package:furn_app/core/errors/result.dart';
import 'package:furn_app/core/utils/text_normalizer.dart';
import 'package:furn_app/shared/models/models.dart';

/// منصّة اختبار الفهم (D-style) — تشغّل مجموعة `understanding_corpus.json`
/// على المُحلِّلَين وتُخرج الدقّة. حالات `strict` تُختبَر خضراء؛ حالات `baseline`
/// تُعدّ وتُحرَس بأرضية لا تنحدر. هذا هو المكان الذي «تُعاد فيه أرقام المحاكي في
/// flutter test» — إن اختلفت عن تقرير الدورة فالكود هو الحكم.
void main() {
  final root = jsonDecode(
    File('test/ai/fixtures/understanding_corpus.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final commands =
      (root['commands'] as List).cast<Map<String, dynamic>>();
  final extraction =
      (root['extraction'] as List).cast<Map<String, dynamic>>();

  const parser = PlanCommandParser();

  // ─────────────────────── سطح أوامر المساعد ───────────────────────
  group('أوامر المساعد', () {
    for (final c in commands.where((c) => c['assert'] == 'strict')) {
      test('${c['id']}: ${c['in']}', () {
        final got = _cmd(parser.parse(c['in'] as String));
        expect(_accepts(c, got), isTrue,
            reason: 'got=$got · exp=${c['expect'] ?? c['accept']}');
      });
    }

    test('baseline لا ينحدر (أرضية 0.40)', () {
      final base = commands.where((c) => c['assert'] == 'baseline').toList();
      var pass = 0;
      for (final c in base) {
        if (_accepts(c, _cmd(parser.parse(c['in'] as String)))) pass++;
      }
      // ignore: avoid_print
      print('أوامر baseline: $pass/${base.length} '
          '(${(100 * pass / base.length).round()}%)');
      expect(pass / base.length, greaterThanOrEqualTo(0.40));
    });
  });

  // ─────────────────────── سطح الاستخراج الحرّ ───────────────────────
  group('استخراج الوصف الحرّ', () {
    final service = MockLlmExtractionService(uuidFactory: () => 'proj_test');

    for (final e in extraction.where((e) => e['assert'] == 'strict')) {
      test('${e['id']}: ${e['in']}', () async {
        final res = await service
            .extract(NormalizedInput(rawText: normalizeInput(e['in'] as String)));
        final p = (res as Ok<FurnishingProject>).value;
        final exp = e['expect'] as Map<String, dynamic>;

        if (exp.containsKey('room_type')) {
          expect(p.room.roomType.wire, exp['room_type']);
        }
        if (exp.containsKey('width_m')) {
          expect(p.room.widthM, (exp['width_m'] as num).toDouble());
        }
        if (exp.containsKey('length_m')) {
          expect(p.room.lengthM, (exp['length_m'] as num).toDouble());
        }
        if (exp.containsKey('budget')) {
          expect(p.budget.maxTotal, (exp['budget'] as num).toDouble());
        }
        if (exp.containsKey('flexible')) {
          expect(p.budget.flexible, exp['flexible']);
        }
        if (exp.containsKey('essential')) {
          final want = (exp['essential'] as List).cast<String>();
          final got = p.items.essential.map((x) => x.type).toSet();
          expect(got.containsAll(want), isTrue, reason: 'essential=$got');
          if (want.isEmpty) expect(p.items.essential, isEmpty);
        }
        if (exp.containsKey('optional')) {
          final got = p.items.optional.map((x) => x.type).toSet();
          expect(got.containsAll((exp['optional'] as List).cast<String>()),
              isTrue, reason: 'optional=$got');
        }
        if (exp.containsKey('constraints')) {
          final want = (exp['constraints'] as List).cast<String>().toSet();
          expect(
              p.items.essential
                  .any((x) => x.constraints.toSet().containsAll(want)),
              isTrue,
              reason: 'no item carries $want');
        }
        if (exp.containsKey('style')) {
          expect(
              p.style.preferred
                  .toSet()
                  .containsAll((exp['style'] as List).cast<String>()),
              isTrue);
        }
        if (exp.containsKey('colors')) {
          expect(
              p.style.colors
                  .toSet()
                  .containsAll((exp['colors'] as List).cast<String>()),
              isTrue,
              reason: 'colors=${p.style.colors}');
        }
        if (exp.containsKey('out_of_scope')) {
          final joined = p.analysis.warnings.join(' ');
          for (final label in (exp['out_of_scope'] as List).cast<String>()) {
            expect(joined.contains(label), isTrue,
                reason: 'warning missing "$label" in ${p.analysis.warnings}');
          }
        }
        // الحدّ الجوهري: المُخرَج بيانات لا قرار — التوصيات فارغة دائمًا.
        expect(p.recommendations.isEmpty, isTrue);
      });
    }
  });
}

Map<String, Object> _cmd(PlanCommand c) => switch (c) {
      SetBudgetCommand() => {'intent': 'set_budget', 'amount': c.amountSar},
      NudgeBudgetCommand() => {'intent': 'nudge_budget', 'direction': c.direction},
      AddCategoryCommand() => {'intent': 'add', 'category': c.category.wire},
      RemoveCategoryCommand() => {'intent': 'remove', 'category': c.category.wire},
      FinalizeCommand() => {'intent': 'finalize'},
      UnknownCommand() => {'intent': 'unknown'},
    };

bool _one(Map<String, Object> got, Map exp) => exp.entries.every((e) {
      final v = e.value;
      if (v is num) return (got[e.key] as num?)?.toDouble() == v.toDouble();
      return got[e.key] == v;
    });

bool _accepts(Map<String, dynamic> c, Map<String, Object> got) =>
    c.containsKey('expect')
        ? _one(got, c['expect'] as Map)
        : (c['accept'] as List).cast<Map>().any((a) => _one(got, a));
