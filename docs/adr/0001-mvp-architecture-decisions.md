# ADR-0001 — قرارات معمارية للـ MVP (تطبيق التأثيث الذكي)

- **الحالة:** مقترح (بانتظار الموافقة قبل التنفيذ)
- **التاريخ:** 2026-07-29
- **السياق:** تطبيق Flutter عربي-أولًا لتأثيث الغرف، mock-first، مع فصل صارم بين
  استخراج الـ AI وقواعد العمل ومحرّك التوصيات. هذا الـ ADR يحسم التسع نقاط المطلوبة.

المصطلحات التقنية بالإنجليزية مقصودة (للاتساق مع كود Flutter/Dart وحزمة الوثائق).

---

## 1. Folder Structure — feature-first + طبقات داخلية

نوفّق بين «الطبقات الأفقية» (Presentation/Domain/Data/AI) و«التقسيم حسب feature»
الوارديْن في `architecture.md` عبر **feature-first مع طبقات داخل كل feature**:

```
lib/
  app/                      # نقطة الدخول، التهيئة، الـ theme، الـ router
  core/
    config/                 # environment, flavors, firebase_options
    constants/
    errors/                 # نموذج الأخطاء الموحّد + Failure/Result
    theme/                  # RTL, الألوان, الخطوط العربية
    utils/                  # units normalization, formatters
    router/                 # GoRouter setup + routes
  features/
    auth/            { presentation/ domain/ data/ }
    onboarding/      { presentation/ domain/ data/ }
    room_input/      { presentation/ domain/ data/ }   # voice/image/manual
    room_analysis/   { presentation/ domain/ data/ }   # summary + missing info
    recommendations/ { presentation/ domain/ data/ }   # items + bundles
    saved_projects/  { presentation/ domain/ data/ }
    profile/         { presentation/ domain/ data/ }
  ai/                       # AI Layer (abstractions + mock impls)
    contracts/              # SpeechToText, VisionAnalysis, LlmExtraction, ...
    prompt/                 # PromptBuilder + templates + versioning
    parsing/                # StructuredResponseParser + validation
    mock/                   # تنفيذات وهمية للـ MVP
  domain_engine/            # منطق حتمي مشترك، مستقل عن الـ AI و الـ UI
    business_rules/         # validation, essential/optional, conflicts
    recommendation/         # scoring, ranking, filtering
    budget/                 # budget allocation per room_type
  shared/
    models/                 # نماذج مطابقة لـ json_schema.md
    widgets/                # مكوّنات RTL مشتركة
    services/               # logging, error mapping
```

- **لكل feature:** `presentation` (screens/widgets/controllers) تعتمد على `domain`
  فقط؛ `domain` (entities + repository interfaces + use cases)؛ `data` (DTOs +
  mappers + data sources + repository impl).
- **`domain_engine/`** يعزل **قواعد العمل + محرّك التوصيات + توزيع الميزانية** كوحدات
  Dart نقية (لا Flutter، لا Firebase، لا AI) → قابلة للاختبار مباشرة.

## 2. State Management — Riverpod

- **القرار:** `flutter_riverpod` (+ `riverpod_generator` اختياريًا). حالة **منفصلة لكل
  feature** عبر `Notifier` / `AsyncNotifier`.
- **الحالات غير المتزامنة** تُمثَّل بـ `AsyncValue` = `initial/loading/success/error`
  تمامًا كما في `architecture.md`.
- **السبب:** أقل boilerplate من Bloc، اختبار أسهل، ويقوم أيضًا بدور الـ DI (نظام واحد).
- **بديل مرفوض للآن:** Bloc (صالح، لكنه أثقل ويضيف طبقة events/states غير لازمة للـ MVP).

## 3. Routing — GoRouter

- `GoRouter` مركزي في `core/router/app_router.dart`، مسارات مُسمّاة، redirect/guards
  للمصادقة، جاهز لـ deep-linking والتوسّع. الـ router يُوفَّر عبر provider.

## 4. Dependency Injection — providers (Riverpod)

- **القرار:** الـ DI عبر **Riverpod providers** فقط (لا get_it/injectable) لتفادي
  نظامَي DI. الـ providers تكشف: repositories، data sources، AI services، use cases،
  ومحرّكات `domain_engine`.
- **التبديل السهل (mock ↔ real):** عبر **provider overrides** — الـ MVP يربط
  الـ abstractions بتنفيذات mock، ولاحقًا نستبدلها بتنفيذات حقيقية دون لمس الـ UI.

## 5. Repository Pattern

- **Domain** يعرّف واجهات مجرّدة: `AuthRepository`، `RoomInputRepository`،
  `CatalogRepository`، `RecommendationRepository`، `ProjectRepository`.
- **Data** يوفّر التنفيذ مدعومًا بـ data sources (Firebase / AI / mock).
- **Use cases** في الـ domain تنسّق بين المستودعات؛ الـ presentation لا تعرف إلا
  الـ domain (عبر providers).
- **الأخطاء:** ترجع `Result<T, Failure>` (نموذج الأخطاء الموحّد) بدل رمي استثناءات خام.
- **MVP:** كل مستودع مدعوم بـ **mock data source** (in-memory / JSON asset).

## 6. AI Service Abstraction — فصل الاستخراج عن القرار

عقود في `ai/contracts/` بتنفيذات mock للـ MVP:
- `SpeechToTextService` — صوت → نص (Mock الآن).
- `VisionAnalysisService` — صور → إشارات منظمة (Mock الآن).
- `LlmExtractionService` — نص مُطبَّع + schema → **`RoomAnalysis` منظّم فقط** (Mock الآن).
- `PromptBuilder` — يبني قالب `[System/Rules/Schema/User Input/Vision/Output]` **مع
  versioning** (`prompt_name, version, last_updated, supported_schema_version`).
- `StructuredResponseParser` — JSON → نماذج مع تحقّق + `missing_information` +
  `confidence_score`، ومنطق `retry → repair → fallback` للـ JSON غير الصالح.

> **قاعدة جوهرية:** الـ AI **يستخرج بيانات منظمة فقط** ولا يقرّر التوصيات. اختيار
> القطع/الترتيب/توزيع الميزانية/الباقات كلها في `domain_engine` (حتمية وقابلة للاختبار).

## 7. Firebase Integration — مجرّد و mock-first

- التكامل خلف `*_data_source` + repositories؛ **لا استدعاءات Firebase حقيقية في
  المسار الأساسي للـ MVP** (تنفيذات mock/in-memory).
- الحزم تُضاف والـ wiring يبقى خلف `FirebaseDataSource` قابل للاستبدال.
- **Auth:** `AuthRepository` مجرّد؛ MVP بـ Anonymous/Mock auth.
- **Firestore** (المشاريع/الكتالوج لاحقًا) و**Storage** (الصور لاحقًا).
- **الإعداد:** `firebase_options.dart` + environment config + flavors (dev/prod)،
  والمفاتيح خارج الكود (per `engineering_standards.md`).
- **المرحلة ٢** تُفعّل الربط الحقيقي دون تغيير الـ UI (فقط provider overrides).

## 8. Testing Strategy

- **Unit (الأولوية القصوى، Dart نقي):** parsing، budget، scoring، validation/business
  rules، مع **edge cases**: مساحات صغيرة، ميزانية منخفضة جدًا، نقص بيانات.
- **Widget:** onboarding، شاشات الإدخال، بطاقات النتائج/الباقات، شاشة الملخص.
- **Integration (لاحقًا):** حفظ المشروع، ثم upload+analysis.
- الـ mock catalog والـ mock AI يجعلان الاختبارات **حتمية**. أدوات: `mocktail`.

## 9. Deployment Approach

- **المصدر/Git flow:** GitHub (`kalifah57/Furn-App`)، `main` مستقر + feature branches
  + PR لكل دمج + code review قبل الدمج.
- **CI (GitHub Actions) على كل PR:** `flutter analyze` (lint) → `flutter test`
  (unit+widget) → build check. Release workflow لاحقًا.
- **البيئات:** flavors (dev/staging/prod) عبر `--dart-define`؛ الأسرار (API keys,
  Firebase config) عبر GitHub Actions secrets — لا شيء داخل الكود.
- **التوزيع (خارج الـ MVP):** Firebase App Distribution ثم المتاجر لاحقًا.

---

## العواقب / المقايضات
- **Riverpod كـ DI** يربطنا بـ Riverpod (مقبول للحجم والسرعة).
- **mock-first** يؤخّر اكتشاف مخاطر التكامل الحقيقي (نخفّفها بعقود/abstractions نظيفة).
- **feature-first + طبقات** يزيد عمق المجلدات قليلًا مقابل قابلية توسّع وعزل أوضح.
- **`domain_engine` منفصل** = محرّك توصيات قابل للاختبار ومستقل عن أي مزوّد AI.

## نقاط تحتاج قرارك قبل التنفيذ
G1 (Riverpod ✔️ مقترح) · G2 (Static JSON catalog ✔️ مقترح) · G3 (Firebase مؤجّل خلف
mock ✔️ مقترح) · G11 (الوثائق الأربع الناقصة) — التفاصيل في
`docs/project-understanding-and-mvp.md`.
