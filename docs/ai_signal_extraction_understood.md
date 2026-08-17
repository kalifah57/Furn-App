# spec — إشارة «فُهِم الاستخراج» (`extraction_understood`)

> **الحالة:** مقترَح من مسار ٣ (الفهم). **لا يُنفَّذ من مسار ٣.**
> يعالج `R-3` و`G-12`/`G-6` من `docs/ai_review_report.md`.
> **حدّ الملكية:** نقطة النداء في `lib/features/room_input/presentation/flow_controller.dart`
> يملكها مسار ٤/المعمارية؛ هذا الملفّ **يصف** التغيير ولا يطبّقه (بأمر المعمارية:
> «ارفع spec دقيقًا — لا تلمس ملفّ مسار ٤»).

---

## ١) لماذا

بعد `X0` صار **الاستخراج الحرّ هو الواجهة الأمامية**، لكنّ `flow_controller` يُطلق
`input_submitted` (عدّادات فقط) و**لا يُطلق أيّ إشارة فهم**. المقابل الأمريّ موجود
منذ زمن: `assistant_command {intent, understood}` يغذّي
`AssistantUnderstoodReport` الذي يقول صراحةً إنه «يغذّي توسيع مُحلِّل مسار ٣».
فالسطح الأهمّ (الاستخراج) **أعمى في تقرير G5**، ونحن نرتّب توسيع الفهم بالحدس لا
بمعدّلٍ مقيس. هذه الإشارة تُغلق تلك الحلقة بنفس نمط سطح الأوامر تمامًا.

**مبدأ محفوظ:** «مفهوم/غير مفهوم» **قرارٌ حتميّ للمحرّك لا حكم AI**. الإشارة
تنقل ما قرّره `BusinessRulesEngine` (`missingInformation` فارغة؟) لا تخترع حكمًا جديدًا.

---

## ٢) الحدث (يعيش في `lib/analytics/analytics.dart` — طبقة القياس)

مطابق لنمط `AssistantCommand`/`NeedUnmet` (أنواع صريحة، قيَم بدائية، **بلا PII**):

```dart
/// المستخدم أدخل وصفًا حرًّا فحلّله الاستخراج + قواعد العمل. [understood] يفصل ما
/// فهمناه عمّا أعلنّاه ناقصًا — تجميع understood=false يكشف **أيّ لغةٍ يعجز عنها
/// المُستخرِج بعد**، فيوجّه توسيع الـcorpus بالطلب الحقيقي لا بالحدس. حدّ الخصوصية:
/// لا يحمل النصّ الخام (قد يحوي اسمًا/مكانًا) — يُلخَّص إلى عدّادات مُجمَّعة فقط.
class ExtractionUnderstood extends AnalyticsEvent {
  const ExtractionUnderstood({
    required this.understood,
    required this.missingCount,
    required this.warningCount,
    required this.confidence,   // 0..100 (نفس اصطلاح PlanSeeded/PlanFinalized)
    required this.inputMode,    // text | voice | image  (لا manual)
  });
  final bool understood;
  final int missingCount;
  final int warningCount;
  final int confidence;
  final String inputMode;

  @override
  String get name => 'extraction_understood';
  @override
  Map<String, Object?> get params => {
        'understood': understood,
        'missing_count': missingCount,
        'warning_count': warningCount,
        'confidence': confidence,
        'input_mode': inputMode,
      };
}
```

### دلالة الحقول (كلّها مشتقّة من المشروع بعد `BusinessRulesEngine.apply`)

| الحقل | المصدر الحتمي | لماذا يهمّ G5 |
|---|---|---|
| `understood` | `project.nextActions.followUpQuestions.isEmpty` | معدّل الفهم للواجهة الأمامية — نظير `AssistantCommand.understood` |
| `missing_count` | `project.analysis.missingInformation.length` | **أيّ** حقلٍ نعجز عن ملئه (يوجّه توسيع الاستخراج) |
| `warning_count` | `project.analysis.warnings.length` | حجم الخسارة المُعلَنة (خارج نطاق/خامة/مقاس) → يغذّي `need_unmet`/قرار التوريد |
| `confidence` | `(project.analysis.confidenceScore * 100).round()` | اتجاه جودة الفهم عبر الزمن |
| `input_mode` | `_lastInputMode` | يفصل text/voice/image (كلٌّ له معدّل فهم مختلف) |

> `understood` **مشتقّ من حكم المحرّك** (لا أسئلة متابعة = لا نقص حرِج)، فيبقى المبدأ:
> الـAI يفهم اللغة والمحرّك وحده يقرّر أنه «فُهم».

---

## ٣) نقطة النداء الدقيقة (يطبّقها مالك الملفّ)

**الملفّ:** `lib/features/room_input/presentation/flow_controller.dart`
**الدالّة:** `_afterAnalysis(FurnishingProject project)`
**الموضع:** مباشرةً بعد نداء `analytics.track(InputSubmitted(...))` القائم (السطر ~٨٧–٩٣)
وقبل تفرّع `if (project.nextActions.hasFollowUps)` (السطر ~٩٤).

```dart
  Future<void> _afterAnalysis(FurnishingProject project) async {
    ref.read(analyticsProvider).track(InputSubmitted( /* … قائم … */ ));

    // ── إضافة R-3: إشارة فهم الاستخراج (تُقاس المدخلات الحرّة فقط، لا اليدوية) ──
    if (_lastInputMode != 'manual') {
      ref.read(analyticsProvider).track(ExtractionUnderstood(
            understood: project.nextActions.followUpQuestions.isEmpty,
            missingCount: project.analysis.missingInformation.length,
            warningCount: project.analysis.warnings.length,
            confidence: (project.analysis.confidenceScore * 100).round(),
            inputMode: _lastInputMode,
          ));
    }

    if (project.nextActions.hasFollowUps) { /* … قائم … */ }
    // …
  }
```

**حرّاسة الموضع:**
- `_lastInputMode != 'manual'`: الإدخال اليدوي يتخطّى الاستخراج (`submitManualDraft`
  يمرّ بـ`_afterAnalysis` أيضًا)، فلا يُقاس فهمُ استخراجٍ لم يحدث.
- **بعد** `apply`: عند هذه النقطة المشروع يحمل نتيجة الاستخراج **وقواعد العمل**، فحقول
  `missingInformation`/`warnings`/`confidenceScore` نهائية.
- الحدث يحترم الموافقة تلقائيًّا (كل الأحداث تُسقَط في `NoopAnalytics`/بلا موافقة).

**لا PII:** لا نصّ خام يُرسَل — عدّادات وقيَم بدائية مُجمَّعة فقط (نفس علاج G1 في `NeedUnmet`).

---

## ٤) المستهلِك في G5 (يملكه مسار ٥ — تقرير مطابق للقائم)

نظير `AssistantUnderstoodReport.fromEvents` لكن على `ExtractionUnderstood`:

```dart
class ExtractionUnderstoodReport {
  final int total, understood;
  final int withWarnings;              // كم مدخلًا حمل خسارة مُعلَنة
  final Map<String, int> byInputMode;  // text/voice/image → عدد
  double get understoodRate => total == 0 ? 0 : understood / total;
  // fromEvents(events): events.whereType<ExtractionUnderstood>() … (بترتيب فرزٍ مستقرّ)
}
```

يعطي **المعدّل والاتجاه** لا الأمثلة الفاشلة؛ جمع أمثلة الفشل يبقى في corpus مسار ٣
الخاصّ (`understanding_corpus.json`)، لا في قياس الإنتاج — نفس حدّ خصوصية التقرير الأمريّ.

---

## ٥) `G-6` — المهمّة الثلاثية (تقسيم الملكية)

اكتشاف المحور ٦ (`G-12`) يُنفَّذ كمهمّة واحدة بثلاثة ملّاك:

| # | المالك | المُخرَج |
|---|---|---|
| ١ | **مسار ٣ (الفهم)** | *هذا الـspec*: دلالة الإشارة + اشتقاق الحقول من حكم المحرّك (مُسلَّم) |
| ٢ | **مسار ٥ (النموّ/القياس)** | تعريف `ExtractionUnderstood` في `analytics.dart` + `ExtractionUnderstoodReport` + اختبار fromEvents |
| ٣ | **مسار الواجهات/التدفّق** | إدراج نقطة النداء في `_afterAnalysis` (§٣) وتمريرها عبر `analyticsProvider` |

**تبعية:** ٢ ثم ٣ (لا يمكن النداء قبل وجود النوع). مسار ٣ لا يطبّق ٢ ولا ٣.

---

## ٦) قبول

- [ ] `extraction_understood` يُطلَق مرّة لكل مدخلٍ حرّ (text/voice/image)، صفرًا لليدوي.
- [ ] `understood == (followUpQuestions.isEmpty)` — لا حكم AI مستقلّ.
- [ ] لا نصّ خام في `params` (اختبار حارس PII كما في `NeedUnmet`).
- [ ] جملة المؤسّس E-16 تُطلق `understood=true, missing_count=0, warning_count≥1`.
- [ ] «أبي أأثث بيتي» تُطلق `understood=false, missing_count≥2`.
