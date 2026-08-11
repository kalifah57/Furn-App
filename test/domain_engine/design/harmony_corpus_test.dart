import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/domain_engine/design/harmony.dart';

/// D4 — منصّة الاختبار: تشغّل المجموعة الذهبية v1 كاملة على المُقيّم، وتُخرج الدقّة
/// وقائمة الإخفاقات مصنّفة بالقاعدة. تقرير خطّ الأساس المكتوب: docs/design/09.
///
/// لا Flutter SDK في البيئة — تُشغَّل على CI؛ الأرقام مُثبَّتة بأوراكل مستقلّ قبل الكتابة.

HarmonyScene _scene(Map<String, dynamic> c) {
  final room = c['room'] as Map<String, dynamic>;
  final pieces = <HarmonyPiece>[];
  for (final pp in c['pieces'] as List) {
    final p = pp as Map<String, dynamic>;
    pieces.add(HarmonyPiece(
      category: p['category'] as String,
      styles: (p['style'] as List).cast<String>(),
      colors: (p['colors'] as List).cast<String>(),
      materials: (p['materials'] as List).cast<String>(),
      woodTone: p['wood_tone'] as String?,
      widthCm: (p['width_cm'] as num).toDouble(),
      depthCm: (p['depth_cm'] as num).toDouble(),
      heightCm: (p['height_cm'] as num).toDouble(),
      subcategory: (p['subcategory'] as String?) ?? '',
    ));
  }
  return HarmonyScene(
    roomType: room['type'] as String,
    widthM: (room['width_m'] as num).toDouble(),
    lengthM: (room['length_m'] as num).toDouble(),
    pieces: pieces,
  );
}

void main() {
  final dir = Directory('test/domain_engine/design/golden/v1');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json') && !f.path.endsWith('index.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final cases = <Map<String, dynamic>>[];
  for (final f in files) {
    for (final c in jsonDecode(f.readAsStringSync()) as List) {
      cases.add(c as Map<String, dynamic>);
    }
  }

  test('golden corpus v1 loads its 60 cases', () {
    expect(dir.existsSync(), isTrue, reason: 'run from package root');
    expect(cases.length, 60);
  });

  test('evaluateHarmony is deterministic across runs', () {
    for (final c in cases) {
      final s = _scene(c);
      final a = evaluateHarmony(s);
      final b = evaluateHarmony(s);
      expect(a.verdict, b.verdict);
      expect(a.firedRules, b.firedRules);
    }
  });

  test('v0 baseline accuracy with classified failures', () {
    var correct = 0;
    final totalByCat = <String, int>{};
    final failByCat = <String, int>{};
    final failByRule = <String, int>{};
    final misses = <String>[];

    for (final c in cases) {
      final cat = c['category'] as String;
      final rule = c['rule'] as String;
      totalByCat[cat] = (totalByCat[cat] ?? 0) + 1;
      final expected = (c['expected'] as Map)['verdict'] as String;
      final got = evaluateHarmony(_scene(c)).isHarmonious ? 'harmonious' : 'dissonant';
      if (got == expected) {
        correct++;
      } else {
        failByCat[cat] = (failByCat[cat] ?? 0) + 1;
        failByRule[rule] = (failByRule[rule] ?? 0) + 1;
        misses.add('${c['id']} [$cat/$rule] expected=$expected got=$got');
      }
    }

    final acc = correct / cases.length * 100;
    final report = StringBuffer()
      ..writeln('\n=== Harmony v0 baseline (D4) ===')
      ..writeln('accuracy: $correct/${cases.length} = ${acc.toStringAsFixed(1)}%');
    for (final k in totalByCat.keys.toList()..sort()) {
      report.writeln('  $k: ${totalByCat[k]! - (failByCat[k] ?? 0)}/${totalByCat[k]} correct');
    }
    report.writeln('failures by rule: '
        '${{for (final r in failByRule.keys.toList()..sort()) r: failByRule[r]}}');
    for (final m in misses) {
      report.writeln('  MISS $m');
    }
    // ignore: avoid_print
    print(report.toString());

    // Baseline ratchet — D5 raises this as rules are added; never lowered.
    const kBaselineCorrect = 50;
    expect(correct, greaterThanOrEqualTo(kBaselineCorrect),
        reason: 'v0 baseline is 50/60; a drop is a regression');
  });
}
