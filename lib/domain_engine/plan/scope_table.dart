import 'unmet_need.dart';

/// **جدول النطاق** — ما لا نخدمه، ولماذا، وكم يُحجز له.
///
/// حتمي بالكامل: خريطة ثابتة، لا شبكة ولا عشوائية ولا نموذج لغوي. البحث السوقي
/// يحدث **مرة واحدة خارج التشغيل** وتُثبَّت نتيجته هنا، فتبقى خاصية «نفس المدخل
/// ⇒ نفس المخرج» التي بُني عليها المحرّك كله.
///
/// **الأرقام تقديرات سوق سعودي — أُخذت في أغسطس 2026 — لا أسعار.** أعِد تحقّقها
/// دوريًا. وما لا مصدر له يُترك بلا شرائح بدل اختراع رقم.

/// مدخل واحد: كلمات مفتاحية → سبب + شرائح تقدير.
class ScopeEntry {
  const ScopeEntry({
    required this.keys,
    required this.reason,
    this.tiers = const [],
  });

  /// كلمات تُطابَق داخل نصّ المستخدم (عربي/إنجليزي، مثل `category_mapper`).
  final List<String> keys;

  final UnmetReason reason;

  /// مرتّبة تصاعديًا بالسعر. فارغة = نعرف أنه خارج النطاق ولا نملك تقديرًا.
  final List<ReserveTier> tiers;
}

/// شرائح الثلاجة — الوحيدة المدعومة بأرقام سوقية مُتحقَّق منها.
///
/// المراجع (أغسطس 2026): كلاس برو 6.2 قدم = 899 · كلاس برو 9.5 قدم = 1,649 ·
/// ميديا 338 لتر = 1,749 · كلاس برو 12.9 قدم = 1,849 · كلاس برو 18.2 قدم = 3,499.
const _fridgeTiers = <ReserveTier>[
  ReserveTier(
    labelAr: 'صغيرة (6–7 قدم)',
    lowSar: 850,
    highSar: 1100,
    cues: ['صغير', 'صغيره', 'مفرد', 'ميني', 'small', 'mini', 'compact'],
  ),
  ReserveTier(
    labelAr: 'متوسطة (9–13 قدم)',
    lowSar: 1600,
    highSar: 1900,
    cues: ['متوسط', 'مقبول', 'عادي', 'medium', 'standard'],
    isDefault: true,
  ),
  ReserveTier(
    labelAr: 'كبيرة (18 قدم فأكثر)',
    lowSar: 3000,
    highSar: 3800,
    cues: ['كبير', 'كبيره', 'عائلي', 'عائلية', 'large', 'family'],
  ),
];

/// الترتيب مهمّ: أول مطابقة تفوز، والقائمة `const` فيبقى الناتج حتميًا.
const kScopeTable = <ScopeEntry>[
  // ---- خارج النطاق: قطاع تجزئة آخر (أجهزة) ----
  ScopeEntry(
    keys: ['ثلاجة', 'ثلاجه', 'براد', 'fridge', 'refrigerator'],
    reason: UnmetReason.outOfScope,
    tiers: _fridgeTiers,
  ),
  // ما يلي خارج النطاق أيضًا، لكن بلا شرائح: لم يُبحث لها سوقيًا بعد، وتقدير
  // بلا مصدر يضلّل المستخدم في ميزانيته أكثر مما يفيده.
  ScopeEntry(
    keys: ['غسالة', 'غساله', 'washing machine', 'washer'],
    reason: UnmetReason.outOfScope,
  ),
  ScopeEntry(
    keys: ['مايكرويف', 'مايكروويف', 'microwave'],
    reason: UnmetReason.outOfScope,
  ),
  ScopeEntry(keys: ['فرن', 'oven'], reason: UnmetReason.outOfScope),
  ScopeEntry(
    keys: ['مكيف', 'مكيّف', 'تكييف', 'air conditioner', 'ac unit'],
    reason: UnmetReason.outOfScope,
  ),
  ScopeEntry(
    keys: ['سخان', 'سخّان', 'water heater'],
    reason: UnmetReason.outOfScope,
  ),

  // ---- ضمن النطاق، غير متوفّر بعد: قائمة تسوّق للتوريد ----
  ScopeEntry(
    keys: ['مرتبة', 'مرتبه', 'فراش', 'mattress'],
    reason: UnmetReason.notStocked,
  ),
  ScopeEntry(
    keys: ['ستارة', 'ستاره', 'ستائر', 'curtain', 'blinds'],
    reason: UnmetReason.notStocked,
  ),
  ScopeEntry(keys: ['مرآة', 'مراية', 'mirror'], reason: UnmetReason.notStocked),
];

/// يبحث عن [rawType] في الجدول ويعيد الحاجة غير الملبّاة، أو `null` إن لم يكن
/// معروفًا كخارج النطاق.
UnmetNeed? lookupScope(String rawType) {
  final t = rawType.trim().toLowerCase();
  if (t.isEmpty) return null;

  for (final entry in kScopeTable) {
    if (!entry.keys.any((k) => t.contains(k.toLowerCase()))) continue;

    return UnmetNeed(
      rawType: rawType.trim(),
      reason: entry.reason,
      tier: _matchTier(t, entry.tiers),
      cheapestTier: entry.tiers.isEmpty ? null : entry.tiers.first,
    );
  }
  return null;
}

/// يطابق وصف المستخدم على الشرائح، ويسقط على الافتراضية عند غياب أي دلالة.
ReserveTier? _matchTier(String lowered, List<ReserveTier> tiers) {
  if (tiers.isEmpty) return null;
  for (final tier in tiers) {
    if (tier.cues.any((c) => lowered.contains(c.toLowerCase()))) return tier;
  }
  for (final tier in tiers) {
    if (tier.isDefault) return tier;
  }
  return tiers.first;
}
