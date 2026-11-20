import 'package:flutter/foundation.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/theme/app_branding.dart';
import '../../domain/entities/receipt_config.dart';

class ReceiptSettingsService {
  static const String keyStoreName = 'receipt.store_name';
  static const String keyStoreActivity = 'receipt.store_activity';
  static const String keyStorePhone = 'receipt.store_phone';
  static const String keyStorePhoneSec = 'receipt.store_phone_sec';
  static const String keyStoreAddress = 'receipt.store_address';
  static const String keyTaxNumber = 'receipt.tax_number';
  static const String keyPaperWidth = 'receipt.paper_width';
  static const String keyShowCashier = 'receipt.show_cashier';
  static const String keyShowCustomer = 'receipt.show_customer';
  static const String keyShowPayment = 'receipt.show_payment';
  static const String keyShowBarcode = 'receipt.show_barcode';
  static const String keyShowItemDetails = 'receipt.show_item_details';
  static const String keyReturnPolicy = 'receipt.return_policy';
  static const String keyFooterGreeting = 'receipt.footer_greeting';

  static final ValueNotifier<ReceiptConfig> notifier =
      ValueNotifier<ReceiptConfig>(ReceiptConfig.defaults);

  static ReceiptConfig get current => notifier.value;

  static Future<void> loadFromFeatureGate(FeatureGate gate) async {
    try {
      final storeName = await gate.getMeta(keyStoreName);
      final storeActivity = await gate.getMeta(keyStoreActivity);
      final storePhone = await gate.getMeta(keyStorePhone);
      final storePhoneSec = await gate.getMeta(keyStorePhoneSec);
      final storeAddress = await gate.getMeta(keyStoreAddress);
      final taxNumber = await gate.getMeta(keyTaxNumber);
      final paperWidthStr = await gate.getMeta(keyPaperWidth);
      final showCashierStr = await gate.getMeta(keyShowCashier);
      final showCustomerStr = await gate.getMeta(keyShowCustomer);
      final showPaymentStr = await gate.getMeta(keyShowPayment);
      final showBarcodeStr = await gate.getMeta(keyShowBarcode);
      final showItemDetailsStr = await gate.getMeta(keyShowItemDetails);
      final returnPolicy = await gate.getMeta(keyReturnPolicy);
      final footerGreeting = await gate.getMeta(keyFooterGreeting);

      final loaded = ReceiptConfig(
        storeName: (storeName != null && storeName.trim().isNotEmpty)
            ? storeName.trim()
            : AppBranding.current.appName,
        storeActivity: storeActivity ?? ReceiptConfig.defaults.storeActivity,
        storePhone: storePhone ?? ReceiptConfig.defaults.storePhone,
        storePhoneSecondary: storePhoneSec ?? ReceiptConfig.defaults.storePhoneSecondary,
        storeAddress: storeAddress ?? ReceiptConfig.defaults.storeAddress,
        taxNumber: taxNumber ?? ReceiptConfig.defaults.taxNumber,
        paperWidthMm: int.tryParse(paperWidthStr ?? '') ?? ReceiptConfig.defaults.paperWidthMm,
        showCashierName: showCashierStr == null ? true : showCashierStr == '1',
        showCustomerInfo: showCustomerStr == null ? true : showCustomerStr == '1',
        showPaymentMethod: showPaymentStr == null ? true : showPaymentStr == '1',
        showBarcode: showBarcodeStr == null ? true : showBarcodeStr == '1',
        showItemDetails: showItemDetailsStr == null ? true : showItemDetailsStr == '1',
        returnPolicy: returnPolicy ?? ReceiptConfig.defaults.returnPolicy,
        footerGreeting: footerGreeting ?? ReceiptConfig.defaults.footerGreeting,
      );

      notifier.value = loaded;
    } catch (_) {
      // Fallback to defaults gracefully
      notifier.value = ReceiptConfig.defaults;
    }
  }

  static Future<void> save(
    ReceiptConfig config,
    FeatureGate gate, {
    required String userId,
  }) async {
    await gate.setMeta(keyStoreName, config.storeName, userId: userId);
    await gate.setMeta(keyStoreActivity, config.storeActivity, userId: userId);
    await gate.setMeta(keyStorePhone, config.storePhone, userId: userId);
    await gate.setMeta(keyStorePhoneSec, config.storePhoneSecondary, userId: userId);
    await gate.setMeta(keyStoreAddress, config.storeAddress, userId: userId);
    await gate.setMeta(keyTaxNumber, config.taxNumber, userId: userId);
    await gate.setMeta(keyPaperWidth, config.paperWidthMm.toString(), userId: userId);
    await gate.setMeta(keyShowCashier, config.showCashierName ? '1' : '0', userId: userId);
    await gate.setMeta(keyShowCustomer, config.showCustomerInfo ? '1' : '0', userId: userId);
    await gate.setMeta(keyShowPayment, config.showPaymentMethod ? '1' : '0', userId: userId);
    await gate.setMeta(keyShowBarcode, config.showBarcode ? '1' : '0', userId: userId);
    await gate.setMeta(keyShowItemDetails, config.showItemDetails ? '1' : '0', userId: userId);
    await gate.setMeta(keyReturnPolicy, config.returnPolicy, userId: userId);
    await gate.setMeta(keyFooterGreeting, config.footerGreeting, userId: userId);

    notifier.value = config;
  }

  static Future<void> resetToDefaults(
    FeatureGate gate, {
    required String userId,
  }) async {
    final defaultConfig = ReceiptConfig.defaults.copyWith(
      storeName: AppBranding.current.appName,
    );
    await save(defaultConfig, gate, userId: userId);
  }
}

