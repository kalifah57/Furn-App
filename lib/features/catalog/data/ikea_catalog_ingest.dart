import '../../../shared/models/enums.dart';
import '../../../shared/models/catalog_product.dart';

/// لماذا أُسقط سجلّ — القياس لا يُبتلع، بل يُعَدّ ويُعرَض.
enum DropReason {
  /// ليس كائن JSON (سجلّ مشوّه).
  notObject,

  /// `id` فارغ — لا مفتاح أساسي.
  emptyId,

  /// رابط المنتج ليس على متجر آيكيا السعودية `https://www.ikea.com/sa/en/`.
  badProductLink,

  /// السعر `null` (مجهول). لا يعني مجانًا؛ لا يُوضع في خطة مبنيّة على ميزانية.
  unknownPrice,

  /// محور مفقود أو ≤ 0 أو > 400 سم.
  badAxis,

  /// الأبعاد أصغر من أن تكون هذه الفئة (أرضية الفئة) — قياس نظافة، لا حجم أثاث.
  belowCategoryFloor,
}

/// نتيجة الابتلاع: ما بقي، ما سقط ولماذا، وتحذيرات لا تُسقط لكنها تستحق النظر.
class IngestResult {
  const IngestResult({
    required this.products,
    required this.dropped,
    required this.warnings,
  });

  final List<CatalogProduct> products;

  /// `id` (أو `#index` إن غاب) → سبب الإسقاط.
  final Map<String, DropReason> dropped;

  /// تحذيرات نصّية (مثلًا: تبادل العرض/العمق مقابل اسم المنتج).
  final List<String> warnings;

  int get keptCount => products.length;
  int get dropCount => dropped.length;

  /// عدّ الإسقاطات حسب السبب — للتقرير.
  Map<DropReason, int> get dropHistogram {
    final h = <DropReason, int>{};
    for (final r in dropped.values) {
      h[r] = (h[r] ?? 0) + 1;
    }
    return h;
  }
}

/// يبتلع كاتلوج آيكيا السعودية (مسحٌ من موقع حيّ = **مدخل غير موثوق**) ويُخرج
/// [CatalogProduct] الذي يتكلّمه المحرّك كلّه. لا نموذج مواز: نفس الوجهة التي
/// يقرأ منها `PlanWorkspace` و`PlacementSolver`.
///
/// **محور القياس هو ما ينكسر بصمت:** آيكيا `length_cm` هو العمق (أمام-لخلف، ما
/// تسمّيه آيكيا Depth)، ويُطابق `depthCm` في المحرّك — بينما `width_cm` جانب-لجانب
/// يُطابق `widthCm`. الحلّال يبني بصمته من `widthCm × depthCm`؛ تبديل المحورين
/// يدوّر كل قطعة 90° فتبدو الغرفة سليمة والأثاث نصفه في الجدار. يحرس هذا اختبار.
class IkeaCatalogIngest {
  const IkeaCatalogIngest();

  static const double maxAxisCm = 400;

  /// أرضيات الفئات كما يفرضها مولّد الكاتلوج: `(widthCm, depthCm, heightCm)`.
  /// فئة غير مذكورة = لا أرضية. مِرآةٌ لأرقام المولّد كي نُسقط ما يُسقطه.
  static const Map<String, (double, double, double)> _floors = {
    'sofa': (90, 55, 50),
    'armchair': (45, 45, 50),
    'bed': (70, 150, 15),
    'wardrobe': (40, 25, 90),
    'dining_table': (55, 45, 55),
    'desk': (55, 35, 45),
    'dresser': (30, 25, 30),
    'bookcase': (20, 15, 50),
    'coffee_table': (35, 30, 20),
    'tv_unit': (40, 20, 15),
    'nightstand': (20, 20, 20),
    'chair': (25, 25, 45),
  };

  /// خريطة فئات آيكيا الاثنتي عشرة إلى فئات المحرّك السبع. الأصل يُحفظ في
  /// `subcategory` فلا يضيع شيء.
  static const Map<String, RecommendationCategory> _categoryMap = {
    'sofa': RecommendationCategory.sofa,
    'armchair': RecommendationCategory.sofa,
    'chair': RecommendationCategory.sofa,
    'bed': RecommendationCategory.bed,
    'wardrobe': RecommendationCategory.storage,
    'dresser': RecommendationCategory.storage,
    'bookcase': RecommendationCategory.storage,
    'nightstand': RecommendationCategory.storage,
    'dining_table': RecommendationCategory.table,
    'desk': RecommendationCategory.table,
    'coffee_table': RecommendationCategory.table,
    'tv_unit': RecommendationCategory.table,
  };

  IngestResult run(List<dynamic> records) {
    final products = <CatalogProduct>[];
    final dropped = <String, DropReason>{};
    final warnings = <String>[];

    for (var i = 0; i < records.length; i++) {
      final raw = records[i];
      if (raw is! Map) {
        dropped['#$i'] = DropReason.notObject;
        continue;
      }
      final m = raw.cast<String, dynamic>();
      final id = _str(m['id']);
      final key = id.isEmpty ? '#$i' : id;

      final reason = _validate(m);
      if (reason != null) {
        dropped[key] = reason;
        continue;
      }

      products.add(_map(m));
      final w = _warnTransposed(m);
      if (w != null) warnings.add(w);
    }

    return IngestResult(
        products: products, dropped: dropped, warnings: warnings);
  }

  // ---- validation (مدخل غير موثوق) --------------------------------------

  DropReason? _validate(Map<String, dynamic> m) {
    if (_str(m['id']).isEmpty) return DropReason.emptyId;

    final link = _str((m['urls'] as Map?)?['product_link']);
    if (!link.startsWith('https://www.ikea.com/sa/en/')) {
      return DropReason.badProductLink;
    }

    // السعر يُفحص قبل الأبعاد: منتج بلا سعر يُسقط أيًّا كان مقاسه.
    if (m['price_sar'] == null) return DropReason.unknownPrice;

    final s = (m['spatial_attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final w = _axis(s['width_cm']);
    final d = _axis(s['length_cm']); // آيكيا length = العمق
    final h = _axis(s['height_cm']);
    if (w == null || d == null || h == null) return DropReason.badAxis;

    final floor = _floors[_str(m['category'])];
    if (floor != null &&
        (w < floor.$1 || d < floor.$2 || h < floor.$3)) {
      return DropReason.belowCategoryFloor;
    }
    return null;
  }

  /// محور صالح: عدد موجب لا يتجاوز [maxAxisCm]. غير ذلك ⇒ `null`.
  double? _axis(Object? v) {
    if (v is! num) return null;
    final x = v.toDouble();
    if (x <= 0 || x > maxAxisCm) return null;
    return x;
  }

  // ---- mapping (آيكيا → CatalogProduct) ---------------------------------

  CatalogProduct _map(Map<String, dynamic> m) {
    final s = (m['spatial_attributes'] as Map).cast<String, dynamic>();
    final a =
        (m['aesthetic_features'] as Map?)?.cast<String, dynamic>() ?? const {};
    final urls = (m['urls'] as Map).cast<String, dynamic>();
    final ikeaCategory = _str(m['category']);

    return CatalogProduct(
      productId: _str(m['id']),
      title: _str(m['product_name']),
      category: _categoryMap[ikeaCategory] ?? RecommendationCategory.other,
      // الفئة الأصلية تبقى مرئية بعد الطيّ إلى السبع.
      subcategory: ikeaCategory,
      styleTags: _styleTags(a),
      colorTags: _strList(a['primary_colors']),
      materialTags: _splitMaterial(_str(a['material'])),
      // **المحور الحاسم:** length_cm (العمق) → depthCm، width_cm → widthCm.
      widthCm: (s['width_cm'] as num).toDouble(),
      depthCm: (s['length_cm'] as num).toDouble(),
      heightCm: (s['height_cm'] as num).toDouble(),
      price: (m['price_sar'] as num).toDouble(),
      currency: 'SAR',
      brand: 'IKEA',
      supplier: _str(m['store']),
      // كل الباقي مُسعَّر وصالح، فهو معروض للشراء.
      availabilityStatus: 'in_stock',
      imageUrl: _str(urls['image_url']),
      productUrl: _str(urls['product_link']),
      // نُبقي رابط الـ USDZ للمستقبل، لكن **arReady = false**: لا نموذج GLB
      // (شرط الويب/أندرويد)، والمضيف api.furn-app.com غير مُتحقَّق بعد — وتوجيه
      // Quick Look إلى ملف غير موجود يكسره. زر «شاهدها في غرفتك» يبقى مطفأً حتى
      // تُتحقَّق النماذج (hasArModel يشترط GLB أصلًا).
      modelUsdzUrl: _str(urls['3d_model_url']),
      modelGlbUrl: '',
      arReady: false,
    );
  }

  /// النمط + «الفايب» كلاهما إشارة جمالية يقرؤها `scoring._styleMatch`.
  List<String> _styleTags(Map<String, dynamic> a) {
    final out = <String>[];
    final style = _str(a['style']);
    if (style.isNotEmpty) out.add(style);
    for (final v in _splitMaterial(_str(a['vibe']))) {
      out.add(v);
    }
    return out;
  }

  /// "Polyester fabric, solid pine" → ["Polyester fabric", "solid pine"].
  List<String> _splitMaterial(String s) => s
      .split(RegExp(r'[,،]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  // ---- name ↔ dimensions cross-check (تحذير لا إسقاط) -------------------

  /// أسماء آيكيا أحيانًا تحمل «العرض×العمق سم». إن حملها الاسم وكان مبادلًا
  /// لأبعاد السجلّ، فالأرجح أن العرض والعمق مُبدَّلان (LACK, SANDSBERG) —
  /// والأرضيات لا تمسك هذا. تحذير لا إسقاط: قد يكون الاسم يذكر قياسًا آخر.
  String? _warnTransposed(Map<String, dynamic> m) {
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)')
        .firstMatch(_str(m['product_name']));
    if (match == null) return null;
    final nameW = double.tryParse(match.group(1)!);
    final nameD = double.tryParse(match.group(2)!);
    if (nameW == null || nameD == null) return null;

    final s = (m['spatial_attributes'] as Map).cast<String, dynamic>();
    final w = (s['width_cm'] as num).toDouble();
    final d = (s['length_cm'] as num).toDouble();

    final matchesAsIs = _near(nameW, w) && _near(nameD, d);
    final matchesSwapped = _near(nameW, d) && _near(nameD, w);
    if (matchesSwapped && !matchesAsIs) {
      return '${_str(m['id'])} (${_str(m['product_name'])}): '
          'الاسم يذكر ${nameW}x$nameD لكن الأبعاد ${w}x$d — عرض/عمق مُبدَّلان؟';
    }
    return null;
  }

  bool _near(double a, double b) => (a - b).abs() <= 1.0;

  // ---- helpers ----------------------------------------------------------

  static String _str(Object? v) => v == null ? '' : v.toString();

  static List<String> _strList(Object? v) => v is List
      ? [for (final e in v) e.toString()]
      : const <String>[];
}
