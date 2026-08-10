# Furn-App — منصّة تخطيط تأثيث تفاعلية

تطبيق **ويب عربي-أولًا** (RTL كامل): يصف المستخدم غرفته وميزانيته، فيبني **خطة
تأثيث** يشكّلها بيده — يثبّت ويرفض ويبدّل ويضبط الميزانية — حتى **يثق بها**.
التوصية ليست المنتج؛ **الخطة هي المنتج، والثقة هي النتيجة، والشراء اختياري.**

> **الهوية والمنتج:** [`docs/product_thesis.md`](docs/product_thesis.md) هو تعريف
> المنتج المُعتمَد، وسطح الملاحة (ثلاث تجارب: المساعد · غرفتي · المعاينة) في
> [`docs/adr/0002-three-experiences-navigation.md`](docs/adr/0002-three-experiences-navigation.md).

> **الحالة: MVP (mock-first).** المحرّك الحتمي (`domain_engine`) وحلقة الثقة
> يعملان على بيانات وهمية بانتظار وصل كاتلوج حقيقي؛ **بلا خلفية أو APIs حقيقية
> بعد**. القرارات المعمارية في
> [`docs/adr/0001-mvp-architecture-decisions.md`](docs/adr/0001-mvp-architecture-decisions.md).

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
