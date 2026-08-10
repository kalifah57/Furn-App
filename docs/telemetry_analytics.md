# telemetry_analytics.md — القياس والتحليلات

> **⚠️ مُتجاوَز (2026-08).** مقياس النجاح في هذه الوثيقة (`recommendations_viewed`
> و`project_saved / recommendations_viewed`) يعكس هوية قديمة تجعل التوصيات هي
> المنتج. **المصدر الحيّ للقياس هو [`analytics_events.md`](analytics_events.md)**،
> ونجمُه الشمالي **`plan_finalized / flow_started`** (خطة يثق بها المستخدم)،
> متوافقًا مع [`product_thesis.md`](product_thesis.md). تُبقى هذه الوثيقة كمرجع
> تاريخي لتصنيف الأحداث فقط.

> تصميم القياس (Telemetry) والتحليلات بما يتوافق مع **مؤشرات النجاح** (PRD) ومعايير
> **التسجيل** (engineering_standards.md). **التنفيذ الحقيقي للتحليلات خارج نطاق المرحلة
> الحالية** — هذه الوثيقة تصميم + موضع تجريد جاهز للتفعيل لاحقًا.

## 1) المبدأ
قياس **مسار المستخدم** وجودة النتائج، **دون تسجيل بيانات حساسة**. كل حدث مجهّل
وقابل للتجميع.

## 2) ربط مؤشرات النجاح بالأحداث (PRD)
| المؤشر | الحدث/الأحداث |
|---|---|
| إكمال رحلة الإدخال→النتائج | `input_submitted` → `recommendations_viewed` |
| نسبة حفظ المشاريع | `project_saved` / `recommendations_viewed` |
| معدل الرجوع | `app_opened` (جلسات متكررة) |
| رضا المستخدم عن وضوح التوصيات | `recommendation_feedback` (لاحقًا) |
| دقة استخراج الأبعاد/الميزانية | `extraction_completed.confidence` + تصحيحات المتابعة |

## 3) تصنيف الأحداث (Event Taxonomy)
```
app_opened
onboarding_started
input_method_selected { source: voice|image|manual }
input_submitted        { source }
extraction_completed   { confidence, missing_count }
followup_shown         { missing_count }
followup_answered       { fields_filled }
summary_viewed
recommendations_viewed { individual_count, bundle_count }
bundle_viewed          { tier }
project_saved
error_occurred         { type: network|validation|ai_parsing|unknown }
```
> ملاحظة: لا يحمل أي حدث نصّ المستخدم الخام، ولا صورًا، ولا مفاتيح.

## 4) المعمارية (موضع التجريد)
- واجهة مقترحة `AnalyticsService` (كتجريد طبقة الـ AI): `logEvent(name, params)`.
- **الـ MVP:** تنفيذ **NoOp/Console** فقط (لا مزوّد حقيقي — التزامًا بقيود المرحلة).
- **الحقن:** `analyticsServiceProvider` (يُضاف عند التفعيل) قابل للاستبدال عبر DI/Feature Flag.
- **مواضع الإطلاق:** انتقالات `FurnishingFlowController`
  (`lib/features/room_input/presentation/flow_controller.dart`) والشاشات الأساسية.

```mermaid
flowchart LR
  UI[الشاشات] --> AS[AnalyticsService (abstract)]
  FC[FlowController] --> AS
  AS -->|MVP| NOOP[NoOp / Console]
  AS -.->|لاحقًا| PROV[مزوّد حقيقي]
  ERR[Failure model] --> LOG[Logger منظّم]
```

## 5) التسجيل (Logging) — engineering_standards.md
- تسجيل **منظّم** عبر مسار موحّد؛ التمييز بين
  `network_errors` / `validation_errors` / `ai_parsing_errors` (يقابل `sealed Failure`
  في `lib/core/errors/failure.dart`).
- **عدم تسجيل البيانات الحساسة** (لا PII، لا صور، لا `cause` يحوي محتوى المستخدم في
  اللوجز العامة).
- تتبّع الإخفاقات في: استخراج الـ AI، رفع الصور، المصادقة.

## 6) الخصوصية
- مجهولية افتراضية، بلا PII.
- التحليلات الحقيقية **opt-in** عند تفعيلها لاحقًا.
- مقاييس مجمّعة لا فردية حسّاسة.

## 7) قابلية الاختبار
- تنفيذ NoOp/Fake يجعل الاختبارات لا تُحدث آثارًا جانبية.
- يمكن التحقق من **إطلاق الأحداث الصحيحة** عبر Fake `AnalyticsService` في اختبارات
  الـ controller (عند إضافته).

## 8) خارج النطاق الآن
- أي SDK تحليلات حقيقي (Firebase Analytics/غيره) — يُضاف في مرحلة لاحقة خلف
  `AnalyticsService` دون تغيير منطق الأعمال.
