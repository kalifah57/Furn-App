// Decision Benchmark — permanent runner (see benchmark/README.md).
//
// A PERMANENT part of the project: the yardstick every engine change is
// measured against — not a throwaway test. It loads every scenario in
// benchmark/scenarios/, runs the REAL engine (domain_engine, pure Dart),
// evaluates each scenario's expected_constraints (hard gate) and
// acceptance_criteria (graded), merges any benchmark/expert_reviews/, and
// writes benchmark/reports/benchmark_report.md.
//
//   flutter pub get
//   dart run benchmark/benchmark_runner.dart
//
// Exit code is non-zero if any INVARIANT scenario violates a hard constraint,
// so it doubles as a regression gate.

import 'dart:convert';
import 'dart:io';

import 'package:furn_app/domain_engine/recommendation/recommendation_engine.dart';
import 'package:furn_app/shared/models/models.dart';

void main() {
  final root = Directory('benchmark/scenarios').existsSync() ? 'benchmark' : '.';
  final catalog = _loadCatalog('assets/catalog/catalog.json');
  final byId = {for (final p in catalog) p.productId: p};
  const engine = RecommendationEngine();

  final scenarios = _loadDir('$root/scenarios');
  scenarios.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
  final reviews = _loadReviews('$root/expert_reviews');

  final out = StringBuffer()
    ..writeln('# Decision Benchmark — report')
    ..writeln()
    ..writeln('Real engine · ${catalog.length} products · '
        '${scenarios.length} scenarios.')
    ..writeln();

  var invPass = 0, invTotal = 0;
  final invFailing = <String>[];
  final canonicalScores = <double>[];

  for (final s in scenarios) {
    final id = '${s['id']}';
    final project = FurnishingProject.fromJson(_asMap(s['input']));
    final recs = engine.generate(project, catalog);
    final ev = _evaluate(recs, project, s, byId);

    if ('${s['tier']}' == 'invariant') {
      invTotal++;
      if (ev.hardPass) {
        invPass++;
      } else {
        invFailing.add(id);
      }
      out.writeln('- ${ev.hardPass ? '✅' : '❌'} `$id` (invariant) — ${s['title']}');
    } else {
      final review = reviews[id];
      final score = _caseScore(ev, review);
      if (score != null) canonicalScores.add(score);
      out.writeln('- `$id` (canonical) — hard ${ev.hardPass ? 'pass' : 'FAIL'} · '
          'machine ${(ev.machineMet * 100).round()}% · '
          '${review == null ? 'expert: pending' : 'stars ${review.stars}'} · '
          'score ${score == null ? 'pending' : score.toStringAsFixed(2)}');
    }
    for (final v in ev.violations) {
      out.writeln('    - $v');
    }
  }

  final benchScore = canonicalScores.isEmpty
      ? null
      : canonicalScores.reduce((a, b) => a + b) / canonicalScores.length;

  out
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Invariants: $invPass/$invTotal pass'
        '${invFailing.isEmpty ? '' : ' — FAILING: ${invFailing.join(', ')}'}')
    ..writeln('- Canonical benchmark_score: '
        '${benchScore == null ? 'no scored cases yet' : benchScore.toStringAsFixed(3)}'
        ' (${canonicalScores.length} scored)');

  final report = out.toString();
  stdout.write(report);
  Directory('$root/reports').createSync(recursive: true);
  File('$root/reports/benchmark_report.md').writeAsStringSync(report);
  stderr.writeln('\n[benchmark] invariants $invPass/$invTotal'
      '${benchScore == null ? '' : ' · benchmark_score '
          '${benchScore.toStringAsFixed(3)}'}');
  if (invFailing.isNotEmpty) exitCode = 1;
}

class _Eval {
  _Eval(this.hardPass, this.machineMet, this.violations);
  final bool hardPass;
  final double machineMet;
  final List<String> violations;
}

_Eval _evaluate(
  Recommendations recs,
  FurnishingProject project,
  Map<String, dynamic> s,
  Map<String, CatalogProduct> byId,
) {
  final items = <RecommendedItem>[
    ...recs.individualItems,
    for (final b in recs.bundles) ...b.items,
  ];
  final violations = <String>[];

  var hard = true;
  for (final c in _asList(s['expected_constraints'])) {
    final cm = _asMap(c);
    if (!_holds(cm, recs, items, project, byId)) {
      hard = false;
      violations.add('constraint failed: ${jsonEncode(cm)}');
    }
  }

  final machine = _asList(_asMap(s['acceptance_criteria'])['machine']);
  var met = 0;
  for (final c in machine) {
    if (_holds(_asMap(c), recs, items, project, byId)) met++;
  }
  final machineMet = machine.isEmpty ? 1.0 : met / machine.length;

  return _Eval(hard, machineMet, violations);
}

/// The shared constraint library (documented in benchmark/constraints/catalog.md).
bool _holds(
  Map<String, dynamic> c,
  Recommendations recs,
  List<RecommendedItem> items,
  FurnishingProject project,
  Map<String, CatalogProduct> byId,
) {
  CatalogProduct? prod(RecommendedItem it) =>
      it.productId == null ? null : byId[it.productId];
  switch ('${c['type']}') {
    case 'no_recommendations':
      return recs.isEmpty;
    case 'in_stock':
      return items.every((it) {
        final p = prod(it);
        return p == null || p.isAvailable;
      });
    case 'fits_room':
      final r = project.room;
      if (r.widthM <= 0 || r.lengthM <= 0) return true;
      final rw = r.widthM * 100, rl = r.lengthM * 100;
      return items.every((it) {
        final p = prod(it);
        if (p == null) return true;
        return (p.widthCm <= rw && p.depthCm <= rl) ||
            (p.depthCm <= rw && p.widthCm <= rl);
      });
    case 'within_total_budget':
      if (!project.budget.hasBudget) return true;
      return recs.individualItems
          .every((it) => it.price <= project.budget.maxTotal);
    case 'covers_category':
      final cat = RecommendationCategory.fromWire(c['category']);
      return recs.individualItems.any((it) => it.category == cat);
    case 'excludes_product':
      final pid = '${c['product_id']}';
      return !items.any((it) => it.productId == pid);
    case 'bundle_within_budget_pct':
      if (!project.budget.hasBudget) return true;
      final pct = (c['max_pct'] as num?)?.toDouble() ?? 0;
      final cap = project.budget.maxTotal * (1 + pct / 100);
      return recs.bundles.every((b) => b.exceedsBudget || b.totalPrice <= cap);
    default:
      return true; // unknown type = ignored; add support in this switch
  }
}

double? _caseScore(_Eval ev, _Review? review) {
  if (!ev.hardPass) return 0; // hard gate failed → score 0
  if (review == null) return null; // pending expert review
  final criteriaMet = (ev.machineMet + review.humanMet) / 2;
  return 0.6 * criteriaMet + 0.4 * (review.stars / 5);
}

class _Review {
  _Review(this.stars, this.humanMet);
  final double stars;
  final double humanMet;
}

List<CatalogProduct> _loadCatalog(String p) =>
    (jsonDecode(File(p).readAsStringSync()) as List)
        .map((e) => CatalogProduct.fromJson(_asMap(e)))
        .toList();

List<Map<String, dynamic>> _loadDir(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  final out = <Map<String, dynamic>>[];
  for (final f in d.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.json') || name.startsWith('_')) continue; // skip _TEMPLATE
    out.add(_asMap(jsonDecode(f.readAsStringSync())));
  }
  return out;
}

Map<String, _Review> _loadReviews(String dir) {
  final out = <String, _Review>{};
  for (final r in _loadDir(dir)) {
    final stars = (r['stars'] as num?)?.toDouble();
    if (stars == null) continue;
    final hc = _asList(r['human_criteria_met']);
    final met = hc.isEmpty
        ? 1.0
        : hc.where((e) => _asMap(e)['met'] == true).length / hc.length;
    out['${r['scenario_id']}'] = _Review(stars, met);
  }
  return out;
}

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Object?> _asList(Object? v) => v is List ? v : const [];
