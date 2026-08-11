# G1 — قائمة فجوات موجَّهة للمعماري (Directed hand-off)

> من: المسار ٥ (النموّ/التحليلات/الثقة) · إلى: المعماري (بوابة المراجعة والتوزيع، الميثاق §٣ A5).
> السياق: G1 مقبول. أصلحتُ فجوات ملفاتي في PR من فرعي `claude/growth-analytics-trust-98bw20`.
> الفجوات أدناه تقع **خارج ملفاتي** (تركيب DI أو نقاط نداء تملكها مسارات أخرى) — لا ألمسها، وأرفعها موجَّهة بالمالك + الملف + السطر + التعديل المقترح.
> المرجع الكامل: `docs/analytics_audit.md`.

---

## أُصلِح في PR المسار ٥ (للعلم — لا إجراء عليك سوى المراجعة)
- **GAP-2** (PII): `need_unmet` أُعيد تشكيله — `raw_type` (نصّ خام) → `requested_category` (مفردات مغلقة/`other`). `lib/analytics/analytics.dart` + اختباره + الكتالوج.
- **GAP-6**: حارس اختباريّ للـ params (أوّليّة + منع أسماء حقول PII) — `test/analytics/analytics_pii_guard_test.dart`.
- **GAP-8**: تصحيح «Wire points» والعدّاد القديم (١٣→١٦) في الكتالوج و`http_analytics.dart`.

---

## موجَّه إليك (١): GAP-4 — `DebugAnalytics` يتجاوز الموافقة في التركيب

| الحقل | القيمة |
|---|---|
| **المالك** | المعماري (`lib/core/` عدا router — الميثاق §٢) |
| **الملف** | `lib/core/di/providers.dart` |
| **السطر** | 54 |
| **الحالي** | `if (kDebugMode) DebugAnalytics(log: true),` |
| **المشكلة** | لا تُمرَّر الموافقة، فيبقى الافتراض `consent = true`؛ في `kDebugMode` يجمع/يطبع بلا إذن (الـHTTP سليم، `providers.dart:63`). |
| **التعديل المقترح** | `if (kDebugMode) DebugAnalytics(log: true, consent: ref.watch(analyticsConsentProvider)),` |
| **قرار مؤسّس مرتبط** | القرار #2: إخضاع جمع Debug المحلّي للموافقة (توصيتنا) أم استثناؤه صراحةً. **إن أُقرّ الإخضاع** طُبِّق التعديل أعلاه. |
| **أثر** | يجعل Debug يحترم الموافقة كالـHTTP. تنبيه لـ G2: قبل منح الموافقة تكون لوحات القِمع المحلّية فارغة (سلوك صحيح خصوصيًّا) — يمكن توفير override تطويريّ صريح إن لزم. |

> **لا نغيّر افتراض `DebugAnalytics(consent = true)` نفسه** في `lib/analytics/`: الاختبارات والاستخدام المحلّي تعتمد عليه (`DebugAnalytics(log: false)` في `analytics_funnel_test`)؛ تغييره يكسر `analytics_funnel_test`. الإصلاح الصحيح تركيبيّ فقط.

---

## موجَّه إليك (٢): GAP-5 — لا فرض HTTPS على الوجهة

| الحقل | القيمة |
|---|---|
| **المالك** | المعماري |
| **الملف** | `lib/core/di/providers.dart` |
| **السطر** | 57–58 |
| **الحالي** | `final uri = Uri.tryParse(kAnalyticsEndpoint);`<br>`if (kAnalyticsEndpoint.isNotEmpty && uri != null && uri.hasScheme) {` |
| **المشكلة** | `hasScheme` يقبل `http://` — فتُرسَل الأحداث بنصّ صريح (خطر أمن/PDPL). |
| **التعديل المقترح** | ```final uri = Uri.tryParse(kAnalyticsEndpoint);```<br>```final schemeOk = uri != null && (uri.isScheme('https') || (kDebugMode && uri.host == 'localhost'));```<br>```if (kAnalyticsEndpoint.isNotEmpty && schemeOk) {``` |
| **أثر** | يمنع القياس بنصّ صريح في الإنتاج؛ يسمح بـ`http://localhost` للتطوير/الاختبار فقط. |

---

## موجَّه إليك (٣): GAP-1 — توصيل `need_unmet` (نقطة نداء لمسار ميزة)

| الحقل | القيمة |
|---|---|
| **المالك** | مسار الميزة التي تُظهر الطلب غير الملبّى (٣ الفهم / ٤ التجربة) — **تحدّده أنت** |
| **الحدث** | جاهز وآمن خصوصيًّا الآن: `NeedUnmet({requestedCategory, reason, reserveSar})` في `lib/analytics/analytics.dart` |
| **لماذا الآن** | كان مُعرَّفًا بلا نقطة نداء (إشارة الطلب = صفر). أُزيل حاجزه (raw_type) في PR المسار ٥. |
| **مسار تكامل ملموس (بنية قائمة)** | المحرّك يُنتج `UnmetNeed{rawType, reason}` (`lib/domain_engine/plan/unmet_need.dart`)، ويوجد مُطبِّع نقيّ `mapTypeToCategory(String) → RecommendationCategory` (`lib/domain_engine/recommendation/category_mapper.dart`, غير المعروف ⇒ `.other`). عند سطح ظهور الطلب غير الملبّى (مثلًا `plan_screen`/`plan_controller` حول `unmetNeeds`، أو مسار المساعد `UnknownCommand`) يُطلَق: |

```dart
// عند طبقة الميزة (لا داخل domain_engine — حارس النقاء):
analytics.track(NeedUnmet(
  requestedCategory: mapTypeToCategory(u.rawType).wire, // مفردات مغلقة/other — بلا نصّ خام
  reason: switch (u.reason) {                            // UnmetReason → عقد الحدث
    UnmetReason.outOfScope => 'out_of_scope',
    UnmetReason.notStocked => 'not_stocked',
    UnmetReason.noneFit    => 'none_fit',
  },
  reserveSar: /* اختياري */,
));
```

> **قيد النقاء:** التطبيع (`mapTypeToCategory`) نقيّ ويجوز استدعاؤه من طبقة الميزة قبل الإطلاق؛ **لا يوضَع نداء القياس داخل `lib/domain_engine/`** (`engine_purity_test`). راجِع أسماء `UnmetReason` الفعلية عند التوصيل.

---

## للعلم — بانتظار قرار المؤسّس (لا إجراء معماريّ الآن)
- **GAP-3** (مبالغ خام `newMax`/`total`/`reserve_sar`): ليست PII؛ توصيتنا الإبقاء. قرار #4.
- **GAP-7** (`telemetry_analytics.md` مُتجاوَز): تقاعد أم إعادة توظيف نظرةً معمارية. قرار #3.
