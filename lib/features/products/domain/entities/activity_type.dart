import 'package:flutter/material.dart';

enum ActivitySector {
  fashion('fashion', 'الأزياء والأناقة', Icons.checkroom_rounded),
  tech('tech', 'التكنولوجيا والأجهزة', Icons.devices_other_rounded),
  food('food', 'الأغذية والسوبرماركت', Icons.shopping_cart_outlined),
  hospitality('hospitality', 'الضيافة والمطاعم والكافيهات', Icons.restaurant_menu_rounded),
  healthKids('healthKids', 'الطفل والصحة والرياضة', Icons.family_restroom_rounded),
  generalHome('generalHome', 'المستلزمات العامة والمنزل', Icons.category_rounded);

  final String code;
  final String label;
  final IconData icon;

  const ActivitySector(this.code, this.label, this.icon);
}

enum ActivityType {
  // 1. الأزياء والأناقة
  clothing('clothing', 'ملابس وأزياء', Icons.checkroom_rounded, ActivitySector.fashion),
  footwearBags('footwearBags', 'شنط وأحذية', Icons.shopping_bag_outlined, ActivitySector.fashion),
  accessoriesBeauty('accessoriesBeauty', 'إكسسوارات ومجوهرات', Icons.auto_awesome_rounded, ActivitySector.fashion),
  perfumesCosmetics('perfumesCosmetics', 'عطور ومستحضرات تجميل', Icons.sanitizer_outlined, ActivitySector.fashion),
  watchesEyewear('watchesEyewear', 'ساعات ونظارات', Icons.visibility_outlined, ActivitySector.fashion),

  // 2. التكنولوجيا والأجهزة
  electronicsMobiles('electronicsMobiles', 'موبايلات وإلكترونيات', Icons.phone_android_rounded, ActivitySector.tech),
  homeLiving('homeLiving', 'أدوات منزلية وأجهزة', Icons.home_work_outlined, ActivitySector.tech),

  // 3. الأغذية والسوبرماركت
  supermarketGroceries('supermarketGroceries', 'سوبرماركت وبقالة', Icons.shopping_cart_outlined, ActivitySector.food),
  spicesNuts('spicesNuts', 'عطارة وتوابل وياميش', Icons.eco_outlined, ActivitySector.food),
  sweetsBakery('sweetsBakery', 'حلويات ومخابز', Icons.cake_outlined, ActivitySector.food),

  // 4. الضيافة والمطاعم والكافيهات
  restaurantsCafes('restaurantsCafes', 'مطاعم وكافيهات وعصائر', Icons.restaurant_menu_rounded, ActivitySector.hospitality),

  // 5. الطفل والصحة والرياضة
  kidsToys('kidsToys', 'ألعاب أطفال وهدايا ورضع', Icons.smart_toy_outlined, ActivitySector.healthKids),
  pharmacySupplies('pharmacySupplies', 'صيدليات ومستلزمات طبية', Icons.local_pharmacy_outlined, ActivitySector.healthKids),
  sportsFitness('sportsFitness', 'أدوات وملابس رياضية', Icons.fitness_center_rounded, ActivitySector.healthKids),

  // 6. المستلزمات العامة والمنزل
  bookstoreStationery('bookstoreStationery', 'مكتبات وأدوات مدرسية', Icons.menu_book_outlined, ActivitySector.generalHome),
  textilesDecor('textilesDecor', 'مفروشات وستائر وديكور', Icons.texture_outlined, ActivitySector.generalHome),
  petShop('petShop', 'مستلزمات حيوانات أليفة', Icons.pets_outlined, ActivitySector.generalHome),
  general('general', 'عام / تجاري مخصص', Icons.category_outlined, ActivitySector.generalHome);

  final String code;
  final String label;
  final IconData icon;
  final ActivitySector sector;

  const ActivityType(this.code, this.label, this.icon, this.sector);

  String get labelArabic => label;

  /// هل النشاط يعتمد على مصفوفة مقاسات وألوان (أزياء / أحذية / رياضة / مفروشات)؟
  bool get isMatrixBased =>
      this == ActivityType.clothing ||
      this == ActivityType.footwearBags ||
      this == ActivityType.sportsFitness ||
      this == ActivityType.textilesDecor;

  /// هل النشاط يعتمد على صنف أحادي مباشر بالقطعة؟
  bool get isSingleItem => !isMatrixBased;

  /// هل يدعم تسجيل فترة ضمان وشهادة جودة؟
  bool get supportsWarranty =>
      this == ActivityType.electronicsMobiles ||
      this == ActivityType.homeLiving ||
      this == ActivityType.watchesEyewear;

  /// هل يدعم تتبع السيريال أو كود الـ IMEI للأجهزة الذكية؟
  bool get supportsIMEI => this == ActivityType.electronicsMobiles;

  /// هل يدعم البيع بالوزن (كيلو / جرام / ميزان إلكتروني)؟
  bool get supportsWeight =>
      this == ActivityType.supermarketGroceries ||
      this == ActivityType.spicesNuts ||
      this == ActivityType.sweetsBakery ||
      this == ActivityType.petShop;

  /// هل يدعم تتبع تواريخ الصلاحية والتشغيلات؟
  bool get supportsExpiry =>
      this == ActivityType.perfumesCosmetics ||
      this == ActivityType.supermarketGroceries ||
      this == ActivityType.sweetsBakery ||
      this == ActivityType.pharmacySupplies ||
      this == ActivityType.petShop;

  /// هل مؤهل للبيع بالتقسيط كافتراضي؟
  bool get supportsInstallment =>
      this == ActivityType.electronicsMobiles ||
      this == ActivityType.homeLiving ||
      this == ActivityType.watchesEyewear ||
      this == ActivityType.general;

  /// هل هو نشاط ضيافة ومطاعم وكافيهات؟
  bool get isHospitality => this == ActivityType.restaurantsCafes;

  /// هل يدعم تحديد ماركة/موديل بشكل بارز؟
  bool get supportsBrandOrModel =>
      this == ActivityType.electronicsMobiles ||
      this == ActivityType.homeLiving ||
      this == ActivityType.watchesEyewear ||
      this == ActivityType.footwearBags ||
      this == ActivityType.perfumesCosmetics ||
      this == ActivityType.sportsFitness ||
      this == ActivityType.general;

  static ActivityType fromString(String? val) {
    if (val == null || val.trim().isEmpty) return ActivityType.clothing;
    final clean = val.trim();

    // 1. Fashion
    if (clean == 'clothing' || clean == 'clothes' || clean == 'fashion' || clean == 'apparel') {
      return ActivityType.clothing;
    }
    if (clean == 'footwear_bags' || clean == 'shoes_bags' || clean == 'footwearBags' || clean == 'shoes' || clean == 'footwear' || clean == 'bags') {
      return ActivityType.footwearBags;
    }
    if (clean == 'accessories_beauty' || clean == 'accessoriesBeauty' || clean == 'accessories' || clean == 'jewelry') {
      return ActivityType.accessoriesBeauty;
    }
    if (clean == 'perfumes_cosmetics' || clean == 'perfumesCosmetics' || clean == 'perfumes' || clean == 'cosmetics' || clean == 'perfume') {
      return ActivityType.perfumesCosmetics;
    }
    if (clean == 'watches_eyewear' || clean == 'watchesEyewear' || clean == 'watches' || clean == 'eyewear' || clean == 'glasses') {
      return ActivityType.watchesEyewear;
    }

    // 2. Tech
    if (clean == 'electronics_mobiles' || clean == 'electronicsMobiles' || clean == 'electronics' || clean == 'mobiles' || clean == 'mobile') {
      return ActivityType.electronicsMobiles;
    }
    if (clean == 'home_living' || clean == 'homeLiving' || clean == 'home' || clean == 'appliances') {
      return ActivityType.homeLiving;
    }

    // 3. Food
    if (clean == 'supermarket_groceries' || clean == 'supermarketGroceries' || clean == 'supermarket' || clean == 'groceries' || clean == 'grocery') {
      return ActivityType.supermarketGroceries;
    }
    if (clean == 'spices_nuts' || clean == 'spicesNuts' || clean == 'spices' || clean == 'nuts' || clean == 'herbs') {
      return ActivityType.spicesNuts;
    }
    if (clean == 'sweets_bakery' || clean == 'sweetsBakery' || clean == 'sweets' || clean == 'bakery' || clean == 'pastry') {
      return ActivityType.sweetsBakery;
    }

    // 4. Hospitality
    if (clean == 'restaurants_cafes' || clean == 'restaurantsCafes' || clean == 'restaurants' || clean == 'cafes' || clean == 'hospitality' || clean == 'cafe' || clean == 'restaurant') {
      return ActivityType.restaurantsCafes;
    }

    // 5. Health & Kids
    if (clean == 'kids_toys' || clean == 'kidsToys' || clean == 'toys' || clean == 'kids' || clean == 'baby') {
      return ActivityType.kidsToys;
    }
    if (clean == 'pharmacy_supplies' || clean == 'pharmacySupplies' || clean == 'pharmacy' || clean == 'medical') {
      return ActivityType.pharmacySupplies;
    }
    if (clean == 'sports_fitness' || clean == 'sportsFitness' || clean == 'sports' || clean == 'fitness' || clean == 'gym') {
      return ActivityType.sportsFitness;
    }

    // 6. General & Home
    if (clean == 'bookstore_stationery' || clean == 'bookstoreStationery' || clean == 'bookstore' || clean == 'stationery' || clean == 'books') {
      return ActivityType.bookstoreStationery;
    }
    if (clean == 'textiles_decor' || clean == 'textilesDecor' || clean == 'textiles' || clean == 'decor' || clean == 'curtains') {
      return ActivityType.textilesDecor;
    }
    if (clean == 'pet_shop' || clean == 'petShop' || clean == 'pets' || clean == 'pet') {
      return ActivityType.petShop;
    }
    if (clean == 'general' || clean == 'misc' || clean == 'other') {
      return ActivityType.general;
    }

    return ActivityType.values.firstWhere(
      (e) => e.code == clean || e.name == clean,
      orElse: () => ActivityType.clothing,
    );
  }
}

/// القوالب التجارية الستة لتجهيز المتجر بنقرة واحدة (Smart Store Presets)
enum StorePreset {
  fashion(
    'fashion',
    'متجر أزياء وموضة',
    Icons.checkroom_rounded,
    {
      ActivityType.clothing,
      ActivityType.footwearBags,
      ActivityType.accessoriesBeauty,
      ActivityType.perfumesCosmetics,
      ActivityType.watchesEyewear,
    },
    'أزياء وأحذية ومجوهرات وعطور',
    false,
  ),
  electronics(
    'electronics',
    'معرض أجهزة وإلكترونيات',
    Icons.devices_rounded,
    {
      ActivityType.electronicsMobiles,
      ActivityType.homeLiving,
    },
    'إلكترونيات وأجهزة وتقسيط',
    true,
  ),
  grocery(
    'grocery',
    'سوبرماركت وبقالة وأغذية',
    Icons.local_grocery_store_outlined,
    {
      ActivityType.supermarketGroceries,
      ActivityType.spicesNuts,
      ActivityType.sweetsBakery,
    },
    'بقالة وعطارة وحلويات وميزان',
    false,
  ),
  hospitality(
    'hospitality',
    'مطاعم وكافيهات وعصائر',
    Icons.restaurant_rounded,
    {
      ActivityType.restaurantsCafes,
    },
    'صالة وتيك أواي ودليفري وبون',
    false,
  ),
  pharmacy(
    'pharmacy',
    'صيدليات وعناية شخصية',
    Icons.medical_services_outlined,
    {
      ActivityType.pharmacySupplies,
      ActivityType.perfumesCosmetics,
      ActivityType.kidsToys,
    },
    'أدوية ومستحضرات وأطفال',
    false,
  ),
  custom(
    'custom',
    'تخصيص يدوي حر',
    Icons.tune_rounded,
    {},
    'تحديد حر للمولات والمتاجر الشاملة',
    false,
  );

  final String code;
  final String title;
  final IconData icon;
  final Set<ActivityType> activities;
  final String description;
  final bool enableInstallments;

  const StorePreset(
    this.code,
    this.title,
    this.icon,
    this.activities,
    this.description,
    this.enableInstallments,
  );

  /// القوالب الستة الأساسية لمعالج الإعداد والتهيئة الأول
  static const List<StorePreset> onboardingPresets = [
    StorePreset.fashion,
    StorePreset.electronics,
    StorePreset.grocery,
    StorePreset.hospitality,
    StorePreset.pharmacy,
    StorePreset.custom,
  ];

  /// يكتشف تلقائياً القالب المتطابق مع قائمة الأنشطة المفعلة حالياً
  static StorePreset detect(Set<ActivityType> enabledActivities) {
    for (final preset in StorePreset.values) {
      if (preset == StorePreset.custom) continue;
      if (preset.activities.length == enabledActivities.length &&
          preset.activities.containsAll(enabledActivities)) {
        return preset;
      }
    }
    return StorePreset.custom;
  }
}
