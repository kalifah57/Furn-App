import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json_helpers.dart';

/// بنية بيانات المنتج من catalog_strategy.md.
/// مصدر بيانات محرّك التوصيات (في الـ MVP: ملف JSON ثابت).
class CatalogProduct extends Equatable {
  const CatalogProduct({
    required this.productId,
    required this.title,
    required this.category,
    this.subcategory = '',
    this.styleTags = const [],
    this.colorTags = const [],
    this.materialTags = const [],
    this.widthCm = 0,
    this.depthCm = 0,
    this.heightCm = 0,
    this.price = 0,
    this.currency = 'SAR',
    this.brand = '',
    this.supplier = '',
    this.availabilityStatus = 'in_stock',
    this.ratingOptional,
    this.roomSuitabilityTags = const [],
    this.imageUrl = '',
    this.productUrl = '',
    this.modelGlbUrl = '',
    this.modelUsdzUrl = '',
    this.arReady = false,
  });

  final String productId;
  final String title;
  final RecommendationCategory category;
  final String subcategory;
  final List<String> styleTags;
  final List<String> colorTags;
  final List<String> materialTags;
  final double widthCm;
  final double depthCm;
  final double heightCm;
  final double price;
  final String currency;
  final String brand;
  final String supplier;
  final String availabilityStatus;
  final double? ratingOptional;
  final List<String> roomSuitabilityTags;
  final String imageUrl;
  final String productUrl;

  /// روابط النموذج ثلاثي الأبعاد للواقع المعزّز (see it in your room).
  /// GLB لأندرويد/الويب، USDZ لـ Quick Look على iOS — بمقاس حقيقي بالمتر.
  final String modelGlbUrl;
  final String modelUsdzUrl;

  /// يُعرض زر «شاهدها في غرفتك» فقط عندما يكون النموذجان جاهزين وموثّقَي المقاس.
  final bool arReady;

  bool get isAvailable => availabilityStatus == 'in_stock';

  /// جاهزية فعلية للـ AR: العلَم مرفوع ونموذج GLB موجود على الأقل.
  bool get hasArModel => arReady && modelGlbUrl.isNotEmpty;

  /// مقاسات أرضية صالحة — شرط دخول **المعاينة** (مسقط علوي بمقياس حقيقي).
  ///
  /// المشهد ثنائي الأبعاد يحتاج أبعادًا لا نموذجًا ثلاثيًّا: اشتراط [hasArModel]
  /// هنا كان سيُفرغ المعاينة بأكملها يوم يصل كتالوج حقيقي بلا نماذج (وهو ما
  /// يفعله مُدخِل آيكيا: `arReady: false` صراحةً). الـ AR وحده يشترط النموذج.
  bool get hasFootprint => widthCm > 0 && depthCm > 0;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
        productId: asString(json['product_id']),
        title: asString(json['title']),
        category: RecommendationCategory.fromWire(json['category']),
        subcategory: asString(json['subcategory']),
        styleTags: asStringList(json['style_tags']),
        colorTags: asStringList(json['color_tags']),
        materialTags: asStringList(json['material_tags']),
        widthCm: asDouble(json['width_cm']),
        depthCm: asDouble(json['depth_cm']),
        heightCm: asDouble(json['height_cm']),
        price: asDouble(json['price']),
        currency: asString(json['currency'], 'SAR'),
        brand: asString(json['brand']),
        supplier: asString(json['supplier']),
        availabilityStatus: asString(json['availability_status'], 'in_stock'),
        ratingOptional:
            json['rating_optional'] == null ? null : asDouble(json['rating_optional']),
        roomSuitabilityTags: asStringList(json['room_suitability_tags']),
        imageUrl: asString(json['image_url']),
        productUrl: asString(json['product_url']),
        modelGlbUrl: asString(json['model_glb_url']),
        modelUsdzUrl: asString(json['model_usdz_url']),
        arReady: asBool(json['ar_ready']),
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'title': title,
        'category': category.wire,
        'subcategory': subcategory,
        'style_tags': styleTags,
        'color_tags': colorTags,
        'material_tags': materialTags,
        'width_cm': widthCm,
        'depth_cm': depthCm,
        'height_cm': heightCm,
        'price': price,
        'currency': currency,
        'brand': brand,
        'supplier': supplier,
        'availability_status': availabilityStatus,
        'rating_optional': ratingOptional,
        'room_suitability_tags': roomSuitabilityTags,
        'image_url': imageUrl,
        'product_url': productUrl,
        'model_glb_url': modelGlbUrl,
        'model_usdz_url': modelUsdzUrl,
        'ar_ready': arReady,
      };

  @override
  List<Object?> get props => [
        productId,
        title,
        category,
        subcategory,
        styleTags,
        colorTags,
        materialTags,
        widthCm,
        depthCm,
        heightCm,
        price,
        currency,
        brand,
        supplier,
        availabilityStatus,
        ratingOptional,
        roomSuitabilityTags,
        imageUrl,
        productUrl,
        modelGlbUrl,
        modelUsdzUrl,
        arReady,
      ];
}
