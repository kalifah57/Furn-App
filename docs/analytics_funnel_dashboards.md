# G2 — لوحات القِمع (Funnel dashboards)

> **مواصفة + لوحة محلّية تعمل** — مبنيّة على الكتالوج الحقيقيّ (`docs/analytics_events.md`) والكود (`lib/analytics/`).
> **الآن:** تعمل محليًّا على `DebugAnalytics` عبر `FunnelReport` (كود نقيّ + اختبار). **حيًّا:** نفس المنطق كـ SQL عند فتح `ANALYTICS_ENDPOINT` (قرار المؤسّس 🔒F4) — **دون لمس نقاط النداء**.
> **الملكية:** المسار ٥. تلاحظ ولا تغيّر · بلا PII · على الجلسات الموافِقة فقط.

---

## 0. الغرض والمصدر

جعل قِمع الثقة **مرئيًّا** الآن دون بنية تحتية: نقرأ الأحداث التي يسجّلها `DebugAnalytics` (قائمة `events` في الذاكرة) ونحسب منها التفعيل والثقة والعودة ونيّة الإيراد. حين تُفتح نقطة النهاية (F4) تُرسَل الأحداث نفسها إلى المستودع، فتُحسب اللوحات بـ SQL بالمنطق ذاته.

المقاييس الخمسة (النجم الشمالي = **التفعيل**):

| المقياس | التعريف | الأحداث (أسماء حقيقية) |
|---|---|---|
| **التفعيل (Activation)** ⭐ | `plan_finalized / flow_started` | `plan_finalized`, `flow_started` |
| **قِمع الثقة** | `flow_started → plan_seeded → engaged → plan_finalized` | `plan_seeded`؛ **engaged** = ≥1 من `item_pinned`/`item_rejected`/`item_swapped`/`budget_changed` |
| **العودة (Return)** | `plan_restored / (plan_seeded + plan_restored)` | `plan_restored` — **ليست بذرة** |
| **التسرّب** | جلسات `session_abandoned` | `session_abandoned` |
| **نيّة الإيراد** | `merchant_click / flow_started` (مدخل قِمع الإيراد، تفصيله G3) | `merchant_click` |

---

## 1. اللوحة المحلّية الآن — `FunnelReport` على `DebugAnalytics`

`lib/analytics/funnel_report.dart` — كود نقيّ بلا شبكة وبلا PII. العدّ **على مستوى الجلسة** (حضور مرحلة، لا أحداثًا خام).

```dart
// جلسة محلّية واحدة (DebugAnalytics.events):
final debug = ref.read(analyticsProvider); // في التطوير: DebugAnalytics ضمن FanOut
// ... بعد رحلة المستخدم ...
final report = FunnelReport.fromSession((debug as DebugAnalytics).events);
debugPrint(report.format());

// عبر عدّة جلسات مُجمَّعة (كل جلسة = قائمة أحداثها):
final agg = FunnelReport.fromSessions([sessionA.events, sessionB.events, ...]);
```

مخرج `format()` (لوحة console):

```
sessions=4
activation (finalized/started) = 33.3%  (1/3)
trust funnel: started=3 → seeded=3 → engaged=2 → finalized=1
  step rates: seed=100.0%  engage=66.7%  finalize=50.0%  overall=33.3%
return (restored/(seeded+restored)) = 25.0%  (restored=1)
abandoned=1   merchant intent=33.3%  (1/3)
```

يغطّيه `test/analytics/funnel_report_test.dart` (تفعيل/عودة/تحوّلات/حالة فارغة بلا قسمة على صفر).

**قيدان على القراءة المحلّية:**
- **الموافقة:** `DebugAnalytics` يسجّل حاليًّا بصرف النظر عن الموافقة في وضع التطوير (فجوة **GAP-4**، مرفوعة للمعماري). قبل ربطها بالموافقة، اللوحة المحلّية تعكس جلسات التطوير لا سلوك مستخدم موافِق. حين يُطبَّق GAP-4 تُصبح اللوحة المحلّية فارغة حتى منح موافقة صريحة (سلوك صحيح خصوصيًّا).
- **جلسة واحدة لكل `DebugAnalytics`:** القِمع عبر الجلسات يتطلّب تجميع قوائم أحداث عدّة جلسات عبر `fromSessions`.

---

## 2. الاستعلامات الحيّة (SQL — عند فتح F4)

حمولة `HttpAnalytics` لكل حدث: `{ name, session_id, at, params }`. المخطّط:
`events(name TEXT, session_id TEXT /* مجهول */, at TIMESTAMP, params JSONB)`.
(نكهة PostgreSQL؛ النافذة مثال، تُضبط لاحقًا.)

**التفعيل — النجم الشمالي:**
```sql
SELECT round(
  COUNT(DISTINCT session_id) FILTER (WHERE name='plan_finalized')::numeric
  / NULLIF(COUNT(DISTINCT session_id) FILTER (WHERE name='flow_started'), 0), 3) AS activation
FROM events WHERE at >= NOW() - INTERVAL '30 days';
```

**قِمع الثقة (٤ مراحل) — عدّ جلسات مميّزة وتحوّل كل خطوة:**
```sql
WITH f AS (
  SELECT
    COUNT(DISTINCT session_id) FILTER (WHERE name='flow_started')  AS started,
    -- plan_seeded فقط — plan_restored حدث مختلف ومُستبعَد عمدًا
    COUNT(DISTINCT session_id) FILTER (WHERE name='plan_seeded')   AS seeded,
    COUNT(DISTINCT session_id) FILTER (WHERE name IN
      ('item_pinned','item_rejected','item_swapped','budget_changed')) AS engaged,
    COUNT(DISTINCT session_id) FILTER (WHERE name='plan_finalized') AS finalized
  FROM events WHERE at >= NOW() - INTERVAL '30 days'
)
SELECT started, seeded, engaged, finalized,
  round(seeded::numeric   / NULLIF(started,0), 3) AS seed_rate,
  round(engaged::numeric  / NULLIF(seeded,0),  3) AS engage_rate,
  round(finalized::numeric/ NULLIF(engaged,0), 3) AS finalize_rate,
  round(finalized::numeric/ NULLIF(started,0), 3) AS overall
FROM f;
```

**العودة — `plan_restored` ليست بذرة:**
```sql
WITH s AS (
  SELECT
    COUNT(DISTINCT session_id) FILTER (WHERE name='plan_restored') AS restored,
    COUNT(DISTINCT session_id) FILTER (WHERE name='plan_seeded')   AS seeded
  FROM events WHERE at >= NOW() - INTERVAL '30 days'
)
SELECT restored, seeded,
  round(restored::numeric / NULLIF(seeded + restored, 0), 3) AS return_rate
FROM s;
```

**نيّة الإيراد (مدخل قِمع G3):**
```sql
SELECT round(
  COUNT(DISTINCT session_id) FILTER (WHERE name='merchant_click')::numeric
  / NULLIF(COUNT(DISTINCT session_id) FILTER (WHERE name='flow_started'), 0), 3) AS merchant_intent_rate
FROM events WHERE at >= NOW() - INTERVAL '30 days';
```

> الاستعلامات تطابق حساب `FunnelReport` سطرًا بسطر: نفس المراحل، نفس المقامات، نفس استبعاد `plan_restored` من البذور.

---

## 3. التحوّل من محلّي إلى حيّ (بلا لمس نقاط النداء)

القرار كله في `analyticsProvider` (`lib/core/di/providers.dart`): عند ضبط `--dart-define=ANALYTICS_ENDPOINT` يُضاف `HttpAnalytics` إلى نفس المصارف. **نقاط النداء لا تتغيّر** — تُطلق `track(event)` كما هي. `FunnelReport` يبقى للفحص المحلّي؛ اللوحات الحيّة تصير استعلامات على المستودع. لا تغيير في العقد ولا في الأحداث ⇒ **`analytics_funnel_test` لا يُكسر**.

---

## 4. حواجز الأمان (ما يجعل الرقم مُضلِّلًا)

- **النِّسَب المتسلسلة «حضور مرحلة» لا تسلسل زمنيّ:** قد تنخرط جلسة مُستعادة دون بذرة، فتظهر `engage_rate` مرتفعة؛ **التفعيل والإتمام الكلّي** أمتن رقمين. (موثَّق في `analytics_metrics_spec.md`.)
- **`flow_started` ودلالته:** توجيه **X0** (هبوط الفتح على شاشة المساعد) قد يغيّر «متى يبدأ التدفّق». لا يُغيَّر تعريف `flow_started` قبل توصية موجَّهة للمعماري — انظر ورقة X0. حتى ذلك الحين المقام (`flow_started`) ثابت.
- **قيد الموافقة:** الأرقام على الجلسات الموافِقة فقط؛ لا تُقدَّم كنسبة على «كل المستخدمين». الجلسات غير الموافِقة غير مرئية (تحيّز تخفيض معلوم).
- **معرّف الجلسة مجهول وقابل للتدوير:** العودة تُقاس كاسترجاع خطة لا كاحتفاظ بشخص عبر الزمن.
