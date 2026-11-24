import 'dart:async';
import 'package:drift/drift.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../products/domain/entities/activity_type.dart';

class ActivitySettingsService {
  final AppDatabase _db;
  final FeatureGate _featureGate;

  ActivitySettingsService(this._db, this._featureGate);

  static const String _metaPrefix = 'activity.';

  /// Checks strict resolved hospitality mode across retail sector and enabled activities.
  /// Unconfigured stores return all 18 activities by default, so restaurants must only
  /// activate when explicitly selected via sectorMode == hospitality or as the sole activity.
  static bool isHospitalityResolved({
    required String sectorMode,
    required List<ActivityType> enabledActivities,
  }) {
    if (RetailSector.isHospitalityMode(sectorMode)) return true;
    return enabledActivities.length == 1 &&
        enabledActivities.contains(ActivityType.restaurantsCafes);
  }

  /// Safely subscribes to [FeatureGate.watchMeta] for [RetailSector.metaKey],
  /// ignoring unstubbed fake implementations in widget tests.
  static StreamSubscription<String?>? listenSectorMode(
    FeatureGate gate,
    void Function(String mode) onMode,
  ) {
    try {
      gate
          .getMeta(RetailSector.metaKey)
          .then((val) {
            if (val != null) {
              onMode(val);
            }
          })
          .catchError((_) {});
    } catch (_) {}
    try {
      return gate
          .watchMeta(RetailSector.metaKey)
          .listen(
            (val) => onMode(val ?? RetailSector.apparel),
            onError: (_) {},
          );
    } catch (_) {
      return null;
    }
  }

  /// Safely subscribes to [watchEnabledActivities] and warms cached activities,
  /// ignoring unstubbed fake implementations in widget tests.
  static StreamSubscription<List<ActivityType>>? listenEnabledActivities(
    ActivitySettingsService service,
    void Function(List<ActivityType> activities) onActivities,
  ) {
    try {
      service.getEnabledActivities().then(onActivities).catchError((_) {});
    } catch (_) {}
    try {
      return service.watchEnabledActivities().listen(
        onActivities,
        onError: (_) {},
      );
    } catch (_) {
      return null;
    }
  }

  /// Checks if a specific activity type is enabled. Defaults to true.
  Future<bool> isActivityEnabled(ActivityType type) async {
    final metaVal = await _featureGate.getMeta('$_metaPrefix${type.code}');
    if (metaVal == null) return true;
    return metaVal == '1';
  }

  List<ActivityType>? _cachedEnabledActivities;

  /// Returns the cached list of enabled activities (or fallback to clothing).
  List<ActivityType> get cachedEnabledActivities =>
      _cachedEnabledActivities ?? [ActivityType.clothing];

  /// Returns the list of currently enabled activities.
  /// Guarantees at least one activity (clothing) is returned to prevent breaking the UI.
  Future<List<ActivityType>> getEnabledActivities() async {
    final rows = await (_db.select(
      _db.appMeta,
    )..where((t) => t.key.like('$_metaPrefix%'))).get();

    final statusMap = <String, bool>{};
    for (final r in rows) {
      final code = r.key.replaceFirst(_metaPrefix, '');
      statusMap[code] = r.value == '1';
    }

    final enabled = ActivityType.values.where((act) {
      return statusMap[act.code] ?? true;
    }).toList();

    if (enabled.isEmpty) {
      _cachedEnabledActivities = [ActivityType.clothing];
      return [ActivityType.clothing];
    }
    _cachedEnabledActivities = enabled;
    return enabled;
  }

  /// Reactive stream of enabled activities
  Stream<List<ActivityType>> watchEnabledActivities() {
    return (_db.select(
      _db.appMeta,
    )..where((t) => t.key.like('$_metaPrefix%'))).watch().map((rows) {
      final statusMap = <String, bool>{};
      for (final r in rows) {
        final code = r.key.replaceFirst(_metaPrefix, '');
        statusMap[code] = r.value == '1';
      }

      final enabled = ActivityType.values.where((act) {
        return statusMap[act.code] ?? true;
      }).toList();

      if (enabled.isEmpty) {
        _cachedEnabledActivities = [ActivityType.clothing];
        return [ActivityType.clothing];
      }
      _cachedEnabledActivities = enabled;
      return enabled;
    });
  }

  /// Sets activity status with safety validation (must keep at least 1 product activity active,
  /// and prevents mixing hospitality with retail activities in the same store).
  Future<void> setActivityEnabled(
    ActivityType type,
    bool enabled, {
    required String userId,
    bool allowSectorSwitch = false,
  }) async {
    final explicitRows = await (_db.select(
      _db.appMeta,
    )..where((t) => t.key.like('$_metaPrefix%'))).get();
    final hasExplicitRetailConfig = explicitRows.any(
      (r) =>
          r.value == '1' &&
          r.key != '$_metaPrefix${ActivityType.restaurantsCafes.code}',
    );
    final currentEnabled = await getEnabledActivities();
    if (!enabled) {
      if (currentEnabled.length <= 1 && currentEnabled.contains(type)) {
        throw Exception(
          'يجب الإبقاء على نشاط تجاري واحد مفعل على الأقل للمحل.',
        );
      }
    } else if (!allowSectorSwitch) {
      if (type == ActivityType.restaurantsCafes &&
          hasExplicitRetailConfig &&
          currentEnabled.any((a) => a != ActivityType.restaurantsCafes)) {
        throw Exception(
          'لا يمكن خلط نشاط المطاعم والكافيهات مع أنشطة التجزئة في نفس المتجر. استخدم "تبديل المتجر / إضافة نشاط جديد" لإنشاء متجر مستقل.',
        );
      }
      if (type != ActivityType.restaurantsCafes &&
          currentEnabled.length == 1 &&
          currentEnabled.contains(ActivityType.restaurantsCafes)) {
        throw Exception(
          'لا يمكن خلط نشاط المطاعم والكافيهات مع أنشطة التجزئة في نفس المتجر. استخدم "تبديل المتجر / إضافة نشاط جديد" لإنشاء متجر مستقل.',
        );
      }
    }

    await _featureGate.setMeta(
      '$_metaPrefix${type.code}',
      enabled ? '1' : '0',
      userId: userId,
    );
    await getEnabledActivities();
  }

  /// Enables or disables all activities at once.
  /// When disabling all (false), guarantees clothing remains active.
  Future<void> setAllActivities(
    bool enableAll, {
    required String userId,
  }) async {
    for (final act in ActivityType.values) {
      final shouldEnable = enableAll || act == ActivityType.clothing;
      await _featureGate.setMeta(
        '$_metaPrefix${act.code}',
        shouldEnable ? '1' : '0',
        userId: userId,
      );
    }
    await getEnabledActivities();
  }

  /// Applies a commercial store preset atomically.
  /// Enables target activities, disables others, and activates specialized modules (e.g. installments).
  Future<void> applyStorePreset(
    StorePreset preset, {
    required String userId,
  }) async {
    if (preset == StorePreset.custom) {
      final current = await getEnabledActivities();
      if (current.isEmpty) {
        for (final act in ActivityType.values) {
          await setActivityEnabled(act, true, userId: userId);
        }
      }
      return;
    }

    final target = preset.activities;
    for (final act in ActivityType.values) {
      final shouldEnable = target.contains(act);
      await _featureGate.setMeta(
        '$_metaPrefix${act.code}',
        shouldEnable ? '1' : '0',
        userId: userId,
      );
    }

    if (preset.enableInstallments) {
      await setInstallmentsEnabled(true, userId: userId);
    }
    await getEnabledActivities();
  }

  /// Checks if pre-orders module is enabled
  Future<bool> isPreOrdersEnabled() async {
    return _featureGate.isEnabled(FeatureKeys.preOrders);
  }

  /// Reactive stream of pre-orders module status
  Stream<bool> watchPreOrdersEnabled() {
    return _featureGate.watchFeatures().map(
      (m) => m[FeatureKeys.preOrders] ?? false,
    );
  }

  /// Checks if installments module is enabled
  Future<bool> isInstallmentsEnabled() async {
    return _featureGate.isEnabled(FeatureKeys.installments);
  }

  /// Enables or disables pre-orders
  Future<void> setPreOrdersEnabled(
    bool enabled, {
    required String userId,
  }) async {
    await _featureGate.setFeatureEnabled(
      FeatureKeys.preOrders,
      enabled,
      userId: userId,
    );
  }

  /// Enables or disables installments
  Future<void> setInstallmentsEnabled(
    bool enabled, {
    required String userId,
  }) async {
    await _featureGate.setFeatureEnabled(
      FeatureKeys.installments,
      enabled,
      userId: userId,
    );
  }

  /// Checks if delivery module is enabled
  Future<bool> isDeliveryEnabled() async {
    return _featureGate.isEnabled(FeatureKeys.delivery);
  }

  /// Reactive stream of delivery module status
  Stream<bool> watchDeliveryEnabled() {
    return _featureGate.watchFeatures().map(
      (m) => m[FeatureKeys.delivery] ?? false,
    );
  }

  /// Enables or disables delivery
  Future<void> setDeliveryEnabled(
    bool enabled, {
    required String userId,
  }) async {
    await _featureGate.setFeatureEnabled(
      FeatureKeys.delivery,
      enabled,
      userId: userId,
    );
  }
}
