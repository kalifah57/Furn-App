# خطّ عربي محلّي — جاهز للتفعيل، محجوب على جلب البايتات

**الحالة:** التخطيط مُحصّن ضدّ غياب الخطّ (كل الصفوف مرنة — X9 بند ٣)، لكن **ملفّ
الخطّ نفسه لم يُضَفّ** لأن جلبه محجوب في بيئة العمل الحالية.

## لماذا لا يوجد ملفّ الخطّ هنا

`main.dart.js` يجلب Roboto من `fonts.gstatic.com` وقت التشغيل (تأكّدنا). الحلّ
تضمين خطٍّ محلّي وضبطه `fontFamily`، فلا يبقى اعتمادٌ على CDN. لكن في هذه البيئة:

- **Tajawal/Cairo (OFL):** github / npm / jsdelivr كلّها تردّ **403** (سياسة خروج
  المؤسّسة — غير قابلة لإعادة المحاولة). لا يمكن جلبها هنا.
- **الخطّ العربي المحلّي الوحيد:** GNU FreeSerif (تغطية عربية كاملة: ٢٥٥ نقطة +
  GSUB/GPOS)، لكنه **٣٫٦م ب للوزن الواحد** ولا أداة تجزئة (subset) متاحة
  (`fonttools`/`hb-subset` غائبة، وpypi محجوبة أيضًا). تضمين خطٍّ سيرِف ثقيلٍ لا
  يمكن التحقّق بصريًّا من عرضه = هندسةٌ رديئة، فامتنعنا.

## التفعيل — خطوةٌ واحدة لمن يستطيع البناء

١. ضع الملفّات (Tajawal مُرجَّح، أو Cairo) هنا:
   `assets/fonts/Tajawal-Regular.ttf` · `assets/fonts/Tajawal-Bold.ttf`
٢. في `pubspec.yaml` فُكّ الكتلة المعلّقة:
   ```yaml
   fonts:
     - family: Tajawal
       fonts:
         - asset: assets/fonts/Tajawal-Regular.ttf
         - asset: assets/fonts/Tajawal-Bold.ttf
           weight: 700
   ```
٣. في `lib/core/theme/app_theme.dart` اضبط:
   ```dart
   static const String? _fontFamily = 'Tajawal';
   ```
   فيتوقّف جلب Roboto من gstatic (لا نصٌّ يستعمله)، ويُرسَم كل شيء من ملفّات التطبيق.

**تحقّق مطلوب** (يملكه من يبني): `flutter build web` ثم فتحٌ بمحاكاة جوال — أنّ
العربية تُرسَم من الملفّ المحلّي بلا أيّ نداءٍ إلى gstatic في تبويب الشبكة.
