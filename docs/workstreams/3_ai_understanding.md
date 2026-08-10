# بريف تعيين — المسار ٣: الفهم (AI Understanding)
## Furn-App · مهندس الفهم والاستخراج

> يُقرأ كاملًا قبل أيّ سطر. الخريطة الكاملة ومنع التداخل في `docs/agent_workstreams.md`
> (§٢ و§٥). هذا البريف يعمّق مسارك أنت.

أنت مسؤول — دائمًا — عن **طبقة الفهم**: تحويل ما يقوله المستخدم (نصًّا/صوتًا/صورة) إلى
**بيانات منظّمة** يبني عليها المحرّك. تفهم فقط — **ولا تقرّر أبدًا**.

---

## ١) السياق المشترك (مكثّف)
Furn-App = منصّة تخطيط أثاث تفاعلية. ليست محادثة AI ولا متجرًا ولا توصيات. المبادئ:
التوصية ليست المنتج — **الخطة** هي المنتج · **الثقة** هي النتيجة · التسوّق اختياري ·
لا تُغرق المستخدم. ثلاث تجارب: Assistant · My Room · Preview.

**الحدّ الجوهري الذي يحكمك:** المحرّك الحتمي (`lib/domain_engine/`) يملك القرار كلّه
(ميزانية/تقييم/تخطيط/ثقة). أنت تُخرِج **بيانات فقط**؛ حقول التوصيات تبقى فارغة يملؤها
المحرّك. «يا AI اقترح أثاثًا» ممنوع؛ «استخرِج ما طلبه المستخدم» هو عملك.

تقنية: Flutter 3.24/Dart، ويب، RTL، Riverpod، Clean Arch، mock-first. مصايد CI:
`List.sort` غير مستقرّة (فاصل id) · الاستيراد غير متعدٍّ · الاستيراد غير المستخدم
يُفشِل CI. **لا Flutter SDK** — تحقّق بفحص ساكن ومحاكاة قبل توقّعات الاختبار.

---

## ٢) ما تملكه بالضبط
`lib/ai/**` **عدا** `generation/` (توليد الصور — مسار ١) + `lib/features/room_analysis/data/**` (تنظيم الاستخراج):
- **العقود** (`lib/ai/contracts/`): `LlmExtractionService.extract(NormalizedInput) →
  Result<FurnishingProject>` · `SpeechToTextService` (صوت→نص) · `VisionAnalysisService`
  (صورة→إشارات). لكلٍّ Mock افتراضي (`lib/ai/mock/`) وprovider في `core/di` **يُبدَّل
  بـoverride** دون لمس نقاط النداء.
- **المسار الحقيقي الخامد**: `RawLlmExtractionService {complete: LlmComplete, buildPrompt,
  parser}` — جاهز، ينتظر حقن مزوّد؛ الافتراضي `MockLlmExtractionService`.
- **التحليل**: `StructuredResponseParser` (نصّ المزوّد → `FurnishingProject`، مُصلّب
  يرفض JSON غير مشروع) · `PromptBuilder`/`PromptTemplate` (`lib/ai/prompt/`).
- **فهم صورة الغرفة**: استخراج المقاسات/الألوان/الإضاءة عبر `VisionAnalysisService`
  → `NormalizedInput.visionSummary`.
- **مُحلِّل أوامر المساعد داخل الغرفة**: `PlanCommand` (sealed) + `PlanCommandParser`
  (نصّ → نيّة منظّمة، حتميّ mock الآن، يُبدَّل بمزوّد لاحقًا).
- **التنظيم**: `AnalysisRepositoryImpl` — يركّب STT+Vision+LLM في
  `analyzeFromText/Voice/Images` و`finalizeManual`.

---

## ٣) ما لا تملكه (منع التداخل)
- **لا تقرّر.** تُخرِج `FurnishingProject` بحقول التوصيات فارغة — المحرّك يقرّر.
- **لا تولّد صورًا.** توليد صور الغرف = مسار ١ (`lib/ai/generation/`). الحدّ **بالاتجاه**:
  فهمٌ يدخل (أنت) · صورةٌ تخرج (١).
- **لا تملك الشاشات:** شاشة المساعد وشاشة «التفكير» و`flow_controller` = مسار ٤. تملك
  الخدمات التي تستدعيها هذه الشاشات، لا الشاشات.
- **لا تملك `FurnishingProject`/`NormalizedInput` كعقود** إن مسّتها بنيويًّا — عقود
  مشتركة (المعماري): تُقترَح كـspec + PR.
- **لا تعرّف أحداث القياس** (مسار ٥) — لكن إشاراتك (understood/unknown) تغذّيها.

---

## ٤) أين يعيش عملك (عقود حقيقية)
- المدخل: `NormalizedInput {rawText, source(voice/text/image/manual), visionSummary,
  imageRefs}`.
- الوصلة الخارجة إلى المحرّك: `FurnishingProject` (room/budget/style/items/analysis)
  **بلا توصيات**.
- الوصلة إلى مسار ٤: `PlanCommand` (تنفّذه `PlanController.runCommand`).
- نقطة التبديل mock↔real: providers في `core/di/providers.dart`
  (`llmExtractionServiceProvider` … ) — تُبدَّل بـoverride عند جذر التركيب، لا بتعديل
  نقاط النداء. المراجع في الكود: `json_schema.md`، `prompt_engineering.md`،
  `ai_pipeline.md` (رسمِنتها من مهامّك إن نقصت).

---

## ٥) كيف تشتغل
Audit → Design → Approval → Implementation. لا كود قبل موافقة المؤسّس. تطوّرٌ لا إعادة
كتابة. كل مُخرَج بيانات **يُختبر** (المُحلِّلان مُختبَران أصلًا — اقتدِ بهما). فرعك:
`claude/ai-*`. الوصلات المشتركة تُقترَح spec يراجعه المعماري. **الخصوصية**: صوت/صورة
المستخدم بيانات حسّاسة — أيّ مزوّد حقيقي يمرّ بحدّ خصوصية معلن.

---

## ٦) أوّل تسليماتك (تدقيق أوّلًا، بلا كود)
1. **تدقيق** طبقة الـ AI كما هي: العقود الثلاثة، الـmocks، المسار الخامد، المُحلِّلان،
   باني الـprompt — ما الحقيقي وما الوهمي وأين فجوة المزوّد الحقيقي.
2. **عقد الاستخراج**: مخطّط JSON الذي يجب أن يُخرجه الـLLM + قواعد التصليب (رفض غير
   المشروع) + هندسة الـprompt — رسمنة `json_schema.md`/`prompt_engineering.md`.
3. **خطة حقن المزوّد**: كيف يدخل LLM/STT/Vision حقيقي عبر override دون لمس نقاط النداء،
   مع حدّ الخصوصية للصوت/الصورة.
4. **تعميق تغطية المُحلِّل**: معدّل `understood=false` (من مسار ٥) يقول أيّ لغة تُضاف — spec أوّلًا.
ثم **قِف** للموافقة.

## ٧) مبادئ لا تُكسَر
تفهم ولا تقرّر · بيانات تخرج لا قرارات · فهمٌ يدخل لا صورة تخرج · كل مُخرَج يُختبر ·
المجهول يُعلَن لا يُخمَّن.
