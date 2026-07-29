# Furn-App — التأثيث الذكي

تطبيق جوال **عربي-أولًا** (RTL كامل) لتأثيث الغرف: المستخدم يصف الغرفة بالصوت أو
النص أو الصور، والنظام يستخرج بيانات منظمة ثم يقترح **قطعًا فردية** و**باقات
متناسقة** ضمن الميزانية — كمستشار تأثيث رقمي لا كمتجر.

> **الحالة: MVP — المرحلة ١ (mock-first).** بنية كاملة + شاشات أساسية + تدفّق توصيات
> وهمي، **بلا أي APIs حقيقية**. القرارات المعمارية في
> [`docs/adr/0001-mvp-architecture-decisions.md`](docs/adr/0001-mvp-architecture-decisions.md)،
> ومراجعة المشروع في [`docs/project-understanding-and-mvp.md`](docs/project-understanding-and-mvp.md).

## التشغيل

هذا المستودع يحتوي كود `lib/` و`test/` والأصول فقط (بلا مجلدات المنصّات). لتشغيله:

```bash
# 1) توليد مجلدات المنصّات (لا يلمس lib/)
flutter create .

# 2) جلب الحزم
flutter pub get

# 3) الاختبارات (منطق حتمي — لا يحتاج جهازًا)
flutter test

# 4) التشغيل
flutter run
```

المتطلبات: Flutter ≥ 3.24 · Dart ≥ 3.5.

## المعمارية (ملخّص)

Clean Architecture + **feature-first**، مع **فصل صارم**: الـ AI يستخرج بيانات منظمة
فقط؛ التوصيات منطق Dart حتمي مستقل.

```
lib/
  app/                 جذر التطبيق (MaterialApp.router، عربي/RTL)
  core/                config, errors (Failure/Result), theme, router, di, utils
  shared/              models (مطابقة json_schema.md), widgets, services (catalog)
  ai/                  عقود STT/Vision/LLM + prompt builder + parser + تنفيذات mock
  domain_engine/       business_rules · recommendation (scoring) · budget — Dart نقي
  features/            auth · onboarding · room_input · room_analysis ·
                       recommendations · saved_projects   (presentation/domain/data)
```

- **الحالة:** Riverpod · **التوجيه:** GoRouter · **الحقن:** providers (+ overrides للتبديل mock↔real).
- **الكتالوج:** ملف ثابت `assets/catalog/catalog.json` (~20 منتجًا).
- **Firebase:** مؤجّل خلف تجريد (mock-first) — يُفعَّل في المرحلة ٢ دون لمس الـ UI.

## خط الأنابيب

`Voice/Text/Images → STT/OCR/Vision → Normalization → Prompt Builder → LLM →
Structured JSON → Business Rules → Recommendation Engine → Budget Allocator → UI`

## الاختبارات

تركّز على المنطق الحتمي (الأولوية في `engineering_standards.md`): استخراج وهمي،
قواعد العمل، توزيع الميزانية، نموذج الدرجة، ومحرّك التوصيات (بما فيها حالات الحافة).

## المراحل القادمة

المرحلة ٢: ربط AI حقيقي · المرحلة ٣: تحسين المحرّك · المرحلة ٤: كتالوج فعلي (Firestore)
· المرحلة ٥: مراجعة بشرية اختيارية.
