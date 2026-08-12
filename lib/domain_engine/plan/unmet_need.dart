import 'package:equatable/equatable.dart';

/// **فجوة معلنة** — شيء طلبه المستخدم ولم تستطع الخطة تلبيته.
///
/// خطة تصمت عن نقصها ليست خطة موثوقة. قبل هذا الكيان كان طلب «ثلاجة» يتحوّل إلى
/// `RecommendationCategory.other` ويظهر للمستخدم كـ«ناقص: أخرى» — تسمية بلا معنى
/// لثقب لا يُسدّ (الكتالوج فيه صفر منتج بتلك الفئة).
///
/// نحتفظ بـ **نصّ المستخدم كما كتبه** لا بفئة، لأن الفئة هي بالضبط ما فُقد.
enum UnmetReason {
  /// خارج نطاق العمل — لن نوفّره (ثلاجة، غسالة، مكيّف).
  /// ليس عيبًا فينا بل حدّ معلن، فلا يخفض الثقة.
  outOfScope,

  /// ضمن نطاقنا لكن لا يوجد في الكتالوج بعد (مرتبة، ستائر).
  /// نقص حقيقي — يخفض الثقة، وهو قائمة تسوّق للتوريد.
  notStocked,

  /// الفئة موجودة لكن لا شيء منها يدخل الغرفة أو الميزانية.
  noneFit;

  /// الاسم السلكي (snake_case) — عقد القياس (كتالوج الأحداث في docs):
  /// `out_of_scope` | `not_stocked` | `none_fit`.
  String get wire => switch (this) {
        UnmetReason.outOfScope => 'out_of_scope',
        UnmetReason.notStocked => 'not_stocked',
        UnmetReason.noneFit => 'none_fit',
      };
}

/// شريحة تقدير — «صغيرة 6–7 قدم» مقابل «متوسطة 9–13 قدم».
///
/// نطاق لا نقطة، ومؤرّخ ومنسوب: هذه **تقديرات سوق** لا أسعار. السعر الحقيقي
/// مسؤولية الكتالوج.
class ReserveTier extends Equatable {
  const ReserveTier({
    required this.labelAr,
    required this.lowSar,
    required this.highSar,
    this.cues = const [],
    this.isDefault = false,
  });

  final String labelAr;
  final double lowSar;
  final double highSar;

  /// كلمات في وصف المستخدم تُرجّح هذه الشريحة («صغير»، «مفرد»، «small»).
  final List<String> cues;

  /// الشريحة المختارة حين لا يذكر المستخدم أي مواصفة.
  final bool isDefault;

  /// الرقم المستخدم في حساب الميزانية.
  ///
  /// الوسط لا الحدّ الأدنى ولا الأعلى: الأدنى يُغري بميزانية لا تكفي، والأعلى
  /// يخنق الخطة بلا داعٍ. الوسط أقرب تقدير صادق، والنطاق كامل يُعرض للمستخدم.
  double get midSar => (lowSar + highSar) / 2;

  @override
  List<Object?> get props => [labelAr, lowSar, highSar, cues, isDefault];
}

/// حاجة لم تُلبَّ، مع سببها وتقديرها إن وُجد.
class UnmetNeed extends Equatable {
  const UnmetNeed({
    required this.rawType,
    required this.reason,
    this.tier,
    this.cheapestTier,
  });

  /// نصّ المستخدم كما كتبه: «ثلاجة بحجم مقبول».
  final String rawType;

  final UnmetReason reason;

  /// الشريحة المطابقة لوصفه — `null` حين لا نملك تقديرًا موثوقًا.
  ///
  /// نتركه فارغًا عمدًا بدل اختراع رقم: تقدير بلا مصدر أسوأ من لا تقدير.
  final ReserveTier? tier;

  /// أرخص شريحة متاحة، تُعرض حين تختلف عن [tier] — لأن الفرق بينهما قد يكون
  /// الفرق بين خطة تُنفَّذ وخطة لا تُنفَّذ.
  final ReserveTier? cheapestTier;

  /// ما يُحجز من الميزانية لهذه الحاجة (0 حين لا تقدير).
  double get reserveSar => tier?.midSar ?? 0;

  bool get hasEstimate => tier != null;

  /// هل تخفض الثقة؟ الحدّ المعلن لا، والنقص الحقيقي نعم.
  bool get lowersConfidence => reason != UnmetReason.outOfScope;

  /// هل تستحق عرض بديل أرخص؟
  bool get hasCheaperAlternative =>
      cheapestTier != null && tier != null && cheapestTier != tier;

  @override
  List<Object?> get props => [rawType, reason, tier, cheapestTier];
}
