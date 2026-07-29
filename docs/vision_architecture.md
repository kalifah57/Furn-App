# vision_architecture.md — معمارية تحليل الرؤية (الصور)

> يصف كيف يعالج النظام **صور الغرفة**. متوافق مع الكود الحالي: العقد
> `lib/ai/contracts/vision_analysis_service.dart` والتنفيذ الوهمي
> `lib/ai/mock/mock_vision_analysis_service.dart` ضمن **طبقة الـ AI** (`lib/ai`).

## 1) المبدأ
الرؤية — كالـ LLM تمامًا — **تستخرج إشارات منظمة فقط**، ولا تقرّر أي توصية. مخرجاتها
تُحقن في الـ prompt كـ `[Vision Signals]` وتغذّي الاستخراج، بينما تبقى قرارات التوصية في
`domain_engine` الحتمي.

## 2) الموقع في الطبقات
- **العقد (Contract):** `VisionAnalysisService.analyze(List<String> imageRefs) → Result<String>`.
- **التنفيذ الحالي:** `MockVisionAnalysisService` (mock-first) يعيد ملخّصًا نصيًا تمثيليًا.
- **الحقن (DI):** `visionAnalysisServiceProvider` في `lib/core/di/providers.dart` — يُستبدل
  بتنفيذ حقيقي في المرحلة ٢ عبر `override` دون لمس بقية الطبقات.

الرؤية **لا تعتمد على** `domain_engine`، و`domain_engine` **لا يعتمد على** الرؤية —
فصلٌ صارم مؤكَّد في الكود.

## 3) تدفّق البيانات

```mermaid
flowchart TD
  IMG[صور الغرفة (refs)] --> VS[VisionAnalysisService.analyze]
  VS --> SUM[ملخّص إشارات نصّي]
  SUM --> NI[NormalizedInput.visionSummary]
  NI --> PB[PromptBuilder → [Vision Signals]]
  PB --> LLM[LlmExtractionService]
  LLM --> JSON[Structured JSON (json_schema.md)]
  JSON --> BR[Business Rules Engine]
  BR --> RE[Recommendation Engine]
```

## 4) المسؤوليات (ماذا تُخرج الرؤية)
- تلميحات **نوع الغرفة** (نوم/معيشة/مجلس).
- **تقدير أبعاد** تقريبي عند غياب الأبعاد النصّية.
- **قطع موجودة** في الغرفة (لتجنّب اقتراح مكرّر).
- **ألوان/خامات/إضاءة** سائدة (تدعم `style_match`).
- المخرج في الـ MVP: ملخّص نصّي. مستقبلًا: نموذج `VisionSignals` منظّم (عناصر مكتشفة،
  أبعاد مقدّرة، ثقة لكل إشارة).

## 5) Mock مقابل Real (التبديل)
| البُعد | MVP (الآن) | المرحلة ٢ (لاحقًا) |
|---|---|---|
| التنفيذ | `MockVisionAnalysisService` | مزوّد حقيقي (نموذج متعدد الوسائط / OCR + كشف) |
| العقد | ثابت لا يتغيّر | **نفس** `VisionAnalysisService` |
| التبديل | افتراضي في الـ provider | عبر DI/Feature Flag |
| الشبكة | لا شيء | استدعاء خارجي مُدار التكلفة |

## 6) الثقة والـ Fallback
- رؤية منخفضة الثقة → لا تُملأ الأبعاد تخمينًا؛ تُوضَع في `missing_information`.
- قواعد العمل قد تضبط `next_actions.ask_for_images = true` لطلب صور أوضح.
- fallback: المضي بالإدخال اليدوي/النصّي إن تعذّرت الرؤية.

## 7) الأمن والخصوصية
- الصور قد تكشف مساحة خاصة: **لا تُسجَّل محتوياتها** في اللوجز (مراجع فقط).
- التحقق من صلاحيات الوصول للملفات (engineering_standards.md).
- التخزين الفعلي للصور (Firebase Storage) **مؤجّل** — خلف تجريد data source.

## 8) ضبط التكلفة (prompt_engineering.md)
- **لا تُستدعى الرؤية** إذا كفى الإدخال اليدوي المنظّم.
- لا تُرسَل الصور إن لم تكن ضرورية.

## 9) قابلية الاختبار
- التنفيذ الوهمي **حتمي** → اختبارات مستقرة.
- تُختبَر خطوة حقن `visionSummary` في `NormalizedInput` ثم في `[Vision Signals]`
  ضمن اختبارات `PromptBuilder`/مسار التحليل.
