import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furn_app/shared/utils/formatters.dart';

import '../support/arabic_app.dart';

/// X9 بند ٢: "1,800 ريال" كانت تُعرض "800,1 ريال" داخل RTL. الرقم يجب أن
/// يخرج معزولًا اتجاهيًّا من المصدر الواحد formatSar، فيبقى ترتيبه سليمًا.
/// نكتب محرِفَي العزل كتهريبٍ ASCII لا كحرفٍ خام (الخام يُفشِل analyze).
const _lri = '\u2066'; // LEFT-TO-RIGHT ISOLATE
const _pdi = '\u2069'; // POP DIRECTIONAL ISOLATE

void main() {
  test('formatSar يعزل الرقم اتجاهيًّا حول فواصل الآلاف', () {
    final out = formatSar(1800);
    // الرقم كاملًا داخل عازلٍ واحد، ثمّ العملة.
    expect(out, '$_lri' '1,800' '$_pdi ريال');
    expect(out.indexOf(_lri) < out.indexOf('1,800'), isTrue);
    expect(out.indexOf('1,800') < out.indexOf(_pdi), isTrue);
  });

  test('كل مبلغ ذي فاصل آلاف يخرج معزولًا', () {
    for (final n in [500.0, 3000.0, 12345.0]) {
      final out = formatSar(n);
      expect(out.startsWith(_lri), isTrue, reason: '\$n بلا عازل بادئ');
      expect(out.contains(_pdi), isTrue, reason: '\$n بلا عازل ختامي');
      expect(out.endsWith(' ريال'), isTrue);
    }
  });

  test('formatPercent يعزل النسبة كذلك', () {
    expect(formatPercent(0.42), '$_lri' '42%' '$_pdi');
  });

  testWidgets('يُصيَّر داخل سياق RTL بلا استثناء', (tester) async {
    await tester.pumpWidget(arabicApp(
      Scaffold(body: Center(child: Text(formatSar(1800)))),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1,800'), findsOneWidget);
    expect(Directionality.of(tester.element(find.textContaining('1,800'))),
        TextDirection.rtl);
  });
}
