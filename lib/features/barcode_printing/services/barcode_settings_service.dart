import 'package:flutter/foundation.dart';
import '../../../core/features/feature_gate.dart';
import '../../../core/theme/app_branding.dart';
import '../domain/models/barcode_config.dart';
import '../domain/models/barcode_label_item.dart';

class BarcodeSettingsService {
  static const String keyLabelSize = 'barcode.label_size';
  static const String keyStoreName = 'barcode.store_name';
  static const String keyShowStoreName = 'barcode.show_store_name';
  static const String keyShowProductName = 'barcode.show_product_name';
  static const String keyShowColorSize = 'barcode.show_color_size';
  static const String keyShowPrice = 'barcode.show_price';
  static const String keyShowBarcodeText = 'barcode.show_barcode_text';
  static const String keyDefaultCopies = 'barcode.default_copies';

  static final ValueNotifier<BarcodeConfig> notifier =
      ValueNotifier<BarcodeConfig>(const BarcodeConfig());

  static BarcodeConfig get current => notifier.value;

  static Future<void> loadFromFeatureGate(FeatureGate gate) async {
    try {
      final sizeStr = await gate.getMeta(keyLabelSize);
      final storeName = await gate.getMeta(keyStoreName);
      final showStoreName = await gate.getMeta(keyShowStoreName);
      final showProductName = await gate.getMeta(keyShowProductName);
      final showColorSize = await gate.getMeta(keyShowColorSize);
      final showPrice = await gate.getMeta(keyShowPrice);
      final showBarcodeText = await gate.getMeta(keyShowBarcodeText);
      final defaultCopies = await gate.getMeta(keyDefaultCopies);

      final size = BarcodeLabelSize.values.firstWhere(
        (s) => s.name == sizeStr || s.toString().split('.').last == sizeStr,
        orElse: () => BarcodeLabelSize.roll50x30,
      );

      final loaded = BarcodeConfig(
        selectedSize: size,
        storeName: (storeName != null && storeName.trim().isNotEmpty)
            ? storeName.trim()
            : AppBranding.current.appName,
        showStoreName: showStoreName == null ? true : showStoreName == '1',
        showProductName: showProductName == null
            ? true
            : showProductName == '1',
        showColorAndSize: showColorSize == null ? true : showColorSize == '1',
        showPrice: showPrice == null ? true : showPrice == '1',
        showBarcodeText: showBarcodeText == null
            ? true
            : showBarcodeText == '1',
        defaultCopies: int.tryParse(defaultCopies ?? '') ?? 1,
      );

      notifier.value = loaded;
    } catch (_) {
      notifier.value = BarcodeConfig(storeName: AppBranding.current.appName);
    }
  }

  static Future<void> save(
    BarcodeConfig config,
    FeatureGate gate, {
    required String userId,
  }) async {
    await gate.setMeta(keyLabelSize, config.selectedSize.name, userId: userId);
    await gate.setMeta(keyStoreName, config.storeName, userId: userId);
    await gate.setMeta(
      keyShowStoreName,
      config.showStoreName ? '1' : '0',
      userId: userId,
    );
    await gate.setMeta(
      keyShowProductName,
      config.showProductName ? '1' : '0',
      userId: userId,
    );
    await gate.setMeta(
      keyShowColorSize,
      config.showColorAndSize ? '1' : '0',
      userId: userId,
    );
    await gate.setMeta(
      keyShowPrice,
      config.showPrice ? '1' : '0',
      userId: userId,
    );
    await gate.setMeta(
      keyShowBarcodeText,
      config.showBarcodeText ? '1' : '0',
      userId: userId,
    );
    await gate.setMeta(
      keyDefaultCopies,
      config.defaultCopies.toString(),
      userId: userId,
    );

    notifier.value = config;
  }

  static Future<void> resetToDefaults(
    FeatureGate gate, {
    required String userId,
  }) async {
    final defaultConfig = BarcodeConfig(storeName: AppBranding.current.appName);
    await save(defaultConfig, gate, userId: userId);
  }
}
