class RetailSector {
  static const String apparel = 'apparel';
  static const String supermarket = 'supermarket';
  static const String houseware = 'houseware';
  static const String hospitality = 'hospitality';

  static const String metaKey = 'retail.sector_mode';

  static const List<String> all = [
    apparel,
    supermarket,
    houseware,
    hospitality,
  ];

  static String getLabel(String mode) {
    switch (mode) {
      case supermarket:
        return 'سوبر ماركت وبقالة';
      case houseware:
        return 'أدوات منزلية وتجارة عامة';
      case hospitality:
        return 'مطاعم وكافيهات وضيافة';
      case apparel:
      default:
        return 'ملابس وأحذية وأزياء';
    }
  }

  static String getDescription(String mode) {
    switch (mode) {
      case supermarket:
        return 'إضافة سريعة بالمسح الضوئي، منتجات بدون مقاسات أو ألوان، تركيز كامل على الكاشير والسكانر.';
      case houseware:
        return 'إضافة يدوية بسيطة ومباشرة للمنتجات، بدون مقاسات أو ألوان، دعم كامل للتقسيط والآجل.';
      case hospitality:
        return 'إدارة الوجبات واستثناءات المطبخ، طلبات الصالة وتيك أواي، بدون مقاسات أو ألوان أو باركود إلزامي.';
      case apparel:
      default:
        return 'دعم كامل لمصفوفة المقاسات والألوان وتوليد ملصقات الباركود الداخلية للأزياء.';
    }
  }

  static bool isHospitalityMode(String mode) => mode == hospitality;

  static bool isSingleProductMode(String mode) {
    return mode == supermarket || mode == houseware || mode == hospitality;
  }
}

