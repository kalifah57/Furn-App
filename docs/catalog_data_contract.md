# عقد بيانات الكاتلوج — المصدر يَنشر، وFurn-App يسحب

- **الحالة:** مُعتمَد
- **التاريخ:** 2026-08

القناة بين مستودع الكاتلوج وFurn-App هي **git + CI، لا الدردشة ولا اللصق**. مستودع
الكاتلوج **مصدر الحقيقة** عند عنوان ثابت؛ وFurn-App يسحب منه تلقائيًّا عبر
`.github/workflows/sync-catalog.yml`. لا يتدخّل بشر في المسار المعتاد.

## المصدر يلتزم بهذا (جانب `abdulazizashy4/Catalog`)

1. **موضع ثابت لا يتغيّر:** فرع `main`، ملف `catalog.json`. لا يُعاد تسميته ولا نقله.
2. **مخطّط ثابت:** كل سجلّ بنفس المفاتيح، بلا زيادة، ولا `null` إلا `price_sar`:
   `id, product_name, store, category, price_sar,`
   `urls{product_link, image_url, 3d_model_url},`
   `spatial_attributes{width_cm, length_cm, height_cm},`
   `aesthetic_features{primary_colors, material, style, vibe}`.
   الأبعاد أرقام JSON، و`price_sar` رقم **أو** `null` (مجهول، لا صفر)، و`product_link`
   دائمًا على `https://www.ikea.com/sa/en/`.
3. **يَنشر خامًا:** لا يُسقط السجلّات «المريبة» (NEIDEN، HÄGERNÄS، LACK/SANDSBERG) —
   ابتلاع Furn-App مُختبَر عليها بالضبط، وإسقاطها في المصدر يُفسد عدّاد الإسقاط.
4. **بيان بجانبه:** مع كل توليد يكتب `catalog.manifest.json`:
   `{ "schema_version": 1, "record_count": <int>, "sha256": "<hex لبايتات catalog.json>", "generated_at": "<ISO-8601 UTC>" }`.
   يكشف التغيّر بثمنٍ زهيد (نستطلع البيان الصغير، ونسحب الملف الكبير فقط حين تختلف
   البصمة)، ويتيح التحقّق من السلامة.
5. **رقم للتغيير الكاسر:** أي تعديل على المخطّط (اسم/وحدة/معنى محور) **يرفع
   `schema_version`**. لا تغيير صامت للشكل.

## Furn-App يسحب هكذا (هذا المستودع)

`sync-catalog.yml` — يوميًّا، أو يدويًّا، أو عند نبضة `repository_dispatch`
(`catalog-updated`) من المصدر:

1. يجلب `catalog.json` + `catalog.manifest.json` من الموضع الثابت (خوادم CI لها
   إنترنت مفتوح، فتصل إلى الرابط الخام الذي يحجبه صندوق الجلسة).
2. **يتحقّق من السلامة:** يرفض المزامنة إن لم تطابق بصمة الملف `sha256` في البيان.
3. يكتب الملف إلى `assets/catalog/ikea_ksa.json`.
4. إن تغيّر، يفتح/يحدّث PR — فيمرّ على `flutter.yml` المعتاد، ويتحقّق
   `test/features/catalog/ikea_asset_test.dart` من أن الابتلاع يقبل الملف الحقيقي.

**الابتلاع هو مصدر الحقيقة الوحيد للتحقّق** (`IkeaCatalogIngest`، Dart، مُختبَر).
لا يكرّر الـworkflow منطق التحقّق؛ يجلب ويكتب ويترك التحقّق للاختبارات.

## ما ليس ضمن هذا العقد

تجميع الأصل في `pubspec.yaml` ووصل `IkeaCatalogRepository` والمزوّدات — خطوة
**لمرّة واحدة** تُنجَز حين يصل أول ملف حقيقي، لا في كل مزامنة.

## للمزامنة الفورية (اختياري)

يضيف المصدر workflow يُرسل `repository_dispatch` بنوع `catalog-updated` إلى
`kalifah57/Furn-App` عند كل دفع لـ`catalog.json`. يتطلب PAT دقيق الصلاحية
(Contents:read + Metadata) في سرّ. بدونه، الاستطلاع اليومي كافٍ.
