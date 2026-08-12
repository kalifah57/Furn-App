# G5 — تقرير معدّل الفهم (understood-rate) لأوامر المساعد

> **مُسلَّم مبكرًا لمسار ٣ (الفهم):** يغذّي **U2** (توسيع مُفردات مُحلِّل الأوامر). الصيغة أدناه ثابتة وجاهزة للاستهلاك الآن.
> **الملكية:** المسار ٥ يملك تعريف الحدث والتقرير؛ نقطة النداء لمسار ٣/٤. تلاحظ ولا تغيّر · بلا PII.

---

## 0. المصدر والدلالة

الحدث `assistant_command { intent, understood }` (`lib/analytics/analytics.dart`)، يُطلَق من `plan_controller.dart:225`:

```dart
AssistantCommand(intent: cmd.intent, understood: cmd is! UnknownCommand)
```

- `intent` ∈ `set_budget | nudge_budget | add | remove | finalize | unknown`.
- `understood == false` **يكافئ** أمرًا لم يفهمه المُحلِّل (`UnknownCommand`).
- **`understood=false` هو الإشارة:** معدّله واتجاهه يكشفان **حجم اللغة التي لم نعلّمها المُحلِّل بعد** — وهو ما يوجّه U2 بأثر حقيقيّ لا بالحدس.

---

## 1. حدّ الخصوصية (مهمّ لمسار ٣)

الحدث **لا يحمل نصّ الأمر الخام** (قد يحوي PII) — فقط النيّة المُعدَّلة ونجاح الفهم. لذلك:

- القياس يعطي **المعدّل + الاتجاه + التوزيع بالنيّة** (آمن، مُجمَّع).
- القياس **لا يعطي الجُمَل الفاشلة** بعينها. جمع الأمثلة لتوسيع المفردات يبقى في **مجموعة اختبار مسار ٣ الخاصّة** (منهج D-style: حالات ← دقّة ← معايرة)، لا في قياس الإنتاج.
- هذا نفس حدّ الخصوصية المطبَّق على `need_unmet` (لا نصّ خام في التحليلات).

**كيف يغذّي U2 عمليًّا:** معدّل الفهم في الإنتاج = **خطّ الأساس والهدف** لحلقة U2؛ ارتفاع `not_understood_rate` أو تغيّر توزيع النيّات = **إشارة أن لغة جديدة ظهرت** ⇒ وسّع الـ corpus وأعِد المعايرة. القياس يقول «كم» و«أين تتركّز»، والـ corpus يقول «ماذا» بالضبط.

---

## 2. التقرير المحلّي الآن (`AssistantUnderstoodReport`)

`lib/analytics/assistant_understood_report.dart` — نقيّ، يُحسب من `DebugAnalytics.events`:

```dart
final r = AssistantUnderstoodReport.fromEvents((debug as DebugAnalytics).events);
debugPrint(r.format());
```

مخرج `format()`:

```
assistant commands: 5
understood: 3 (60.0%)   not understood: 2 (40.0%)
by intent: unknown=2 add=1 remove=1 set_budget=1
```

- `understoodRate` = `understood / total`.
- `intentsRanked`: تنازليًّا بالعدد، فاصل تعادل بالاسم (ترتيب مستقرّ — مصيدة CI).
- يغطّيه `test/analytics/assistant_understood_report_test.dart`.

---

## 3. الاستعلام الحيّ (عند فتح 🔒F4)

المخطّط: `events(name, session_id, at, params JSONB)`.

```sql
-- معدّل الفهم الإجماليّ خلال نافذة:
SELECT
  COUNT(*)                                                        AS total,
  COUNT(*) FILTER (WHERE (params->>'understood')::boolean)        AS understood,
  round(
    COUNT(*) FILTER (WHERE (params->>'understood')::boolean)::numeric
    / NULLIF(COUNT(*), 0), 3)                                     AS understood_rate
FROM events
WHERE name = 'assistant_command' AND at >= NOW() - INTERVAL '7 days';

-- التوزيع بالنيّة + معدّل الفهم لكل نيّة (لتحديد أين تتركّز الفجوة):
SELECT
  params->>'intent'                                              AS intent,
  COUNT(*)                                                       AS commands,
  round(
    COUNT(*) FILTER (WHERE (params->>'understood')::boolean)::numeric
    / NULLIF(COUNT(*), 0), 3)                                    AS understood_rate
FROM events
WHERE name = 'assistant_command' AND at >= NOW() - INTERVAL '7 days'
GROUP BY params->>'intent'
ORDER BY commands DESC, intent ASC;
```

---

## 4. التقرير الدوريّ (الصيغة المُسلَّمة لمسار ٣)

- **الوتيرة:** أسبوعيّ (يوازي حلقة معايرة U2).
- **الحقول:** `total`, `understood_rate`, `not_understood_rate`, و`by_intent[{intent, commands, understood_rate}]`, مع **الاتجاه** مقابل الأسبوع السابق (Δ understood_rate).
- **التنبيه:** قفزة في `not_understood_rate` فوق عتبة (مثلًا +5 نقاط) = لغة جديدة ⇒ إشعار لمسار ٣.
- **القراءة:** `understood_rate` يرتفع مع نضج U2؛ النيّات ذات الحجم العالي والفهم المنخفض = أولوية التوسيع.

> **قيد التوليد الآن:** التقرير يُولَّد محليًّا على `DebugAnalytics` (رهن فجوة GAP-4: إخضاع Debug للموافقة)، وحيًّا عند F4. لا يُكسر `analytics_funnel_test` (لا تغيير في الأحداث).
