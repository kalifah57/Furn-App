/// تعدادات مطابقة لقيم `json_schema.md`.
/// كل تعداد يوفّر تحويلًا آمنًا من/إلى النص المستخدم في الـ JSON.

enum RoomType {
  bedroom,
  livingRoom,
  guestRoom,
  other;

  String get wire => switch (this) {
        RoomType.bedroom => 'bedroom',
        RoomType.livingRoom => 'living_room',
        RoomType.guestRoom => 'guest_room',
        RoomType.other => 'other',
      };

  /// اسم عربي للعرض في الواجهة.
  String get arabicLabel => switch (this) {
        RoomType.bedroom => 'غرفة نوم',
        RoomType.livingRoom => 'غرفة معيشة',
        RoomType.guestRoom => 'مجلس/غرفة ضيوف',
        RoomType.other => 'أخرى',
      };

  static RoomType fromWire(Object? value) {
    return RoomType.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => RoomType.other,
    );
  }
}

enum ItemPriority {
  essential,
  useful,
  optional;

  String get wire => name;

  String get arabicLabel => switch (this) {
        ItemPriority.essential => 'أساسي',
        ItemPriority.useful => 'مفيد',
        ItemPriority.optional => 'اختياري',
      };

  static ItemPriority fromWire(Object? value) {
    return ItemPriority.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => ItemPriority.optional,
    );
  }
}

enum RecommendationCategory {
  bed,
  sofa,
  rug,
  table,
  lamp,
  storage,
  other;

  String get wire => name;

  String get arabicLabel => switch (this) {
        RecommendationCategory.bed => 'سرير',
        RecommendationCategory.sofa => 'كنب/كرسي',
        RecommendationCategory.rug => 'سجادة',
        RecommendationCategory.table => 'طاولة',
        RecommendationCategory.lamp => 'إضاءة',
        RecommendationCategory.storage => 'تخزين',
        RecommendationCategory.other => 'أخرى',
      };

  static RecommendationCategory fromWire(Object? value) {
    return RecommendationCategory.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => RecommendationCategory.other,
    );
  }
}

enum BundleTier {
  budget,
  balanced,
  premium;

  String get wire => name;

  String get arabicLabel => switch (this) {
        BundleTier.budget => 'اقتصادية',
        BundleTier.balanced => 'متوازنة',
        BundleTier.premium => 'مميّزة',
      };

  static BundleTier fromWire(Object? value) {
    return BundleTier.values.firstWhere(
      (e) => e.wire == value,
      orElse: () => BundleTier.budget,
    );
  }
}
