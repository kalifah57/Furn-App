/// نصوص الواجهة (عربية-أولًا). بنية بسيطة قابلة للترحيل إلى ARB/gen-l10n لاحقًا (G9).
class AppStrings {
  AppStrings._();

  static const appTitle = 'التأثيث الذكي';
  static const appTagline = 'مستشارك الرقمي لتأثيث الغرف ضمن ميزانيتك';

  // Onboarding
  static const onboardingStart = 'ابدأ الآن';
  static const onboardingSaved = 'مشاريعي المحفوظة';
  static const onboardingPoints = [
    'صف غرفتك بالصوت أو النص أو الصور',
    'نحلّل الأبعاد والاحتياج والميزانية',
    'نقترح قطعًا فردية وباقات متناسقة',
  ];

  // Input method
  static const chooseInputMethod = 'اختر طريقة الإدخال';
  static const inputVoice = 'تسجيل صوتي';
  static const inputVoiceSub = 'صف غرفتك بصوتك (تجريبي)';
  static const inputImage = 'رفع صور';
  static const inputImageSub = 'أضف صور الغرفة (تجريبي)';
  static const inputManual = 'إدخال يدوي';
  static const inputManualSub = 'أدخل التفاصيل بنفسك — المسار الموصى به';

  // Manual input
  static const manualTitle = 'تفاصيل الغرفة';
  static const roomType = 'نوع الغرفة';
  static const widthM = 'العرض (م)';
  static const lengthM = 'الطول (م)';
  static const budgetMax = 'سقف الميزانية (ريال)';
  static const budgetFlexible = 'الميزانية مرنة';
  static const preferredStyle = 'النمط المفضّل';
  static const essentialItems = 'العناصر الأساسية';
  static const optionalItems = 'العناصر الاختيارية';
  static const analyzeRequest = 'حلّل الطلب';

  // Voice / image
  static const voiceTitle = 'التسجيل الصوتي';
  static const voiceHint = 'اضغط للتسجيل (محاكاة) ثم حلّل';
  static const startRecording = 'تسجيل ثم تحليل';
  static const imageTitle = 'صور الغرفة';
  static const imageHint = 'أضف صورًا (محاكاة) ثم حلّل';
  static const addSampleImage = 'إضافة صورة تجريبية';

  // Analysis
  static const analyzing = 'جاري تحليل الطلب…';
  static const recommending = 'جاري إعداد التوصيات…';
  static const requestSummary = 'ملخص الطلب';
  static const followUpTitle = 'أسئلة متابعة قصيرة';
  static const followUpHint = 'بعض البيانات ناقصة — أجب لتحسين النتائج';
  static const continueBtn = 'متابعة';
  static const skip = 'تخطٍّ';
  static const viewRecommendations = 'عرض التوصيات';
  static const missingInfo = 'بيانات ناقصة';
  static const warnings = 'تنبيهات';
  static const confidence = 'درجة الثقة';

  // Recommendations
  static const recommendationsTitle = 'التوصيات';
  static const individualTab = 'قطع فردية';
  static const bundlesTab = 'باقات';
  static const bundleReason = 'سبب الاختيار';
  static const bundleTradeoffs = 'أبرز التنازلات';
  static const bundleFeatures = 'أبرز المزايا';
  static const exceedsBudgetWarn = 'تتجاوز الميزانية — تُعرض مع تنبيه';
  static const totalPrice = 'الإجمالي';
  static const saveProject = 'حفظ المشروع';
  static const projectSaved = 'تم حفظ المشروع';

  // Saved
  static const savedTitle = 'مشاريعي المحفوظة';
  static const noSavedProjects = 'لا توجد مشاريع محفوظة بعد';

  // Errors / common
  static const retry = 'إعادة المحاولة';
  static const genericError = 'حدث خطأ. حاول مرة أخرى.';
  static const sar = 'ريال';
}
