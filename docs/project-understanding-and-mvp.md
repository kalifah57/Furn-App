# مراجعة الوثائق — فهم المشروع، الفجوات، ونطاق الـ MVP

> **⚠️ مرجع تأسيسي مُتجاوَز جزئيًا (2026-08).** يصف هذا المستند المشروع كـ«مستشار
> رقمي يقترح قطعًا وباقات» و«تطبيق جوال» — وكلاهما لم يعد التعريف المُعتمَد:
> المنتج **منصّة تخطيط تفاعلية على الويب**، **الخطة هي المنتج لا التوصية**
> ([`product_thesis.md`](product_thesis.md)). كما أن حزمة الوثائق الأصلية المذكورة
> أدناه (`product_requirements.md`, `architecture.md`, `ai_pipeline.md`,
> `json_schema.md`, `prompt_engineering.md`, `engineering_standards.md`) **ليست في
> هذا المستودع** — مرجع خارجي تاريخي. يُقرأ هذا المستند لسياق النشأة فقط.

> وثيقة مراجعة تسبق كتابة أي كود. مبنية على قراءة حزمة الوثائق (`final_all_in_one_pack`)
> التي تضم: `product_requirements.md`، `architecture.md`، `ai_pipeline.md`،
> `json_schema.md`، `recommendation_engine.md`، `catalog_strategy.md`،
> `prompt_engineering.md`، `engineering_standards.md`.

---

## 1) ملخص الفهم الكامل للمشروع

**الفكرة:** تطبيق جوال ذكي **Arabic-first** لتأثيث الشقق والغرف. المستخدم يصف الغرفة
بالصوت أو النص أو الصور، فيحلّل النظام المدخلات ويقترح **قطع أثاث فردية** و**باقات
متناسقة** ضمن الميزانية.

**الرؤية:** ليس متجرًا، بل **مستشار تأثيث رقمي** يجمع بين خبرة التصميم الداخلي
والانضباط المالي، ويعطي توصيات عملية قابلة للتنفيذ مع تبرير مختصر لكل توصية.

**الجمهور:** أفراد يؤثثون بميزانية محدودة، يريدون اقتراحات جاهزة ومتناسقة دون بحث
يدوي، بأولوية لتجربة عربية كاملة مع RTL.

**رحلة المستخدم الأساسية:** فتح التطبيق ← اختيار طريقة الإدخال (صوت/صور/يدوي) ←
وصف الغرفة والاحتياج والميزانية ← استخراج المعلومات ← أسئلة متابعة قصيرة عند نقص
البيانات ← ملخص الطلب ← توصيات فردية ← باقات متناسقة (٣ مستويات) ← حفظ/رجوع.

**المعمارية (Clean Architecture + Feature-first):**
- **Presentation:** الشاشات، Widgets مشتركة، إدارة الحالة، حالات التحميل/الخطأ.
- **Domain:** الكيانات، use cases، **قواعد العمل**، **واجهات المستودعات**.
- **Data:** Firebase data sources، Remote AI sources، Models + mappers، Repository impl.
- **AI Layer:** Speech-to-text، Vision analysis، Prompt builder، Structured response
  parser، Confidence scoring — كلها **abstractions**.

**المكدس التقني:** Flutter · Firebase (Auth / Firestore / Storage) · Cloud Functions
لاحقًا للطلبات الحساسة · مزوّد AI **قابل للاستبدال** (Gemini/OpenAI/غيرهما) ·
State: Riverpod أو Bloc · Routing: GoRouter · DI عبر providers.

**مبدأ الذكاء الاصطناعي الجوهري (فصل صارم):** دور الـ LLM هو **فهم النية واستخراج
بيانات منظمة فقط** (مطابِقة لـ `json_schema.md`). أما **قواعد العمل + محرّك التوصيات +
توزيع الميزانية** فهي **منطق تطبيقي حتمي (deterministic) بلغة Dart**، قابل للاختبار
ومستقل عن الـ AI.

**خط الأنابيب (AI Pipeline):**
`Voice/Text/Images → STT/OCR/Vision → Input Normalization → Prompt Builder → LLM →
Structured JSON → Business Rules Engine → Recommendation Engine → Budget Allocator →
UI`.

**محرّك التوصيات (منطق حتمي):** مراحل = تصفية غير الصالح ← توافق الغرفة ← توافق
الميزانية ← مطابقة النمط ← التوفر ← احتساب الدرجة ← ترتيب ← بناء الباقات ← تحذيرات
وتنازلات. ونموذج الدرجة:

```
Recommendation Score =
  Room Compatibility (35%) + Budget Fit (30%) + Style Match (20%)
  + Popularity/Quality (10%) + User Preferences (5%)
```

الأوزان قابلة للتعديل حسب نوع الغرفة. مثال توزيع ميزانية غرفة نوم اقتصادية:
السرير 40% · الكنب/الكرسي 20% · التخزين 15% · الإضاءة 10% · السجادة والإضافات 15%.

**الباقات:** `budget` (أقل تكلفة، الضروري فقط) · `balanced` (توازن شكل/سعر) ·
`premium` (أعلى جودة، لا تُعرض فوق الميزانية إلا بتحذير). كل باقة تحمل: سبب الاختيار،
أبرز تنازل، أبرز ميزة.

**الكتالوج:** التوصيات مرتبطة بجودة الكتالوج. للـ MVP: **Mock/Internal Catalog صغير
(٥٠–٢٠٠ منتج)**. بنية المنتج: `product_id, title, category, subcategory, style_tags,
color_tags, material_tags, width_cm, depth_cm, height_cm, price, currency, brand,
supplier, availability_status, rating_optional, room_suitability_tags, image_url,
product_url`.

**هندسة الـ Prompt:** الـ prompt عقد تشغيلي (System / User / Developer / Few-shot).
مخرجات JSON منظمة فقط، تحديد `missing_information` و`confidence_score`، احترام
الوحدات والعملة، Versioning للـ prompts، ومعالجة JSON غير الصالح (retry → repair →
fallback)، وضبط التكلفة (عدم استدعاء الـ LLM عند كفاية الإدخال اليدوي).

**معايير الهندسة:** كود واضح، عزل الـ features، عدم خلط UI بمنطق العمل، نموذج أخطاء
موحّد، Logging منظم بلا بيانات حساسة، اختبارات (Unit/Widget/Integration)، Git flow
(main + feature branches + PR + review)، CI/CD (lint + tests + build)، مفاتيح خارج
الكود، توثيق ADRs وإصدارات الـ schema/prompt.

---

## 2) الفجوات والقرارات غير المحسومة

| # | الفجوة / القرار | الحالة في الوثائق | التوصية المقترحة |
|---|---|---|---|
| G1 | **State management** | «Riverpod أو Bloc» — غير محسوم | **Riverpod** (أقل boilerplate، `AsyncValue` يطابق initial/loading/success/error، ويصلح كـ DI) |
| G2 | **مصدر الكتالوج للـ MVP** | Mock أو Internal، وتخزينه «Firestore أو JSON ثابت» | **Static JSON asset** أولًا (أبسط، حتمي للاختبار)، ثم Firestore لاحقًا |
| G3 | **ربط Firebase في الـ MVP** | مطلوب ضمن المكدس، لكن المطلوب mock-first | **تجريد خلف repositories + mock data sources**، وتأجيل الربط الحقيقي للمرحلة ٢ |
| G4 | **مزوّد الـ AI** | Gemini/OpenAI «أو غيرهما» — غير محدد | تجريد `LlmExtractionService` مع **Mock** افتراضي؛ اختيار المزوّد يُؤجَّل |
| G5 | **STT / Vision في الـ MVP** | ضمن الرحلة، لكن mock-first | بناء الشاشات + **معالِجات وهمية**؛ لا استدعاءات حقيقية الآن |
| G6 | **المصادقة (Auth)** | «تسجيل/دخول بسيط» ضمن الـ MVP | تجريد `AuthRepository`؛ استخدام **Anonymous/Mock auth** أولًا لتقليل الاعتماد المبكر |
| G7 | **عتبة `confidence_score`** لتشغيل أسئلة المتابعة | غير محدّدة رقميًا | قاعدة عمل قابلة للضبط (مثلًا < 0.6) — تُحدَّد في الـ Business Rules |
| G8 | **توزيع الميزانية لأنواع غرف أخرى** | مثال واحد فقط (غرفة نوم) | تعريف نِسب افتراضية لكل `room_type` في المحرّك |
| G9 | **تعدّد اللغات** | Arabic-first + `locale: "ar-SA"` ثابت | العربية فقط في الـ MVP، مع بنية i18n جاهزة للتوسّع |
| G10 | **تسمية الباقات** | PRD: «اقتصادي/متوازن/أفضل» — المحرّك/الschema: `budget/balanced/premium` | توحيدها على `budget/balanced/premium` (كما في الـ schema) |
| G11 | **٤ وثائق مذكورة وغير موجودة** كملفات مستقلة | `vision_architecture.md`، `product_catalog_erd.md`، `telemetry_analytics.md`، `deployment.md` غير ظاهرة في الحزمة؛ مواضيعها مغطّاة جزئيًا داخل وثائق أخرى | تأكيد: هل تُعتمد التغطية الحالية، أم تُكتب كوثائق مستقلة؟ |
| G12 | **لا يوجد مجلد `/docs` في المستودع** | المستودع فارغ (README فقط)؛ الوثائق مصدرها الـ PDF | أستطيع إعادة بناء الـ ٨ وثائق المصدر داخل `/docs` عند الطلب |
| G13 | **توتر بسيط:** «دعم صوت/صور» مقابل «mock-first بلا APIs» | كلاهما مطلوب | حلّه: بناء واجهات الصوت/الصور مع معالجة **وهمية** في الـ MVP |

---

## 3) نطاق الـ MVP المقترح (واضح ومختصر)

**داخل الـ MVP (مع mock data ومنطق حتمي، بلا APIs حقيقية):**
1. Onboarding عربي + RTL كامل.
2. شاشة اختيار طريقة الإدخال (صوت / صور / يدوي).
3. نموذج **إدخال يدوي منظم** (الغرفة، الأبعاد، الميزانية، الأساسي/الاختياري، النمط) — المسار الأساسي.
4. شاشتا **الصوت والصور** بواجهة كاملة لكن بمعالجة **وهمية** (mock STT / mock Vision).
5. **تحليل أولي** ينتج نموذجًا منظّمًا مطابقًا لـ `json_schema.md` (عبر Mock LLM service).
6. **أسئلة متابعة قصيرة** عند نقص البيانات / انخفاض الثقة.
7. **صفحة ملخص الطلب**.
8. **توصيات فردية مرتّبة** + سبب مختصر لكل توصية.
9. **٣ باقات** (`budget/balanced/premium`) + توزيع ميزانية مبسّط + تحذيرات/تنازلات.
10. **حفظ المشاريع والرجوع إليها** (تخزين محلي/وهمي في الـ MVP).
11. **محرّك توصيات + قواعد عمل حتمية** قابلة للاختبار بالكامل (Unit tests).

**خارج الـ MVP:** Marketplace كامل · ربط مباشر بمتاجر · لوحة خبراء · عروض 3D ·
تسعير ديناميكي · توصيات مبنية على تاريخ شراء واسع · STT/Vision/LLM حقيقية · مراجعة بشرية.

**تحسينات مقترحة على الـ MVP لجعله أسرع تنفيذًا:**
- جعل **الإدخال اليدوي المنظم** هو المسار الأساسي المضمون، والصوت/الصور طبقة تجريبية
  فوقه (يقلّل المخاطرة ويطابق «ضبط التكلفة» في `prompt_engineering.md`).
- **Static JSON catalog** بـ ٢٠–٣٠ منتجًا للـ MVP (كافٍ لإثبات المحرّك والباقات).
- **Mock LLM** يُرجِع JSON مطابقًا للـ schema من أمثلة معدّة مسبقًا → تدفّق كامل بلا تكلفة/شبكة.

---

## 4) الـ ADR
تفاصيل القرارات المعمارية التسعة (folder structure, state management, routing, DI,
repository pattern, AI service abstraction, Firebase integration, testing strategy,
deployment approach) في: **`docs/adr/0001-mvp-architecture-decisions.md`**.

> **لا يُكتب أي كود قبل موافقتك.** بعد الموافقة (وحسم G1–G3 تحديدًا) يبدأ التنفيذ على
> مراحل صغيرة، مع تلخيص ما تمّ وما تبقّى بعد كل مرحلة.
