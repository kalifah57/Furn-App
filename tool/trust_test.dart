// S0 · Trust-Test harness (see docs/cto_roadmap.md).
//
// Runs the REAL deterministic recommendation engine over a set of realistic
// Saudi furnishing scenarios and writes a human-review packet. It uses ONLY
// the pure-Dart core (domain_engine + models) — no Flutter, device, backend,
// or AI. This is the cheapest possible evidence that the engine — the actual
// product — produces recommendations a person would trust.
//
// Run from the repo root:
//   flutter pub get                 # one-time: resolves equatable + uuid
//   dart run tool/trust_test.dart
//
// Output: prints the report to stdout and writes tool/trust_test_report.md
// (the file to put in front of target users + a furniture/interior expert).
//
// The Dart VM compiles only the pure-Dart subtree this script imports, so it
// runs headless even though the wider project is a Flutter app.

import 'dart:convert';
import 'dart:io';

import 'package:furn_app/domain_engine/recommendation/recommendation_engine.dart';
import 'package:furn_app/shared/models/models.dart';

const _catalogPath = 'assets/catalog/catalog.json';
const _scenariosPath = 'tool/trust_test_scenarios.json';
const _reportPath = 'tool/trust_test_report.md';

void main() {
  final catalog = _loadCatalog(_catalogPath);
  final scenarios = _loadScenarios(_scenariosPath);
  const engine = RecommendationEngine();

  final out = StringBuffer();
  _writeHeader(out, catalog.length, scenarios.length);

  for (final s in scenarios) {
    final project = FurnishingProject.fromJson(_asMap(s['project']));
    final recs = engine.generate(project, catalog);
    _writeScenario(out, s, project, recs);
  }

  final report = out.toString();
  stdout.write(report);
  File(_reportPath).writeAsStringSync(report);
  stderr.writeln('\n[ok] wrote $_reportPath '
      '(${scenarios.length} scenarios over ${catalog.length} products)');
}

// ---------------------------------------------------------------- loading

List<CatalogProduct> _loadCatalog(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as List;
  return raw.map((e) => CatalogProduct.fromJson(_asMap(e))).toList();
}

List<Map<String, dynamic>> _loadScenarios(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as List;
  return raw.map(_asMap).toList();
}

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

// ---------------------------------------------------------------- rendering

void _writeHeader(StringBuffer out, int products, int scenarios) {
  out
    ..writeln('# تقرير اختبار الثقة — جودة قرارات المحرّك')
    ..writeln()
    ..writeln('> مُولّد آليًا من `tool/trust_test.dart` عبر المحرّك الحتمي '
        'الحقيقي على $products منتجًا و$scenarios سيناريو. '
        'بدون Flutter أو خادم أو ذكاء اصطناعي — منطق حتمي بحت.')
    ..writeln()
    ..writeln('**طريقة المراجعة:** لكل سيناريو، قارن التوصيات بالتوقّع البشري، '
        'ثم أعطِ درجة ثقة من ١ (سيئة/غير منطقية) إلى ٥ (كما أتوقّع أو أفضل). '
        'بوّابة النجاح V1: غالبية واضحة عند ٤ أو ٥.')
    ..writeln();
}

void _writeScenario(
  StringBuffer out,
  Map<String, dynamic> meta,
  FurnishingProject p,
  Recommendations recs,
) {
  out
    ..writeln('---')
    ..writeln()
    ..writeln('## ${meta['id']} · ${meta['title']}');

  final persona = '${meta['persona'] ?? ''}';
  if (persona.isNotEmpty) out.writeln('- **الشخصية:** $persona');

  final r = p.room;
  final dims = (r.widthM > 0 && r.lengthM > 0)
      ? '${_n(r.widthM)}×${_n(r.lengthM)} م (${_n(r.areaM2)} م²)'
      : 'أبعاد غير محددة';
  out.writeln('- **الغرفة:** ${r.roomType.arabicLabel} · $dims');

  final budget = p.budget.hasBudget
      ? '${_money(p.budget.maxTotal)} ريال${p.budget.flexible ? ' (مرنة)' : ''}'
      : 'غير محددة';
  out.writeln('- **الميزانية:** $budget');

  final style = <String>[
    if (p.style.preferred.isNotEmpty) 'نمط: ${p.style.preferred.join('، ')}',
    if (p.style.colors.isNotEmpty) 'ألوان: ${p.style.colors.join('، ')}',
  ].join(' · ');
  out.writeln('- **النمط:** ${style.isEmpty ? 'غير محدّد' : style}');

  final essential = p.items.essential.map((e) => e.type).join('، ');
  final optional = p.items.optional.map((e) => e.type).join('، ');
  final requested = <String>[
    if (essential.isNotEmpty) 'أساسي: $essential',
    if (optional.isNotEmpty) 'اختياري: $optional',
  ].join(' · ');
  out.writeln('- **المطلوب:** ${requested.isEmpty ? '—' : requested}');

  final expectation = '${meta['expectation'] ?? ''}';
  if (expectation.isNotEmpty) {
    out.writeln('- **التوقّع البشري:** $expectation');
  }
  out.writeln();

  // ---- individual recommendations
  out.writeln('**التوصيات الفردية (${recs.individualItems.length}):**');
  if (recs.individualItems.isEmpty) {
    out.writeln('- (لا شيء)');
  } else {
    var i = 1;
    for (final it in recs.individualItems) {
      out
        ..writeln('${i++}. **${it.name}** — ${it.category.arabicLabel} — '
            '${_money(it.price)} ريال — درجة ${_n(it.score)} — '
            '${it.priority.arabicLabel}')
        ..writeln('   - السبب: ${it.reason}');
    }
  }
  out.writeln();

  // ---- bundles
  out.writeln('**الباقات (${recs.bundles.length}):**');
  if (recs.bundles.isEmpty) {
    out.writeln('- (لا شيء)');
  } else {
    for (final b in recs.bundles) {
      final flag = b.exceedsBudget ? ' ⚠️ تتجاوز الميزانية' : '';
      out.writeln('- **${b.tier.arabicLabel}** — الإجمالي '
          '${_money(b.totalPrice)} ريال$flag');
      out.writeln('  - العناصر: ${b.items.map((e) => e.name).join('، ')}');
      if (b.designNotes.isNotEmpty) {
        out.writeln('  - ملاحظات: ${b.designNotes.join('؛ ')}');
      }
      if (b.tradeoffs.isNotEmpty) {
        out.writeln('  - تنازلات: ${b.tradeoffs.join('؛ ')}');
      }
    }
  }
  out.writeln();

  // ---- app-level fallback (mirrors RecommendationRepositoryImpl)
  if (recs.individualItems.isEmpty && recs.bundles.isEmpty) {
    out
      ..writeln('> سلوك التطبيق عند غياب المطابقات: يعرض إرشادات عامة أو يطلب '
          'صورًا/تعديل الميزانية.')
      ..writeln();
  }

  out
    ..writeln('**تقييم الثقة (يملؤه المُراجِع):** '
        '☐ ١ ☐ ٢ ☐ ٣ ☐ ٤ ☐ ٥ — ملاحظات: ________________')
    ..writeln();
}

// ---------------------------------------------------------------- format

String _money(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
