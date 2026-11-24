import '../constants/retail_sector.dart';
import '../features/feature_gate.dart';
import '../../features/products/domain/entities/activity_type.dart';
import '../../features/settings/data/services/activity_settings_service.dart';

class StorePresetsEngine {
  /// Applies a commercial store preset: configures activities, sector mode, and core feature flags.
  static Future<void> applyPreset({
    required StorePreset preset,
    required FeatureGate featureGate,
    required ActivitySettingsService activityService,
    String userId = 'system',
  }) async {
    // 1. Enable/Disable activities according to preset
    await activityService.applyStorePreset(preset, userId: userId);

    // 2. Set the retail sector mode (for POS layout and single item form)
    String sectorMode = RetailSector.apparel;
    switch (preset) {
      case StorePreset.grocery:
        sectorMode = RetailSector.supermarket;
        break;
      case StorePreset.electronics:
        sectorMode = RetailSector.houseware;
        break;
      case StorePreset.hospitality:
        sectorMode = RetailSector.hospitality;
        break;
      case StorePreset.pharmacy:
        sectorMode = RetailSector.houseware;
        break;
      case StorePreset.homeTextiles:
        sectorMode = RetailSector.houseware;
        break;
      case StorePreset.fashion:
      case StorePreset.custom:
        sectorMode = RetailSector.apparel;
        break;
    }
    await featureGate.setMeta(RetailSector.metaKey, sectorMode, userId: userId);

    // 3. Configure features
    if (preset.enableInstallments) {
      await featureGate.setFeatureEnabled(FeatureKeys.installments, true, userId: userId);
    }

    // 4. Record preset code in app_meta
    await featureGate.setMeta('store.preset', preset.code, userId: userId);
  }
}
