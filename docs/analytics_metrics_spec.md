# مواصفة المقاييس — Furn-App (Metrics Spec)

> **مقترح — بانتظار الموافقة (Proposal — pending approval)**
> هذه وثيقة تصميم للمقاييس (Metrics Spec) في طور التدقيق/التصميم. الغرض منها التحديد والاقتراح فقط، لا التنفيذ. تُبنى **حصريًا** على العقد المعتمد في `docs/analytics_audit.md`، ولا تُنشئ أسماء أحداث أو `params` جديدة. أي مقياس لا يسنده حدث قائم يُدرَج تحت «فجوات القياس» ولا يُخترع له حدث.
>
> **مبادئ حاكمة:** «الخطة هي المنتج» · «الثقة هي النتيجة» · «التسوّق اختياري».
> **قاعدتا القياس:** «تلاحظ ولا تغيّر» — نُلاحِظ من الخارج ولا نغيّر سلوك المنتج ولا حلقة الثقة. و«الأرقام تُرشد لا تقرّر».
> **الملكية (Track 5):** `lib/analytics/**` + منطق الموافقة `lib/features/consent/**` (عدا البانر = Track 4) + وثائق `docs/analytics_events.md` و`docs/telemetry_analytics.md`.
> **الحاكم عند التنازع:** `docs/agent_workstreams.md` والبريف الكامل `docs/workstreams/5_growth_analytics.md`.
> **مصدر الحقيقة للأحداث:** كتالوج §3 في `docs/analytics_audit.md` (16 حدثًا). أسماء الأحداث و`params` أدناه منقولة منه حرفيًّا.

---

## 1. ملخّص — فلسفة القياس

هذه الوثيقة تُحوِّل عقد التحليلات المعتمد إلى **نموذج مقاييس** قابل للحساب: عائلات مقاييس، تعريفات دقيقة، أحداث مصدرية، أبعاد، حواجز أمان، واستعلامات توضيحية. المبادئ الثلاثة التي تحكم كل رقم هنا:

1. **الأرقام تُرشد لا تقرّر.** المقاييس أداة إرشاد للفريق، لا بديل عن قرار المحرك ولا عن حكم المنتج. لا يُشتق من أي رقم في هذه الوثيقة تغييرٌ تلقائي لسلوك المستخدم أو لحلقة الثقة. المحرك يقرّر؛ التحليلات تُلاحِظ.
2. **نُلاحِظ ولا نغيّر.** كل مقياس مبنيّ على حدث يُصدَر من **خارج** المحرك النقي (feature-layer)، ولا يُغذّي أي رقمٍ عائدًا إلى قرار المحرك. القياس أحادي الاتجاه: من الحالة إلى الرصد، لا العكس.
3. **مجهول فقط، بلا PII.** كل مقياس يُحسب على `session_id` **مجهول** فقط، ومن `params` أولية مُعدَّلة (enum) أو مُجمّعة في سِلال (buckets). لا اسم، لا بريد، لا هوية مستخدم، لا نص خام، لا مبلغ خام، لا محتوى غرفة. هذا القيد يشكّل حدود ما يمكن قياسه — وهو حدٌّ مقصود، لا نقص.

**قيد التغطية (consent):** الموافقة مُعطَّلة افتراضيًا (`null` و`false` = لا جمع). لذلك كل الأرقام أدناه تُحسب على **الجلسات الموافِقة فقط**؛ الجلسات غير الموافِقة غير مرئية للقياس. النِّسَب (ratios) أمتن من الأعداد المطلقة تحت هذا القيد لأن البسط والمقام يخضعان للتحيّز نفسه، لكن يجب عدم تقديم أي عدد مطلق على أنه «إجمالي المستخدمين».

---

## 2. النجم الشمالي والعائلات

خمس عائلات مقاييس تغطّي دورة حياة القيمة في المنصّة:

| العائلة | تعريف بسطر واحد | الحدث/الأحداث المحورية |
|---|---|---|
| **التفعيل (Activation)** ⭐ | نسبة الجلسات التي أنتجت **خطة نهائية** إلى الجلسات التي بدأت مسارًا. | `plan_finalized / flow_started` |
| **قِمع الثقة (Trust funnel)** | تقدّم الجلسة عبر أربع مراحل قانونية حتى الإتمام، مع رصد التسرّب. | `flow_started → plan_seeded → engaged → plan_finalized` |
| **قِمع الإيراد (Revenue funnel)** | نسبة الجلسات التي بلغت **نيّة الشراء** (النقر إلى التاجر) بعد الاستكشاف. | `options_opened`/`ar_opened` → `merchant_click` |
| **العودة (Return/Retention)** | نسبة الجلسات التي **استرجعت** خطة محفوظة، كإشارة رجوع. | `plan_restored` |
| **الطلب (Demand)** | حجم وتوزيع **الحاجات غير الملبّاة** بحسب سببها. | `need_unmet` |

**النجم الشمالي = التفعيل (Activation).** السبب: «الخطة هي المنتج» — الخطة النهائية هي القيمة الفعلية المُسلَّمة للمستخدم، و«الثقة هي النتيجة» — بلوغ الإتمام هو تجسيد الثقة في القُمع. أمّا الإيراد فمصبٌّ لاحق واختياري («التسوّق اختياري»)، فلا يصلح نجمًا شماليًا لأنه لا يقيس القيمة الأساسية للمنتج بل مصبًّا فرعيًا منها. التفعيل هو المقياس الوحيد الذي يرتفع فقط حين يُسلَّم المنتج فعلًا، بصرف النظر عن حدوث التسوّق.

---

## 3. تفصيل العائلات الخمس

### 3.1 التفعيل (Activation) ⭐

- **التعريف:** حصّة الجلسات التي وصلت إلى خطة نهائية مثبَّتة من بين كل الجلسات التي بدأت مسار تخطيط، خلال نافذة زمنية.
- **البسط/المقام:**
  - البسط = عدد الجلسات المميّزة التي أطلقت `plan_finalized`.
  - المقام = عدد الجلسات المميّزة التي أطلقت `flow_started`.
  - `activation_rate = distinct sessions(plan_finalized) / distinct sessions(flow_started)`.
- **الأحداث المستخدمة:** `flow_started`، `plan_finalized`.
- **الأبعاد (مجهولة):**
  - `experience` ∈ `{assistant, my_room, preview}` (من `params.experience`).
  - `time` عبر `ts` (يومي/أسبوعي)، أو `duration_bucket` من `plan_finalized` لتقسيم سرعة الإتمام.
  - لا بُعد `category` هنا (غير ذي معنى على مستوى التفعيل الكلّي).
- **حواجز الأمان (ما الذي يجعل الرقم مُضلِّلًا):**
  - **تعدّد `flow_started` في الجلسة:** لو أطلقت الجلسة `flow_started` أكثر من مرة، فاستخدام `DISTINCT session_id` يمنع تضخّم المقام؛ لا تَعُدّ الأحداث الخام.
  - **مصدر البدء:** `source ∈ {home, deeplink, resume, share}`؛ جلسات `resume` قد تصل للإتمام دون «بداية حقيقية»، فافصلها عند الحاجة كي لا تُنسب الفضل خطأً.
  - **قيد الموافقة:** غياب الجلسات غير الموافِقة يجعل الرقم نِسبةً داخل العيّنة الموافِقة فقط؛ لا يُقدَّم كنسبة على «كل المستخدمين».
  - **تدوير المُعرّف المجهول:** إن دُوِّر `session_id` كثيرًا، يتضخّم المقام (جلسات أكثر لأشخاص أقل) ويُخفَّض معدّل التفعيل الظاهري. القرار في §6 من التدقيق.

### 3.2 قِمع الثقة (Trust funnel)

- **التعريف:** القُمع القانوني **أربع مراحل مرتّبة**: `flow_started → plan_seeded → engaged → plan_finalized`. يُقاس تحوّل كل خطوة (step conversion) والإتمام الكلّي (overall completion)، ويُرصد التسرّب عبر `session_abandoned`.
- **المراحل والخرائط إلى الأحداث:**

  | # | المرحلة | الحدث/الأحداث | ملاحظة |
  |---|---|---|---|
  | S1 | البدء (started) | `flow_started` | مقام القُمع. |
  | S2 | بذر الخطة (seeded) | `plan_seeded` | **`plan_seeded` فقط — لا `plan_restored`** (انظر الحاجز أدناه). |
  | S3 | الانخراط (engaged) | **مشتقّة**: ≥١ من `item_pinned` · `item_rejected` · `item_swapped` · `budget_changed` | التزام فعليّ بالخطة داخل حلقة الثقة. |
  | S4 | الإتمام (finalized) | `plan_finalized` | بسط التفعيل؛ حصيلة القُمع. |

- **إشارات مُلاصِقة (خارج المراحل الأربع القانونية):** `input_submitted` إشارة إدخال بين S1 وS2 تُرصد لكنها ليست مرحلة قُمع مستقلّة؛ `plan_shared` إشارة تضخيم/ثقة اجتماعية **بعد** S4 (اختيارية، لا تُعدّ إتمامًا). تُعرض بمعزل عن تحوّلات القُمع الأربعة كي لا تُشوّه التعريف القانوني.
- **البسط/المقام:**
  - **تحوّل الخطوة** `cvr(n→n+1) = distinct sessions at stage n+1 / distinct sessions at stage n` عبر المراحل الأربع.
  - **الإتمام الكلّي** `overall_completion = distinct sessions(plan_finalized) / distinct sessions(flow_started)` (يتطابق بسطًا/مقامًا مع التفعيل؛ التفعيل هو حصيلة هذا القُمع).
  - **التسرّب** يُقاس من `session_abandoned` موزّعًا على `last_stage ∈ {input, seeded, editing, preview, checkout_intent}`.
- **الأحداث المستخدمة:** `flow_started`, `plan_seeded`, `item_pinned`, `item_rejected`, `item_swapped`, `budget_changed`, `plan_finalized`, `session_abandoned` (وللإشارات المُلاصِقة: `input_submitted`, `plan_shared`).
- **الأبعاد (مجهولة):** `experience` (من `flow_started`/`plan_seeded`/`plan_finalized`)؛ `category` على مستوى S3 لأحداث العناصر؛ `time` عبر `ts`؛ `last_stage` كبُعد للتسرّب.
- **حواجز الأمان:**
  - **`plan_restored` ليست بذرة (حاجز حاسم):** يجب **عدم** عدّ `plan_restored` ضمن S2 (`plan_seeded`) ولا في بسط/مقام التفعيل. `plan_restored` عودة إلى خطة قائمة لا بذرًا جديدًا؛ خلطها بالبذر **يضخّم القُمع كذبًا**. تُحسب حصريًّا في عائلة العودة (§3.4).
  - **القُمع ليس صارم الترتيب:** الحساب بعدّ الجلسات المميّزة الحاضرة عند كل مرحلة **لا** يفرض ترتيبًا زمنيًا داخل الجلسة؛ قد تظهر خطوة دون سابقتها فيُنتِج ذلك تحوّلًا > 100%. عالِج بأخذ الجلسات التي مرّت بالمرحلة السابقة كمقام (funnel محكم) عند الحاجة، أو صرّح بأنه «حضور مرحلة» لا «تسلسل». (يؤكّد `analytics_funnel_test` التسلسل القانوني للأحداث.)
  - **S3 (engaged) مشتقّة ومتعدّدة الأحداث:** جلسة قد تُتِمّ دون انخراط ظاهر، فلا تُعامَل S3 كبوابة إجبارية صلبة، لكنها المرحلة القانونية الوسطى.
  - **قيد الموافقة والتدوير:** كما في 3.1؛ النِّسَب أمتن من الأعداد المطلقة.

### 3.3 قِمع الإيراد (Revenue funnel)

- **التعريف:** حصّة الجلسات التي بلغت **نيّة الشراء** — أي أطلقت `merchant_click` — من بين الجلسات التي دخلت مرحلة الاستكشاف (`options_opened` أو `ar_opened`). هذه أول إشارة نيّة شراء ومدخل قُمع الإيراد.
- **البسط/المقام:**
  - البسط = عدد الجلسات المميّزة التي أطلقت `merchant_click`.
  - المقام = عدد الجلسات المميّزة التي أطلقت `options_opened` أو `ar_opened`.
  - `merchant_ctr = distinct sessions(merchant_click) / distinct sessions(options_opened OR ar_opened)`.
- **الأحداث المستخدمة:** `options_opened`, `ar_opened`, `merchant_click`.
- **الأبعاد (مجهولة):** `category` (من `params.category` في `merchant_click`/`item_*`/`options_opened`)؛ `product_id` (غير شخصي، لتوزيع النقر على المنتجات)؛ `experience` (النقر من `preview`/`my_room`)؛ `time` عبر `ts`.
- **حواجز الأمان:**
  - **النقر ≠ شراء:** `merchant_click` نيّة فقط. التحوّل إلى شراء/عمولة يحدث **خارج** العميل (لدى التاجر/شبكة الأفلييت)، ولا يوجد حدث `purchase_*` في الكتالوج — يُنسَب هذا صراحةً إلى «خطة الإيراد» ويُدرَج في §6.
  - **حساسية المقام:** كثرة `options_opened`/`ar_opened` (استكشاف تلقائي أو واجهة تُظهر خيارات كثيرة) تُضخِّم المقام وتخفض CTR ظاهريًا دون تغيّر حقيقي في النيّة.
  - **«التسوّق اختياري»:** انخفاض CTR **ليس** فشلًا للمنتج؛ القيمة الأساسية هي الخطة لا النقر. لا يُتّخذ قرار منتج يقسر المستخدم على النقر بحجّة رفع هذا الرقم.
  - **تكرار النقر:** استخدم `DISTINCT session_id` للنِّسبة، واحتفظ بعدّ الأحداث الخام فقط لتحليل الكثافة لا للـ CTR.

### 3.4 العودة (Return / Retention)

- **التعريف:** حصّة الجلسات التي **استرجعت** خطة محفوظة (`plan_restored`) كإشارة رجوع، من بين الجلسات النشطة في النافذة.
- **البسط/المقام:**
  - البسط = عدد الجلسات المميّزة التي أطلقت `plan_restored`.
  - المقام = عدد الجلسات المميّزة النشطة في النافذة (أطلقت أي حدث)، أو بديلًا: الجلسات التي أطلقت `flow_started`.
  - `return_rate = distinct sessions(plan_restored) / distinct active sessions`.
- **الأحداث المستخدمة:** `plan_restored` (وبُعده `source ∈ {local, link}` و`age_bucket ∈ {h1,d1,d7,d30,older}`).
- **الأبعاد (مجهولة):** `source` (local مقابل link)؛ `age_bucket` (قِدَم الخطة المسترجَعة)؛ `experience`؛ `time` عبر `ts`.
- **حواجز الأمان:**
  - **تدوير المُعرّف المجهول يحدّ من قياس الاحتفاظ الحقيقي:** بما أن الهوية مجهولة وقد تُدوَّر (لكل جلسة/يوميًا/عند سحب الموافقة — قرار مفتوح §9 من التدقيق)، فإن «العودة» تُقاس كإشارة استرجاع خطة **لا** كاحتفاظ بشخص عبر الزمن. لا يُقدَّم `plan_restored` على أنه retention حقيقي لمستخدم فريد.
  - **`source=link`:** الاسترجاع عبر رابط مشاركة قد يكون مستخدمًا **جديدًا** لا عائدًا؛ افصله عن `source=local` عند تفسير العودة.
  - **قيد الموافقة:** الجلسات غير الموافِقة التي عادت غير مرئية، فالعودة الحقيقية أعلى من المرصود (تحيّز تخفيض).

### 3.5 الطلب (Demand)

- **التعريف:** حجم وتوزيع الحاجات التي تعذّر تلبيتها (`need_unmet`) مُجمّعة حسب `reason_code`، كإشارة طلب غير ملبّى تُرشد المنتج والمخزون والتكامل.
- **البسط/المقام:** مقياس **عدّي/توزيعي** لا نِسبيّ بالضرورة:
  - العدّ = عدد أحداث `need_unmet` لكل `reason_code`.
  - العرض المميّز = عدد الجلسات المتأثّرة (`distinct session_id`) لكل `reason_code`.
  - يمكن اشتقاق نِسبة `unmet_rate = distinct sessions(need_unmet) / distinct sessions(flow_started)` كإشارة كثافة.
- **الأحداث المستخدمة:** `need_unmet` مع `reason_code ∈ {no_match, out_of_budget, unsupported, out_of_stock}`.
- **الأبعاد (مجهولة):** `reason_code` (المحور الأساسي)؛ `experience` عبر مسار الإطلاق؛ `time` عبر `ts`.
- **حواجز الأمان:**
  - **رمز مُعدَّل لا نص حرّ:** `reason_code` مغلق؛ لا يُلتقط سبب حرّ. ما لا ينطبق على الرموز الأربعة يُفقد أو يقع في تفسير غامض — راقب هيمنة أي رمز بوصفها إشارة لحاجة توسيع الكتالوج (§6).
  - **الطلب الصامت غير مرصود:** المستخدم الذي يستسلم دون أن يُطلق المحرك `need_unmet` لا يظهر هنا؛ فالطلب المرصود حدٌّ أدنى للطلب الحقيقي.
  - **الاعتماد على إصدار المحرك للحدث:** الحدث يُصدَر من خارج المحرك عند تعذّر التلبية؛ إن لم تُغطِّ طبقة الميزات حالة تعذّر ما، غابت عن القياس دون أن يعني ذلك عدم وجودها.

---

## 4. الاستعلامات (Queries)

> **جدول توضيحي — بانتظار الاعتماد.** يُفترَض مستودع أحداث بالمخطّط:
> `events(event_name TEXT, session_id TEXT /* anonymous */, ts TIMESTAMP, params JSONB)`.
> الاستعلامات بنكهة **PostgreSQL** وهي **توضيحية**؛ اسم المستودع وموقعه وسياسة الاحتفاظ قرارات مفتوحة (§9 من التدقيق). النوافذ الزمنية أمثلة (`30 days`) وتُضبط لاحقًا.

**‏(أ) معدّل التفعيل — النجم الشمالي: نسبة الجلسات المُتِمّة إلى الجلسات البادئة.**
```sql
SELECT
  COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'plan_finalized')::numeric
    / NULLIF(COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'flow_started'), 0)
    AS activation_rate
FROM events
WHERE ts >= NOW() - INTERVAL '30 days';
```

**‏(ب) قِمع الثقة — عدد الجلسات المميّزة عند كل مرحلة وتحوّل كل خطوة عبر تجميع شرطي.**
```sql
WITH funnel AS (
  SELECT
    COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'flow_started')     AS s1_started,
    -- S2: plan_seeded فقط — plan_restored حدث مختلف ومُستبعَد عمدًا (عدّه بذرة يضخّم القُمع كذبًا)
    COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'plan_seeded')      AS s2_seeded,
    COUNT(DISTINCT session_id) FILTER (WHERE event_name IN
        ('item_pinned','item_rejected','item_swapped','budget_changed'))      AS s3_engaged,
    COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'plan_finalized')   AS s4_finalized,
    -- إشارات مُلاصِقة (ليست مراحل قُمع):
    COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'input_submitted')  AS aux_input,
    COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'plan_shared')      AS aux_shared
  FROM events
  WHERE ts >= NOW() - INTERVAL '30 days'
)
SELECT
  s1_started, s2_seeded, s3_engaged, s4_finalized, aux_input, aux_shared,
  round(s2_seeded::numeric    / NULLIF(s1_started, 0),  3) AS cvr_started_seeded,
  round(s3_engaged::numeric   / NULLIF(s2_seeded, 0),   3) AS cvr_seeded_engaged,
  round(s4_finalized::numeric / NULLIF(s3_engaged, 0),  3) AS cvr_engaged_finalized,
  round(s4_finalized::numeric / NULLIF(s1_started, 0),  3) AS overall_completion
FROM funnel;
```

**‏(ج) قِمع الإيراد — نسبة النقر إلى التاجر (CTR) بين الجلسات المستكشِفة، إجمالًا وحسب `category`.**
```sql
WITH rev AS (
  SELECT
    COUNT(DISTINCT session_id) FILTER (WHERE event_name IN ('options_opened','ar_opened')) AS explored,
    COUNT(DISTINCT session_id) FILTER (WHERE event_name = 'merchant_click')                AS clicked
  FROM events
  WHERE ts >= NOW() - INTERVAL '30 days'
)
SELECT
  explored, clicked,
  round(clicked::numeric / NULLIF(explored, 0), 3) AS merchant_ctr
FROM rev;

-- توزيع نيّة الشراء حسب الفئة (product_id/category غير شخصيين):
SELECT
  params->>'category'        AS category,
  COUNT(*)                   AS click_events,
  COUNT(DISTINCT session_id) AS clicking_sessions
FROM events
WHERE event_name = 'merchant_click'
  AND ts >= NOW() - INTERVAL '30 days'
GROUP BY params->>'category'
ORDER BY clicking_sessions DESC;
```

**‏(د) معدّل العودة — حصّة الجلسات التي استرجعت خطة محفوظة من الجلسات النشطة.**
```sql
WITH active AS (
  SELECT COUNT(DISTINCT session_id) AS n
  FROM events
  WHERE ts >= NOW() - INTERVAL '30 days'
),
restored AS (
  SELECT COUNT(DISTINCT session_id) AS n
  FROM events
  WHERE event_name = 'plan_restored'
    AND ts >= NOW() - INTERVAL '30 days'
)
SELECT
  restored.n AS returning_sessions,
  active.n   AS active_sessions,
  round(restored.n::numeric / NULLIF(active.n, 0), 3) AS return_rate
FROM active, restored;
```

**‏(هـ) الطلب غير الملبّى — توزيع `need_unmet` حسب `reason_code`.**
```sql
SELECT
  params->>'reason_code'     AS reason_code,
  COUNT(*)                   AS unmet_events,
  COUNT(DISTINCT session_id) AS affected_sessions
FROM events
WHERE event_name = 'need_unmet'
  AND ts >= NOW() - INTERVAL '30 days'
GROUP BY params->>'reason_code'
ORDER BY unmet_events DESC;
```

---

## 5. لوحة القيادة المقترحة

مجموعة موجزة من المقاييس الرئيسية للعرض. **التحديث دفعيّ** (batch)؛ لا حاجة لزمن حقيقي — التحليلات تُلاحِظ ولا تقود سلوكًا آنيًا.

| # | المقياس | العائلة | التعريف المختصر | البُعد الأساسي | وتيرة التحديث |
|---|---|---|---|---|---|
| 1 | `activation_rate` ⭐ | التفعيل | `plan_finalized / flow_started` | `experience` | يومي |
| 2 | `overall_completion` | قِمع الثقة | إتمام كلّي (`flow_started → plan_finalized`) | `experience` | يومي |
| 3 | `step_conversions` (started→seeded→engaged→finalized) | قِمع الثقة | تحوّل كل خطوة عبر المراحل الأربع | مرحلة | يومي |
| 4 | `abandonment_by_stage` | قِمع الثقة | `session_abandoned` حسب `last_stage` | `last_stage` | يومي |
| 5 | `merchant_ctr` | الإيراد | `merchant_click / (options_opened∪ar_opened)` | `experience` | يومي |
| 6 | `merchant_clicks_by_category` | الإيراد | توزيع نيّة الشراء | `category` | يومي |
| 7 | `return_rate` | العودة | `plan_restored / active sessions` | `source`, `age_bucket` | أسبوعي |
| 8 | `share_rate` | قِمع الثقة/العودة | `plan_shared / plan_finalized` | `channel` | أسبوعي |
| 9 | `unmet_by_reason` | الطلب | `need_unmet` حسب `reason_code` | `reason_code` | يومي |
| 10 | `ar_engagement` | الإيراد/المعاينة | جلسات `ar_opened` (تعمّق المعاينة) | `trigger` | أسبوعي |

> جميع المقاييس تُحسب على `session_id` مجهول ومن `params` أولية فقط. أي بطاقة تعرض «عددًا مطلقًا» يجب أن تُذيَّل بـ«ضمن العيّنة الموافِقة» تفاديًا لإيهام التغطية الكاملة.

---

## 6. فجوات القياس

أسئلة **لا** تستطيع أحداث الكتالوج الحالية (16 حدثًا) الإجابة عنها. كلٌّ منها **يُرفع كاقتراح حدث مستقبلي عبر هذا الـ workstream (Track 5)** ويمرّ بتحديث الكتالوج + `analytics_funnel_test` في الالتزام نفسه؛ **لا** يُخترع أي حدث هنا.

| # | السؤال غير القابل للقياس الآن | لماذا | مسار المعالجة المقترح |
|---|---|---|---|
| 1 | **التحوّل بعد النقر إلى شراء/عمولة.** | `merchant_click` نيّة فقط؛ لا حدث `purchase_*` والتأكيد يقع خارج العميل. | يتبع «خطة الإيراد»؛ ربط خارجي عبر شبكة الأفلييت، أو اقتراح حدث تأكيد لاحقًا عبر Track 5. |
| 2 | **الاحتفاظ الحقيقي بمستخدم عبر الزمن.** | الهوية مجهولة وقابلة للتدوير؛ `plan_restored` إشارة استرجاع لا هوية مستمرّة. | قرار سياسة تدوير المُعرّف (§9 تدقيق) قبل أي مقياس retential حقيقي. |
| 3 | **توزيع حالة الموافقة (granted/denied/absent).** | لا حدث يلتقط تغيّر الموافقة؛ القيَم في `consent_store` لا في مجرى الأحداث. | اقتراح حدث موافقة مجهول (بلا PII) عبر Track 5 إن لزم قياس التبنّي. |
| 4 | **حجم الأحداث المُسقَطة (drop-oldest/buffer overflow) والفشل الصامت.** | الفشل الصامت مقصود؛ لا يوجد حدث meta يرصد إسقاطًا أو تجاوز `maxBuffer`. | اقتراح عدّاد تشغيلي مجهول (operational metric) منفصل عن قُمع المستخدم. |
| 5 | **القيمة/السعر الكامن خلف نيّة الشراء.** | `merchant_click = {product_id, category}` بلا سلّة قيمة؛ ولا مبلغ خام (سياسة PII). | إن لزم ترجيح النيّة بالقيمة: اقتراح `value_bucket` مُعدَّل عبر Track 5. |
| 6 | **سبب فشل أمر المساعد.** | `assistant_command = {command_kind, success}`؛ `success=false` بلا `reason_code`. | اقتراح إضافة `reason_code` مُعدَّل لـ `assistant_command` عبر Track 5. |
| 7 | **الترتيب الزمني الصارم داخل قُمع الثقة على مستوى الجلسة.** | الحساب بعدّ حضور المرحلة لا تسلسلها؛ قد يعطي تحوّلًا > 100%. | قابل للاشتقاق جزئيًا من `ts` بتحليل تسلسلي، لكنه خارج نموذج القُمع المعتمد؛ يُوثَّق كقيد لا كحدث. |
| 8 | **الطلب الصامت (استسلام دون `need_unmet`).** | يُلتقط `need_unmet` فقط حين يُصدره المحرك؛ الاستسلام الصامت غير مرصود. | يُقارب عبر `session_abandoned.last_stage`، لا يُغطّى كاملًا؛ قيد موثّق. |
| 9 | **الرحلة عبر التجارب (assistant → my_room → preview).** | الربط عبر الجلسة محدود؛ لا حدث انتقال بين التجارب. | اقتراح حدث انتقال مجهول عبر Track 5 إن لزم تحليل الرحلة المتقاطعة. |

---

> **الخلاصة:** هذه مواصفة مقاييس **مقترحة — بانتظار الموافقة**، مبنية حرفيًّا على كتالوج `docs/analytics_audit.md`. عند الاعتماد تُثبَّت العائلات والاستعلامات ولوحة القيادة، وتُشتق منها بطاقات `docs/telemetry_analytics.md`، وتُحرَس صحّة القُمع بـ`test/analytics/analytics_funnel_test.dart`. أي فجوة في §6 لا تُسدّ باختراع حدث بل باقتراحٍ يمرّ عبر Track 5 مع تحديث الكتالوج والاختبار معًا.
