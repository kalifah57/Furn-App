# تدقيق التوصيل G1 — القياس والموافقة والمصارف (Wiring Audit)

> **تقرير فجوات — بانتظار موافقة المؤسّس (Gap report — pending founder approval).**
> تدقيق **مبنيّ على الكود الفعليّ** بعد دمج فرع المعماري. **تدقيق فقط: لا إصلاح ولا كود قبل الموافقة** (الانضباط: Audit → Design → Approval → Implementation).
> يَحلّ هذا التقرير محلّ مسودّة التدقيق السابقة التي كُتبت على افتراض مستودع فارغ.
>
> **الحاكم عند التنازع:** `docs/agent_workstreams.md` · **بريف المسار:** `docs/workstreams/5_growth_analytics.md` · **الكتالوج الحيّ:** `docs/analytics_events.md`.
> **الملكية (المسار ٥):** `lib/analytics/**` + منطق الموافقة `lib/features/consent/**` (عدا البانر = مسار ٤) + وثائق القياس. **نقاط النداء لأصحابها؛ تعريف الأحداث عبرنا.**

---

## 0. الخلاصة التنفيذية (Verdict)

**البنية سليمة ومختبَرة جيدًا في جوهرها**، والمبادئ الحاكمة محترمة في معظمها: الموافقة معطّلة افتراضيًا، البوابة قبل التخزين، فشل صامت محدود، معرّف جلسة مجهول، `plan_restored` ليست بذرة (مثبَّت بالبناء والاختبار)، وحارس نقاء المحرّك قائم. **لكن خمس فجوات تحتاج قرارًا وإصلاحًا:**

1. **حدث `need_unmet` غير موصَّل إطلاقًا** — إشارة الطلب لا تُجمَع (High).
2. **تسريب نصّ خام (PII) في `need_unmet.raw_type`** — يخالف عقد «بلا PII» صراحةً ويصل إلى الشبكة (High/PII).
3. **مصرف `DebugAnalytics` يتجاوز الموافقة** في التركيب (يجمع في وضع التطوير بلا إذن) (Medium).
4. **لا فرض لـ HTTPS** على `ANALYTICS_ENDPOINT` — يقبل `http://` عاديًّا (Medium/Security).
5. **لا حارس اختباريّ لـ PII/أوّليّة الـ params** — لذلك تسلّل `raw_type` دون أن يكسر اختبارًا (Medium).

**لا أنفّذ أيًّا من الإصلاحات قبل موافقتك.** خطة الإصلاح المرتّبة في §6، والقرارات المطلوبة في §7.

---

## 1. مصفوفة التوصيل — الكتالوج (١٦ حدثًا) مقابل المُوصَّل فعلًا

| # | event_name | موصَّل؟ | نقطة النداء (call site) | ملاحظة |
|---|---|---|---|---|
| 1 | `flow_started` | ✅ | `onboarding_screen.dart:56,69` (`onboarding` \| `sample_plan`) | مقام التفعيل. |
| 2 | `input_submitted` | ✅ | `flow_controller.dart:87` | — |
| 3 | `plan_seeded` | ✅ | `plan_controller.dart:92` (عند البناء) | — |
| 4 | `plan_restored` | ✅ | `plan_controller.dart:86` (بديل حصريّ للبذرة) | **ليست بذرة** — مثبَّت بالبناء + اختبار. |
| 5 | `item_pinned` | ✅ | `plan_controller.dart:161` | — |
| 6 | `item_rejected` | ✅ | `plan_controller.dart:170` | — |
| 7 | `item_swapped` | ✅ | `plan_controller.dart:176` | — |
| 8 | `budget_changed` | ✅ | `plan_controller.dart:184` | `newMax` مبلغ خام (§GAP-3). |
| 9 | `options_opened` | ✅ | `plan_controller.dart:298` | — |
| 10 | `ar_opened` | ✅ | `ar_button.dart:36,81` (productId \| `demo`) | — |
| 11 | `merchant_click` | ✅ | `sandbox_screen.dart:211` | **إشارة الإيراد المرساة.** غير مذكور في «Wire points» بالكتالوج (§GAP-8). |
| 12 | `plan_finalized` | ✅ | `plan_controller.dart:194` | بسط التفعيل. |
| 13 | `plan_shared` | ✅ | `plan_controller.dart:300` | — |
| 14 | `assistant_command` | ✅ | `plan_controller.dart:225` | `understood` يغذّي G5. |
| 15 | `session_abandoned` | ✅ | `plan_controller.dart:307` | مرّة واحدة (اختبار). |
| 16 | `need_unmet` | ❌ **غير موصَّل** | — لا شيء في `lib/` — | مُعرَّف + موثَّق + مُختبَر في `http_analytics_test.dart:83` فقط، ولا يُطلقه أي مسار. **إشارة الطلب صفر.** |

**الحصيلة: ١٥/١٦ موصَّلة.** `need_unmet` مُعرَّف بلا نقطة نداء.

---

## 2. الفجوات وإصلاحها المقترح

| ID | الفجوة | الخطورة | الدليل | الإصلاح المقترح (بعد الموافقة) |
|---|---|---|---|---|
| **GAP-1** | `need_unmet` مُعرَّف وموثَّق لكنه **لا يُطلَق من أي مكان**؛ إشارة الطلب (قائمة التسوّق بالطلب الحقيقي) لا تُجمَع. | **High** | لا مثيل لـ `NeedUnmet(` في `lib/`؛ الوحيد في `test/analytics/http_analytics_test.dart:83`. «Wire points» في `analytics_events.md` تُغفله. | **يُطلَق عند تعذّر التلبية** (مسار المساعد `UnknownCommand`، أو سطح «طلب غير مخدوم» في الخطة/الغرفة). النداء ملك مسار ٣/٤؛ **أعرّف الحدث وأنسّق، وهم يضيفون النداء** — بعد حسم شكل `raw_type` (GAP-2). |
| **GAP-2** | **PII:** `need_unmet.raw_type` يحمل **نصّ المستخدم كما كتبه**، ويصل إلى حمولة الشبكة. يخالف عقد `AnalyticsEvent` («قيَم بدائية فقط — بلا PII») و`telemetry_analytics.md §3` والبريف. النص الحرّ قد يحوي اسمًا/مكانًا/رقمًا. | **High / PII** | `analytics.dart:237` (تعليق «نصّ المستخدم كما كتبه») + `:251` (`'raw_type': rawType`) → `http_analytics.dart:64` (`'params': event.params`) → موثَّق `analytics_events.md:52` → **مؤكَّد كسلوك متوقَّع** في `http_analytics_test.dart:90`. | استبدال `raw_type` بـ **`requested_type` مُعدَّل من مفردات مغلقة** يعرفها المُحلِّل (غير المعروف ⇒ `other`)، فيبقى مقياس الطلب دون نصّ حرّ. تحديث الكتالوج + تعديل `http_analytics_test.dart:83-90` + إضافة حارس PII (GAP-6). *(بديل يحتاج قرارك: الاحتفاظ بالمصطلح بعد تطبيع صارم لقائمة بيضاء — أضعف خصوصيًّا.)* |
| **GAP-3** | مبالغ خام في الـ params: `budget_changed.newMax`، `plan_seeded.total`، `need_unmet.reserve_sar`، و`confidence`. **ليست PII** (لا تُعرِّف شخصًا) والعقد «بدائيّ» محقَّق — لكنها قيَم خام لا سِلال. | Low (قرار تصميم) | `analytics.dart:139,69,243`. | **مقبولة كما هي** (قابلة للتجميع، غير معرِّفة). خيار: تسليّة المبالغ (`value_bucket`) إن رفعت منطقة/جهة الوجهة الحساسية. **قرار خصوصية لك/DPO، غير عاجل.** |
| **GAP-4** | `DebugAnalytics` يُركَّب `DebugAnalytics(log: true)` **بلا تمرير الموافقة**، فيبقى على الافتراض `consent = true`؛ في `kDebugMode` يجمع/يطبع **بصرف النظر عن موافقة المستخدم**. (الـHTTP يمرّر الموافقة صحيحًا.) | Medium | التركيب `providers.dart:54` مقابل الافتراض `analytics.dart:278`؛ الـHTTP الصحيح `providers.dart:63`. غير مُختبَر. | تمرير `consent: ref.watch(analyticsConsentProvider)` إلى `DebugAnalytics` (وجعله تفاعليًّا)، **أو** قرار موقَّع بأن جمع التطوير المحلّي (لا يغادر الجهاز) مُستثنى. **توصيتي: البوابة على Debug أيضًا** اتّساقًا مع «لا جمع بلا موافقة» — مع علم أن G2 يشغّل اللوحات على DebugAnalytics. |
| **GAP-5** | لا فرض لـ **HTTPS/TLS**: `analyticsProvider` يقبل أي وجهة بمخطّط (`uri.hasScheme`) بما فيها `http://` — فتُرسَل الأحداث (وضمنها حمولة `raw_type`) بنصّ صريح. | Medium / Security | `providers.dart:57-58`. | رفض ما ليس `https://` في التركيب (السماح بـ`http://localhost` للاختبار/التطوير فقط) + اختبار. |
| **GAP-6** | **لا حارس اختباريّ لـ PII/أوّليّة الـ params.** نقاء المحرّك محروس، أمّا لا-PII فمُعلَن بلا حارس — ولهذا تسلّل `raw_type` **وأُكِّد كسلوك متوقَّع**. | Medium | `engine_purity_test.dart` موجود؛ لا مقابل له للـ params. `http_analytics_test.dart:90` يثبّت `raw_type`. | حارس يؤكّد أن كل قيَم `params` من `{String,int,double,bool}` **وأن لا حقل بنمط نصّ حرّ** (قائمة سماح للأسماء/الأنماط)؛ ودمج `need_unmet` في تغطية القِمع بعد إعادة تشكيله. تعديل `http_analytics_test.dart` جزء من الإصلاح. |
| **GAP-7** | `telemetry_analytics.md` **مُتجاوَز** لكن البريف يعدّه وثيقة مملوكة تُحدَّث مع كل حدث؛ تصنيفه (`recommendations_viewed`, `AnalyticsService.logEvent` بخرائط حرّة) يناقض النموذج الـsealed. | Low / Doc | `telemetry_analytics.md:3-8, 27-58`. | إمّا دمجه بالكامل في `analytics_events.md` (مصدر واحد)، أو إعادة كتابته كـ«نظرة معمارية» (المصارف/الموافقة/التدفّق) وحسم التجاوز. **قرارك: تقاعد أم إعادة توظيف.** |
| **GAP-8** | «Wire points» في `analytics_events.md` غير دقيقة: تُغفل `merchant_click` (موصَّل فعلًا) و`need_unmet` (غير موصَّل)؛ وتعليق `http_analytics.dart:12` يقول «الأحداث الثلاثة عشر» (عدد قديم؛ الآن ١٦). | Low / Doc | `analytics_events.md:55-65`؛ `http_analytics.dart:12`. | تصحيح قائمة نقاط النداء لتعكس الـ١٦ ونداءها الحقيقيّ، ووسم `need_unmet` «مُعرَّف، غير موصَّل بعد». |

---

## 3. تأكيدات إيجابية (ما هو صحيح ومختبَر — ليست فجوات)

- **الموافقة معطّلة افتراضيًا:** `analyticsConsentProvider = consentController == true` ⇒ `null` و`false` كلاهما «لا جمع» (`providers.dart:45-46`)؛ مُختبَر (`consent_gate_test.dart:59-83`).
- **البوابة قبل التخزين (HTTP):** `if (!consent) return;` قبل `_buffer.add` (`http_analytics.dart:56-58`)؛ مُختبَر «بلا موافقة لا شيء يُخزَّن فلا شيء يُسرَّب لاحقًا» (`http_analytics_test.dart:107-115`).
- **التجميع والحدود:** `batchSize=20` / `flush=15s` / `maxBuffer=200` يُسقِط الأقدم (`http_analytics.dart:29-31,67-69`)؛ مُختبَر (الأحدث ينجو `[3,4,5]`).
- **فشل صامت محدود:** `track` لا يرمي أبدًا، الدفعة تُعاد ضمن السقف (`http_analytics.dart:95-107`)؛ مُختبَر.
- **الوجهة الفارغة ⇒ Noop:** لا إرسال بلا `ANALYTICS_ENDPOINT` (`providers.dart:57-69`)، والقرار كله في `analyticsProvider` لا في `main.dart`.
- **معرّف جلسة مجهول فقط:** UUID، بلا هوية (`http_analytics.dart:37`, `providers.dart:62`).
- **`plan_restored` ليست بذرة:** بديل حصريّ، مثبَّت بالبناء وثلاثة اختبارات (`analytics_funnel_test.dart:96-158`) — أهمّ حاجز في البريف، **مُنفَّذ صحيحًا**.
- **حارس نقاء المحرّك:** فحص ساكن لـ `lib/domain_engine/**` (`engine_purity_test.dart`) — يعمل بلا Flutter SDK.
- **العقد:** `Analytics` (واجهة) + `AnalyticsEvent` (sealed، ١٦ صنفًا بأنواع صريحة)، والمصارف الخمسة موجودة (`Noop/Debug/Http/FanOut/Remote-stub`).

---

## 4. تغطية الاختبارات (ما يُحرَس فعلًا)

| المجال | مُختبَر؟ | أين |
|---|---|---|
| تسلسل أحداث القِمع | ✅ | `analytics_funnel_test.dart` (قوائم `a.names` مرتّبة) |
| الموافقة عند المصرف (Debug/HTTP) تُسقِط | ✅ | `analytics_funnel_test.dart:85-94`، `http_analytics_test.dart:106-116` |
| بوابة الموافقة على مستوى المزوّد (القيمة) | ✅ | `consent_gate_test.dart` |
| تجميع/سقف/إسقاط الأقدم/فشل صامت/fan-out | ✅ | `http_analytics_test.dart` |
| نقاء المحرّك | ✅ | `engine_purity_test.dart` |
| **أوّليّة الـ params / لا-PII** | ❌ **غائب** | — (GAP-6) — بل `raw_type` **مؤكَّد** في `http_analytics_test.dart:90` |
| **التركيب يمرّر الموافقة إلى Debug** | ❌ غائب | — (GAP-4) |
| **فرض HTTPS** | ❌ غائب | — (GAP-5) |

---

## 5. الأثر على تسليماتي السابقة

مسودّاتي الأربع (`analytics_audit.md` السابقة، `analytics_metrics_spec.md`، `analytics_revenue_plan.md`، `analytics_privacy_pdpl_review.md`) كُتبت **قبل الدمج** على افتراض مستودع فارغ، فاخترعت `params` مُسلّاة/مُعدَّلة **لا تطابق الكتالوج الحقيقيّ** (الذي يستخدم `confidence`/عدّادات/مبالغ خام و`raw_type`). لذلك:

- هذا التقرير (`analytics_audit.md`) أُعيدت كتابته على الكود الحقيقيّ — **هو المرجع**.
- تُعاد مواصفة المقاييس والإيراد والخصوصية (**G2/G3/G4**) على الكتالوج الحقيقيّ؛ حتى ذلك الحين تُقرأ المسودّات الثلاث كاتجاه لا كمواصفة نافذة (سأضع وسم تجاوز على رأس كلٍّ منها).

---

## 6. خطة الإصلاح المرتّبة (تُنفَّذ بعد الموافقة فقط)

1. **GAP-2 أوّلًا (يحجب GAP-1):** إعادة تشكيل `need_unmet` — استبدال `raw_type` بـ`requested_type` مُعدَّل من مفردات مغلقة؛ تحديث `analytics.dart` + `analytics_events.md` + `http_analytics_test.dart`.
2. **GAP-6:** إضافة حارس أوّليّة/لا-PII للـ params (يمنع تكرار المشكلة، ويحرس ما بعده).
3. **GAP-1:** توصيل `need_unmet` عند مواضع تعذّر التلبية — **spec أعرّفه، ونداء يضيفه مسار ٣/٤** عبر المعماري (وصلة `AnalyticsEvent`).
4. **GAP-4 + GAP-5:** تمرير الموافقة إلى `DebugAnalytics` + رفض ما ليس `https` في `analyticsProvider` + اختباراهما.
5. **GAP-8 ثم GAP-7:** تصحيح «Wire points» والعدّاد القديم؛ حسم مصير `telemetry_analytics.md`.

كل تغيير أحداث يحدّث `docs/analytics_events.md` والاختبارات في الالتزام نفسه، **دون كسر `analytics_funnel_test`** (تسلسل الأحداث).

---

## 7. القرارات المطلوبة منك (المؤسّس)

1. **`need_unmet.raw_type`:** الموافقة على استبداله بـ`requested_type` مُعدَّل (توصيتي) — أم إبقاء المصطلح مع تطبيع صارم لقائمة بيضاء؟ *(الأول أسلم خصوصيًّا.)*
2. **جمع Debug المحلّي (GAP-4):** إخضاعه للموافقة (توصيتي) أم استثناؤه صراحةً كأداة تطوير محلّية لا تغادر الجهاز؟
3. **`telemetry_analytics.md` (GAP-7):** تقاعده لصالح `analytics_events.md`، أم إعادة توظيفه نظرةً معمارية؟
4. **المبالغ الخام (GAP-3):** إبقاؤها (توصيتي) أم تسليتها؟

> **قِف للموافقة.** لا يُكتَب أيّ إصلاح حتى تحسم ما سبق. عند الموافقة أبدأ بترتيب §6، وأنسّق نقاط النداء المملوكة لمسارات أخرى عبر المعماري.
