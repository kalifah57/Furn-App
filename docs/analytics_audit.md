# تدقيق التحليلات — Furn-App

> **مقترح — بانتظار الموافقة (Proposal — pending approval)**
> هذه وثيقة تصميم وتدقيق (Audit/Design). الغرض منها التحديد والاقتراح فقط، لا التنفيذ. لا تحتوي على كود تنفيذي بلغة Dart سوى تواقيع توضيحية صغيرة.
>
> **مبادئ حاكمة:** «الخطة هي المنتج» · «الثقة هي النتيجة» · «التسوّق اختياري».
> **قاعدة القياس العليا:** «تلاحظ ولا تغيّر» — التحليلات تُلاحِظ من الخارج ولا تغيّر سلوك المنتج ولا حلقة الثقة. و«الأرقام تُرشد لا تقرّر».
> **الملكية (Track 5):** `lib/analytics/**` + منطق الموافقة `lib/features/consent/**` (عدا البانر = Track 4: لنا المخزن والمتحكّم ومنطق البوابة، لا واجهة البانر) + وثائق `docs/analytics_events.md` و`docs/telemetry_analytics.md`.
> **الحاكم عند التنازع في الحدود:** `docs/agent_workstreams.md`، والبريف الكامل لهذا المسار `docs/workstreams/5_growth_analytics.md` (كلاهما غير موجود بعد في هذا المستودع الفارغ — يُشار إليهما ولا يُختلقان).

---

## 1. ملخّص تنفيذي

**الواقع الحالي (greenfield):** المستودع فارغ فعليًا. لا يوجد سوى `README.md`. لا `lib/`، ولا `docs/` (سوى هذه الوثيقة)، ولا `test/`، ولا أي كود من أي نوع، ولا `docs/agent_workstreams.md`. أي كل ما يرد أدناه هو الهدف/النية (target/intent) وليس شيئًا مُنفَّذًا.

**الهدف (target):** طبقة تحليلات تُلاحِظ سلوك المستخدم عبر التجارب الثلاث (Assistant · My Room · Preview) من خلال واجهة `Analytics` واحدة، وأحداث مُصنَّفة بنوع صريح (`AnalyticsEvent` كتسلسل `sealed`)، تُرسَل عبر «مصارف» (Sinks) قابلة للتركيب، مع بوابة موافقة (consent) مُعطَّلة افتراضيًا وفق نظام حماية البيانات الشخصية السعودي (PDPL)، وحارس نقاء (purity guard) يمنع أي تسرّب للتحليلات إلى المحرك النقي.

**الفجوة (الفجوة في فقرة واحدة):** الفجوة كاملة. لا شيء من العقد أو الكتالوج أو المصارف أو التركيب أو الموافقة أو اختبارات النقاء والقُمع مُنفَّذ؛ الحالة لكل مكوّن هي «غير مُنفَّذ / مقترح». هذه الوثيقة تُحوِّل النية إلى مواصفة قابلة للاعتماد والتنفيذ لاحقًا، وتحصر القرارات المفتوحة التي يجب حسمها قبل كتابة أي سطر تنفيذي.

---

## 2. عقد القياس (The contract)

التحليلات = **واجهة** واحدة. كل ما عداها (مصارف، تركيب، موافقة) يقف خلفها. الكود يعتمد على الواجهة لا على التفاصيل.

```dart
// توضيحي فقط — لا يُعتمد كتنفيذ
abstract class Analytics {
  void log(AnalyticsEvent event);
}
```

الحدث نفسه نموذج `sealed` بأنواع فرعية صريحة، وشكله الثابت:

```dart
// توضيحي فقط — الشكل، لا التنفيذ
sealed class AnalyticsEvent {
  String get name;                  // snake_case ثابت ومستقر
  Map<String, Object?> get params;  // قيم أولية فقط (primitives)، بلا PII
}

// مثال على نوع فرعي صريح
final class MerchantClick extends AnalyticsEvent {
  final String productId;
  final String category;
  // name => 'merchant_click'
  // params => { 'product_id': productId, 'category': category }
}
```

**قواعد العقد الثلاث الملزِمة:**

1. **`name` = snake_case ثابت ومستقر.** الاسم عقد عام؛ لا يتغيّر بمرور الزمن لأن لوحات القياس والاستعلامات تُبنى عليه. تغيير اسم = تغيير عقد = تحديث الكتالوج + الاختبارات.
2. **`params` = قيم أولية فقط (`String`, `int`, `double`, `bool`).** لا كائنات متداخلة، لا قوائم حرّة، لا خرائط ديناميكية. هذا يضمن قابلية التسلسل (serialization) والاستعلام الحتمي.
3. **لا PII إطلاقًا.** لا اسم، لا بريد، لا رقم هاتف، لا نص مُدخَل خام، لا محتوى غرفة، لا صورة، لا مُعرِّف مستخدم. كل قيمة إمّا مُعدّدة (enum) أو مُجمّعة في «سلّة» (bucket) أو مُعرّف منتج/فئة غير شخصي. مُعرّف الجلسة **مجهول** فقط.

---

## 3. كتالوج الأحداث (Event catalog)

الأحداث الستة عشر (16) كاملةً. كل `params` **مجهولة، مُعدَّدة أو مُجمّعة في سِلال، ولا تحمل محتوى المستخدم الخام أبدًا**. القيم المُعدَّدة أدناه مقترحة وتُثبَّت عند الاعتماد في `docs/analytics_events.md`.

| event_name | متى يُطلق (trigger) | التجربة/المسار المالك | params (typed, primitives, no PII) | ملاحظات |
|---|---|---|---|---|
| `flow_started` | بدء أي مسار تخطيط | Assistant · My Room · Preview | `{ experience: String(enum: assistant\|my_room\|preview), source: String(enum: home\|deeplink\|resume\|share) }` | مقام القُمع (مقام التفعيل). |
| `input_submitted` | إرسال المستخدم مُدخَلًا للمحرك | Assistant · My Room | `{ input_kind: String(enum: text\|dimensions\|image\|voice), has_image: bool }` | **لا نص خام إطلاقًا**؛ فقط نوع المُدخَل ووجود صورة. |
| `plan_seeded` | توليد الخطة الأولى من المحرك | Assistant · My Room | `{ experience: String, item_count_bucket: String(enum: xs\|s\|m\|l\|xl) }` | إشارة بدء بناء الخطة. |
| `plan_restored` | استرجاع خطة محفوظة عند العودة | Assistant · My Room · Preview | `{ source: String(enum: local\|link), age_bucket: String(enum: h1\|d1\|d7\|d30\|older) }` | **إشارة العودة** (return signal) — **لا تُحسب بذرة (not a seed)**؛ عدّها ضمن `plan_seeded` يضخّم القُمع كذبًا. |
| `item_pinned` | تثبيت المستخدم لعنصر في الخطة | My Room · Preview | `{ category: String, position_bucket: String(enum: early\|mid\|late) }` | التزام إيجابي داخل حلقة الثقة. |
| `item_rejected` | رفض المستخدم لعنصر مقترح | My Room · Preview | `{ category: String, reason_code: String(enum: size\|style\|price\|other) }` | لا سبب حرّ؛ رمز مُعدَّد فقط. |
| `item_swapped` | استبدال عنصر بآخر | My Room · Preview | `{ category: String, swap_source: String(enum: engine\|user) }` | تفاعل تنقيح الخطة. |
| `budget_changed` | تعديل الميزانية | Assistant · My Room | `{ direction: String(enum: up\|down), bucket: String(enum: low\|mid\|high\|premium) }` | اتجاه وسلّة فقط، لا مبلغ خام. |
| `options_opened` | فتح لوحة الخيارات/البدائل | My Room · Preview | `{ category: String, options_count_bucket: String(enum: s\|m\|l) }` | إشارة استكشاف. |
| `ar_opened` | فتح العرض الواقعي/المعزّز | Preview | `{ trigger: String(enum: item\|scene), item_count_bucket: String(enum: xs\|s\|m\|l\|xl) }` | تعمّق في المعاينة. |
| `merchant_click` | نقر المستخدم للانتقال إلى التاجر | Preview · My Room | `{ product_id: String, category: String }` | **حدث الإيراد المفتاح** — أول إشارة نيّة شراء. مدخل قُمع الإيراد. |
| `plan_finalized` | إتمام/تثبيت الخطة النهائية | Assistant · My Room · Preview | `{ experience: String, item_count_bucket: String, duration_bucket: String(enum: m1\|m5\|m15\|m30\|longer) }` | **بسط التفعيل** (Activation). |
| `plan_shared` | مشاركة الخطة | Assistant · My Room · Preview | `{ channel: String(enum: link\|image\|native), has_items: bool }` | إشارة انتشار/ثقة اجتماعية. |
| `assistant_command` | تنفيذ أمر عبر المساعد | Assistant | `{ command_kind: String(enum: add\|remove\|resize\|arrange\|explain), success: bool }` | نوع الأمر ونجاحه فقط، لا نص الأمر. |
| `need_unmet` | تعذّر تلبية طلب المستخدم | Assistant · My Room · Preview | `{ reason_code: String(enum: no_match\|out_of_budget\|unsupported\|out_of_stock) }` | **إشارة الطلب** (demand)؛ **رمز مُعدَّد لا نص حرّ**. |
| `session_abandoned` | ترك الجلسة دون إتمام | Assistant · My Room · Preview | `{ last_stage: String(enum: input\|seeded\|editing\|preview\|checkout_intent), duration_bucket: String(enum: m1\|m5\|m15\|longer) }` | إشارة تسرّب في القُمع. |

> **تعهّد الخصوصية للكتالوج:** كل قيمة في كل `params` أعلاه إمّا مُعدَّدة (enum مغلق) أو سلّة مُجمّعة (bucket) أو `product_id`/`category` غير شخصيين أو `bool`. **لا يظهر محتوى المستخدم الخام (نص، أبعاد دقيقة، صورة، مبلغ، اسم) في أي حدث.**

---

## 4. الـSinks (المصارف)

المصرف هو وِجهة الحدث بعد `log`. التركيب يختار المصرف؛ الكود المُنتِج للأحداث لا يعرف أيّها فعّال.

| Sink | السلوك | الإعداد/التهيئة |
|---|---|---|
| `NoopSink` | لا يفعل شيئًا (الافتراضي الآمن). | بلا إعداد؛ يُستخدم حين لا وجهة إرسال. |
| `DebugSink` | يطبع الحدث محليًا للسجل. | **للتطوير فقط (dev only)**؛ لا يُفعَّل في الإنتاج. |
| `HttpSink` | يجمِّع الأحداث ويرسلها دفعات إلى نقطة نهاية HTTP. | `batch=20`، `flush=15s`، `maxBuffer=200` (يُسقِط **الأقدم** عند الامتلاء)، **يفحص الموافقة قبل التخزين لا قبل الإرسال**، **فشل صامت محدود** عند خطأ الشبكة (لا يُسقِط شاشة المستخدم). |
| `FanOutSink` | يبثّ الحدث الواحد إلى عدّة مصارف. | قائمة مصارف فرعية؛ فشل أحدها لا يوقف البقية. |
| `RemoteSink` | جذع (stub) للتكامل البعيد لاحقًا. | مؤجَّل؛ لا سلوك فعلي الآن. |

**HttpSink بدقّة:**

- **التجميع (batch):** يُرسِل عند اكتمال **20** حدثًا، **أو** عند انقضاء **15 ثانية** منذ آخر إرسال — أيّهما أسبق.
- **الحدّ الأقصى للمخزن (maxBuffer):** **200** حدثًا. عند الامتلاء يُسقَط **الأقدم** (drop oldest) لصالح الأحدث.
- **بوابة الموافقة:** يُفحص consent **قبل التخزين لا قبل الإرسال** — أي عند إدخال الحدث إلى المخزن المؤقّت (enqueue). لا موافقة (`null`/`false`) ⇐ لا تخزين، وبالتالي لا إرسال. ما دخل المخزن تحت موافقة سارية يُرسَل ضمن دفعته (انظر القرار المفتوح حول سحب الموافقة والمخزن في §9).
- **الفشل الصامت المحدود:** أي خطأ شبكة يُبتلع بصمت وضمن حدود (لا حلقات إعادة غير محدودة، لا انتظار يوقف الواجهة). **تعطّل التحليلات لا يُعطِّل ولا يُسقِط شاشة المستخدم أبدًا.**

**تسلسل الحدث (enqueue → gate → batch → flush → fail-silent):**

1. **enqueue:** يصل الحدث إلى `HttpSink.log`.
2. **gate (بوابة الموافقة، قبل التخزين):** إن كانت الموافقة `null` أو `false` ⇐ يُسقَط الحدث فورًا **قبل أي تخزين**. إن كانت `granted` ⇐ يُخزَّن في المخزن المؤقّت.
3. **buffer:** يُضاف إلى المخزن؛ إن تجاوز `maxBuffer=200` يُسقَط الأقدم.
4. **batch/flush:** يُرسَل عند بلوغ 20 حدثًا أو عند مؤقّت 15s.
5. **fail-silent:** عند فشل الإرسال يُبتلع الخطأ بصمت؛ لا استثناء يصعد للواجهة، ولا أثر على الشاشة.

---

## 5. التركيب (Composition)

كل قرارات الربط (wiring) تعيش في `analyticsProvider`. الكود المُنتِج للأحداث لا يتخذ قرارات إرسال.

**`analyticsProvider` — منطق القرار:** المصدر الوحيد للقرار هو `--dart-define=ANALYTICS_ENDPOINT` (تعريف وقت-بناء، لا قراءة بيئة وقت-تشغيل)، مع تفعيل `DebugSink` في التطوير:

```
sinks = []
if (kDebugMode)                    => sinks += DebugSink()          // تطوير فقط
if (ANALYTICS_ENDPOINT غير فارغة)  => sinks += HttpSink(endpoint)   // خلف بوابة الموافقة
=> analytics = sinks.isEmpty ? NoopSink() : FanOutSink(sinks)
```

- **التطوير:** `DebugSink` فعّال؛ فإن وُجدت النقطة أيضًا ⇒ `FanOutSink([DebugSink, HttpSink])`.
- **الإنتاج:** لا `DebugSink`؛ نقطة موجودة ⇒ `HttpSink` فقط؛ نقطة فارغة ⇒ `NoopSink` (لا إرسال).
- الافتراض الآمن دائمًا: `--dart-define=ANALYTICS_ENDPOINT` فارغة/غير مضبوطة ⇐ لا إرسال.

**`analyticsConsentProvider`:** يعرض حالة الموافقة الحالية لطبقة المصارف كي تفحصها البوابة قبل التخزين. قراءة فقط من منظور المصرف.

**`consentControllerProvider`:** يُبدِّل حالة الموافقة (mutate). تستدعيه واجهة لافتة الموافقة (Track 4) عند اختيار المستخدم الصريح.

**`consent_store`:** يحفظ المفتاح `furn.analytics_consent` بقيم `granted` / `denied` / `absent(=null)`. **الافتراض = OFF.** كلٌّ من `null` و`false` يعني **لا جمع**. التفعيل يتطلّب opt-in صريحًا. الجلسة مجهولة الهوية فقط (anonymous session id، بلا هوية مستخدم).

---

## 6. حارس النقاء (Purity guard)

**لماذا:** المحرك النقي `lib/domain_engine/` هو «المنتج» ومصدر الثقة؛ قراره حتمي وقابل للاختبار بمعزل. لو استورد التحليلات، لاختلط القرار بالمراقبة، ولانتُهك مبدأ «تلاحظ ولا تغيّر»، ولأصبح المحرك قابلًا للكسر بأعطال شبكة أو موافقة. لذلك: **`lib/domain_engine/` يجب ألا يستورد التحليلات إطلاقًا.**

**كيف تحدث الملاحظة من الخارج:** طبقة الميزات (feature-layer providers/listeners) تستمع إلى حالة المحرك (engine state) وتُصدِر الأحداث. المحرك يُصدِر حالة؛ المُراقِب في الخارج يترجم تغيّر الحالة إلى `AnalyticsEvent`. المحرك لا يعلم بوجود تحليلات.

**كيف يُفرَض:** عبر `test/analytics/engine_purity_test.dart` — فحص ساكن (static scan):

- يقرأ ملفات `lib/domain_engine/**` ويبحث عن أي استيراد ممنوع (`import` يشير إلى `lib/analytics/` أو أي حزمة تحليلات).
- وجود أي استيراد ممنوع ⇐ **فشل الاختبار**.
- لا يشغّل المحرك؛ فحص نصّي/ساكن للاستيرادات فقط، ما يناسب غياب Flutter SDK (تحقّق بالتحليل الساكن، لا بتشغيل حيّ).

---

## 7. جدول الحالة (Wired-vs-missing)

المستودع فارغ، لذا حالة كل مكوّن **«غير مُنفَّذ / مقترح»**.

| المكوّن | الحالة | ملاحظة |
|---|---|---|
| `Analytics` (الواجهة) | غير مُنفَّذ / مقترح | العقد الأساسي؛ يُشتق منه كل شيء. |
| `AnalyticsEvent` (sealed model) | غير مُنفَّذ / مقترح | `{ name, params }`، أنواع فرعية صريحة. |
| `flow_started` | غير مُنفَّذ / مقترح | مقام التفعيل. |
| `input_submitted` | غير مُنفَّذ / مقترح | لا نص خام. |
| `plan_seeded` | غير مُنفَّذ / مقترح | بدء بناء الخطة. |
| `plan_restored` | غير مُنفَّذ / مقترح | إشارة العودة. |
| `item_pinned` | غير مُنفَّذ / مقترح | التزام داخل حلقة الثقة. |
| `item_rejected` | غير مُنفَّذ / مقترح | `reason_code` مُعدَّد. |
| `item_swapped` | غير مُنفَّذ / مقترح | تنقيح الخطة. |
| `budget_changed` | غير مُنفَّذ / مقترح | اتجاه + سلّة. |
| `options_opened` | غير مُنفَّذ / مقترح | إشارة استكشاف. |
| `ar_opened` | غير مُنفَّذ / مقترح | تعمّق المعاينة. |
| `merchant_click` | غير مُنفَّذ / مقترح | **حدث الإيراد المفتاح**. |
| `plan_finalized` | غير مُنفَّذ / مقترح | بسط التفعيل. |
| `plan_shared` | غير مُنفَّذ / مقترح | انتشار/ثقة. |
| `assistant_command` | غير مُنفَّذ / مقترح | نوع الأمر لا نصّه. |
| `need_unmet` | غير مُنفَّذ / مقترح | إشارة الطلب. |
| `session_abandoned` | غير مُنفَّذ / مقترح | تسرّب القُمع. |
| `NoopSink` | غير مُنفَّذ / مقترح | الافتراضي الآمن. |
| `DebugSink` | غير مُنفَّذ / مقترح | للتطوير فقط. |
| `HttpSink` | غير مُنفَّذ / مقترح | batch/flush/buffer/consent/silent. |
| `FanOutSink` | غير مُنفَّذ / مقترح | بثّ متعدد. |
| `RemoteSink` | غير مُنفَّذ / مقترح | جذع مؤجَّل. |
| `analyticsProvider` | غير مُنفَّذ / مقترح | قرار `ANALYTICS_ENDPOINT`. |
| `analyticsConsentProvider` | غير مُنفَّذ / مقترح | يعرض الموافقة للمصارف. |
| `consent_store` | غير مُنفَّذ / مقترح | مفتاح `furn.analytics_consent`. |
| `consentControllerProvider` | غير مُنفَّذ / مقترح | يُبدِّل الموافقة. |
| `engine_purity_test.dart` | غير مُنفَّذ / مقترح | حارس الاستيراد الساكن. |
| `analytics_funnel_test.dart` | غير مُنفَّذ / مقترح | حارس القُمع/الكتالوج. |

---

## 8. الاختبارات المرجعية

**`test/analytics/engine_purity_test.dart`:** يحرس نقاء المحرك. يفحص `lib/domain_engine/**` بحثًا عن أي استيراد ممنوع للتحليلات، ويفشل عند وجود أيّه. تحقّق ساكن لا يشغّل المحرك (مناسب لغياب Flutter SDK).

**`test/analytics/analytics_funnel_test.dart`:** يحرس كتالوج الأحداث ونموذج القُمع، ويؤكّد **تسلسل الأحداث** (الترتيب) لا مجرّد وجودها: أن الأحداث الأساسية موجودة بأسمائها الثابتة (`snake_case`)، وأن `params` أولية وخالية من PII، وأن قِمع الثقة يتقدّم بالترتيب الصحيح ومقاديره قابلة للحساب:

- **Activation** = `plan_finalized / flow_started`.
- **قِمع الثقة (Trust funnel)** = أربع مراحل بالترتيب: `flow_started → plan_seeded → engaged → plan_finalized`، حيث **`engaged`** مرحلة مشتقّة (≥١ من: `item_pinned` / `item_rejected` / `item_swapped` / `budget_changed`).
- **`plan_restored`** = إشارة **العودة** فقط — **ليست بذرة جديدة**؛ عدّها ضمن `plan_seeded` أو مقام التفعيل **يضخّم القُمع كذبًا** ويجب استبعادها منه.
- **`merchant_click`** = إشارة نيّة الشراء (مدخل قُمع الإيراد).
- **`need_unmet`** = إشارة الطلب.

**القاعدة الملزِمة:** أي تغيير في الأحداث (اسم، `params`، إضافة/حذف) يجب أن **يُبقي `analytics_funnel_test` أخضر**، ويُرافَق بتحديث الكتالوج (`docs/analytics_events.md`) والاختبار في الالتزام نفسه. تغيير الأحداث دون ذلك = كسر عقد = يُرفَض.

---

## 9. قرارات مفتوحة تحتاج موافقة (Open decisions)

- **مُعرّف الجلسة المجهول:** آلية التوليد (UUID مجهول؟) وسياسة التدوير (rotation) — لكل جلسة؟ يوميًّا؟ عند سحب الموافقة؟ يجب ضمان عدم ربطه بأي هوية مستمرّة.
- **سحب الموافقة والمخزن المؤقّت:** بما أن البوابة **قبل التخزين لا قبل الإرسال**، ما مصير الأحداث المخزّنة سلفًا عند انتقال الموافقة إلى `denied` — تُمسح فورًا أم تُرسَل ضمن دفعتها؟ (توصية القياس: **مسح المخزن (flush-and-drop) فور الانتقال إلى `denied`** حسمًا للالتباس، ويحتاج توقيع الخصوصية).
- **استضافة `ANALYTICS_ENDPOINT`:** الجهة والمنطقة (region) — التزامًا بـ PDPL، هل تُشترط استضافة داخل المملكة؟ ومن يملك النقطة؟
- **أرقام التجميع:** تثبيت `batch=20` / `flush=15s` / `maxBuffer=200` أو ضبطها بعد قياس أولي.
- **لافتة الموافقة (Track 4):** كيف تستدعي `consentControllerProvider` بالضبط؟ نص اللافتة، توقيت الظهور، وسلوك «denied» مقابل «absent».
- **`RemoteSink`:** هل يُؤجَّل بالكامل الآن (جذع فقط) أم يُحدَّد عقده مبكرًا؟
- **قيم الـ enums والسِلال:** اعتماد القيم المقترحة في §3 (حدود السِلال الزمنية والعددية، ورموز `reason_code`) وتثبيتها في `docs/analytics_events.md`.
- **الاحتفاظ (retention):** مدّة الاحتفاظ بالأحداث على الوجهة وسياسة الحذف — خارج نطاق العميل لكنه شرط امتثال يجب حسمه قبل الإطلاق.

---

> **الخلاصة:** المستودع فارغ؛ كل ما سبق **مقترح — بانتظار الموافقة**. عند الاعتماد، تُشتق منه ملفات `docs/analytics_events.md` و`docs/telemetry_analytics.md` والتنفيذ تحت `lib/analytics/**` و`lib/features/consent/**` مع اختباريها المرجعيين.