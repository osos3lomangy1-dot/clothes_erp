import 'package:equatable/equatable.dart';

class ReceiptConfig extends Equatable {
  final String storeName;
  final String storeActivity;
  final String storePhone;
  final String storePhoneSecondary;
  final String storeAddress;
  final String taxNumber;
  final int paperWidthMm; // 80 or 58
  final bool showCashierName;
  final bool showCustomerInfo;
  final bool showPaymentMethod;
  final bool showBarcode;
  final bool showItemDetails; // size & color
  final bool groupVariantsOnReceipt; // Task 17: Group multiple variants of same model in receipt
  final String returnPolicy;
  final String footerGreeting;
  final String wifiInfo;
  final bool taxEnabled;
  final double taxRate;
  final bool taxInclusive;
  final bool dineInServiceChargeEnabled;
  final double dineInServiceChargeRate;

  const ReceiptConfig({
    required this.storeName,
    this.storeActivity = 'أحدث صيحات الملابس الجاهزة',
    this.storePhone = '01000000000',
    this.storePhoneSecondary = '',
    this.storeAddress = 'بني سويف',
    this.taxNumber = '',
    this.paperWidthMm = 80,
    this.showCashierName = true,
    this.showCustomerInfo = true,
    this.showPaymentMethod = true,
    this.showBarcode = true,
    this.showItemDetails = true,
    this.groupVariantsOnReceipt = true,
    this.returnPolicy = 'الاستبدال والاسترجاع خلال 14 يوماً مع وجود الفاتورة وأصل التكت بحالته',
    this.footerGreeting = 'شكراً لزيارتكم ونتمنى لكم يوماً سعيداً',
    this.wifiInfo = '',
    this.taxEnabled = false,
    this.taxRate = 14.0,
    this.taxInclusive = false,
    this.dineInServiceChargeEnabled = false,
    this.dineInServiceChargeRate = 12.0,
  });

  static const ReceiptConfig defaults = ReceiptConfig(
    storeName: 'بيعة',
    storeActivity: 'أحدث صيحات الملابس الجاهزة',
    storePhone: '01000000000',
    storePhoneSecondary: '',
    storeAddress: 'بني سويف',
    taxNumber: '',
    paperWidthMm: 80,
    showCashierName: true,
    showCustomerInfo: true,
    showPaymentMethod: true,
    showBarcode: true,
    showItemDetails: true,
    groupVariantsOnReceipt: true,
    returnPolicy: 'الاستبدال والاسترجاع خلال 14 يوماً مع وجود الفاتورة وأصل التكت بحالته',
    footerGreeting: 'شكراً لزيارتكم ونتمنى لكم يوماً سعيداً',
    wifiInfo: '',
    taxEnabled: false,
    taxRate: 14.0,
    taxInclusive: false,
    dineInServiceChargeEnabled: false,
    dineInServiceChargeRate: 12.0,
  );

  static const ReceiptConfig hospitalityDefaults = ReceiptConfig(
    storeName: 'بيعة - مطاعم وكافيهات',
    storeActivity: 'مطاعم وكافيهات',
    storePhone: '01000000000',
    storePhoneSecondary: '',
    storeAddress: 'بني سويف',
    taxNumber: '',
    paperWidthMm: 80,
    showCashierName: true,
    showCustomerInfo: true,
    showPaymentMethod: true,
    showBarcode: true,
    showItemDetails: false,
    groupVariantsOnReceipt: true,
    returnPolicy:
        'الأطعمة والمشروبات الطازجة غير قابلة للاسترجاع بعد مغادرة الطاولة أو استلام الأوردر لسلامة الغذاء.',
    footerGreeting: 'شكراً لزيارتكم ونتمنى لكم وجبة شهية!',
    wifiInfo: 'WiFi: Restaurant-Guest',
    taxEnabled: false,
    taxRate: 14.0,
    taxInclusive: false,
    dineInServiceChargeEnabled: true,
    dineInServiceChargeRate: 12.0,
  );

  ReceiptConfig copyWith({
    String? storeName,
    String? storeActivity,
    String? storePhone,
    String? storePhoneSecondary,
    String? storeAddress,
    String? taxNumber,
    int? paperWidthMm,
    bool? showCashierName,
    bool? showCustomerInfo,
    bool? showPaymentMethod,
    bool? showBarcode,
    bool? showItemDetails,
    bool? groupVariantsOnReceipt,
    String? returnPolicy,
    String? footerGreeting,
    String? wifiInfo,
    bool? taxEnabled,
    double? taxRate,
    bool? taxInclusive,
    bool? dineInServiceChargeEnabled,
    double? dineInServiceChargeRate,
  }) {
    return ReceiptConfig(
      storeName: storeName ?? this.storeName,
      storeActivity: storeActivity ?? this.storeActivity,
      storePhone: storePhone ?? this.storePhone,
      storePhoneSecondary: storePhoneSecondary ?? this.storePhoneSecondary,
      storeAddress: storeAddress ?? this.storeAddress,
      taxNumber: taxNumber ?? this.taxNumber,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      showCashierName: showCashierName ?? this.showCashierName,
      showCustomerInfo: showCustomerInfo ?? this.showCustomerInfo,
      showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
      showBarcode: showBarcode ?? this.showBarcode,
      showItemDetails: showItemDetails ?? this.showItemDetails,
      groupVariantsOnReceipt: groupVariantsOnReceipt ?? this.groupVariantsOnReceipt,
      returnPolicy: returnPolicy ?? this.returnPolicy,
      footerGreeting: footerGreeting ?? this.footerGreeting,
      wifiInfo: wifiInfo ?? this.wifiInfo,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxRate: taxRate ?? this.taxRate,
      taxInclusive: taxInclusive ?? this.taxInclusive,
      dineInServiceChargeEnabled:
          dineInServiceChargeEnabled ?? this.dineInServiceChargeEnabled,
      dineInServiceChargeRate:
          dineInServiceChargeRate ?? this.dineInServiceChargeRate,
    );
  }

  @override
  List<Object?> get props => [
        storeName,
        storeActivity,
        storePhone,
        storePhoneSecondary,
        storeAddress,
        taxNumber,
        paperWidthMm,
        showCashierName,
        showCustomerInfo,
        showPaymentMethod,
        showBarcode,
        showItemDetails,
        groupVariantsOnReceipt,
        returnPolicy,
        footerGreeting,
        wifiInfo,
        taxEnabled,
        taxRate,
        taxInclusive,
        dineInServiceChargeEnabled,
        dineInServiceChargeRate,
      ];
}

