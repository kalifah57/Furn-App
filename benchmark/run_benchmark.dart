// Decision Benchmark — invariant-tier runner (see benchmark/README.md).
//
// Scores the REAL deterministic engine against OBJECTIVE invariants — rules
// that must hold regardless of taste (fit, availability, budget sanity,
// coverage, synonym mapping). These are auto-checkable, so this is the
// regression gate: exit code is non-zero if any invariant fails.
//
// The SUBJECTIVE quality tier (benchmark/canonical.*) is NOT scored here — it
// needs real cases + an expert rubric. This runner only proves the engine
// never violates a hard rule; it does not claim the recommendations are "good".
//
// Run from the repo root:
//   flutter pub get
//   dart run benchmark/run_benchmark.dart
//
// The Dart VM compiles only the pure-Dart engine subtree — no Flutter needed.

import 'dart:convert';
import 'dart:io';

import 'package:furn_app/domain_engine/recommendation/recommendation_engine.dart';
import 'package:furn_app/shared/models/models.dart';

const _catalogPath = 'assets/catalog/catalog.json';
const _casesPath = 'benchmark/invariants.json';
const _reportPath = 'benchmark/invariants_report.md';

void main() {
  final catalog = _loadCatalog(_catalogPath);
  final byId = {for (final p in catalog) p.productId: p};
  final cases = _loadJsonList(_casesPath);
  const engine = RecommendationEngine();

  final out = StringBuffer()
    ..writeln('# Decision Benchmark — invariant tier')
    ..writeln()
    ..writeln('Objective auto-checks over the real engine '
        '(${catalog.length} products · ${cases.length} invariants). '
        'Taste/quality is scored separately by an expert (canonical tier).')
    ..writeln();

  var passed = 0;
  final failing = <String>[];

  for (final c in cases) {
    final id = '${c['id']}';
    final project = FurnishingProject.fromJson(_asMap(c['project']));
    final recs = engine.generate(project, catalog);
    final problems = _check(recs, project, _asMap(c['assert']), byId);

    if (problems.isEmpty) {
      passed++;
    } else {
      failing.add(id);
    }
    out.writeln('- ${problems.isEmpty ? '✅ PASS' : '❌ FAIL'} · '
        '`$id` — ${c['title']}');
    for (final p in problems) {
      out.writeln('    - $p');
    }
  }

  out
    ..writeln()
    ..writeln('## Result: $passed/${cases.length} invariants pass'
        '${failing.isEmpty ? '' : ' — FAILING: ${failing.join(', ')}'}');

  final report = out.toString();
  stdout.write(report);
  File(_reportPath).writeAsStringSync(report);
  stderr.writeln('\n[benchmark] $passed/${cases.length} invariants passed');
  if (failing.isNotEmpty) exitCode = 1; // regression gate
}

/// Returns a list of invariant violations for one case (empty = pass).
List<String> _check(
  Recommendations recs,
  FurnishingProject project,
  Map<String, dynamic> a,
  Map<String, CatalogProduct> byId,
) {
  final problems = <String>[];

  // expect_no_recommendations short-circuits the rest.
  if (a['expect_no_recommendations'] == true) {
    if (!recs.isEmpty) {
      problems.add('expected no recommendations, engine returned some');
    }
    return problems;
  }

  final recItems = <RecommendedItem>[
    ...recs.individualItems,
    for (final b in recs.bundles) ...b.items,
  ];
  CatalogProduct? productOf(RecommendedItem it) =>
      it.productId == null ? null : byId[it.productId];

  // 1) never recommend an out-of-stock product (default on).
  if (a['no_out_of_stock'] != false) {
    for (final it in recItems) {
      final p = productOf(it);
      if (p != null && !p.isAvailable) {
        problems.add('out-of-stock item recommended: ${p.productId}');
      }
    }
  }

  // 2) every recommended product must physically fit the room (skip if no dims).
  if (a['all_fit_room'] != false) {
    final r = project.room;
    if (r.widthM > 0 && r.lengthM > 0) {
      final roomW = r.widthM * 100, roomL = r.lengthM * 100;
      for (final it in recItems) {
        final p = productOf(it);
        if (p == null) continue;
        final fitsDirect = p.widthCm <= roomW && p.depthCm <= roomL;
        final fitsRotated = p.depthCm <= roomW && p.widthCm <= roomL;
        if (!fitsDirect && !fitsRotated) {
          problems.add('item does not fit room: ${p.productId}');
        }
      }
    }
  }

  // 3) no single individual item may cost more than the whole budget.
  if (a['no_item_exceeds_budget'] != false && project.budget.hasBudget) {
    for (final it in recs.individualItems) {
      if (it.price > project.budget.maxTotal) {
        problems.add('individual item above total budget: '
            '${it.productId} (${it.price} > ${project.budget.maxTotal})');
      }
    }
  }

  // 4) explicit exclusions must not appear.
  for (final pid in _asStrList(a['must_exclude'])) {
    if (recItems.any((it) => it.productId == pid)) {
      problems.add('must-exclude product appeared: $pid');
    }
  }

  // 5) requested categories must be covered by at least one individual item.
  for (final wire in _asStrList(a['must_cover_categories'])) {
    final cat = RecommendationCategory.fromWire(wire);
    if (!recs.individualItems.any((it) => it.category == cat)) {
      problems.add('required category not covered: $wire');
    }
  }

  return problems;
}

// ---------------------------------------------------------------- loaders

List<CatalogProduct> _loadCatalog(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .map((e) => CatalogProduct.fromJson(_asMap(e)))
        .toList();

List<Map<String, dynamic>> _loadJsonList(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List).map(_asMap).toList();

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<String> _asStrList(Object? v) =>
    v is List ? v.map((e) => '$e').toList() : const <String>[];
