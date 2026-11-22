import 'dart:async';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../products/domain/entities/activity_type.dart';

class ActivitySettingsService {
  final AppDatabase _db;
  final FeatureGate _featureGate;

  ActivitySettingsService(this._db, this._featureGate);

  static const String _metaPrefix = 'activity.';

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

  /// Sets activity status with safety validation (must keep at least 1 product activity active).
  Future<void> setActivityEnabled(
    ActivityType type,
    bool enabled, {
    required String userId,
  }) async {
    if (!enabled) {
      final currentEnabled = await getEnabledActivities();
      if (currentEnabled.length <= 1 && currentEnabled.contains(type)) {
        throw Exception(
          'يجب الإبقاء على نشاط تجاري واحد مفعل على الأقل للمحل.',
        );
      }
    }

    await _featureGate.setMeta(
      '$_metaPrefix${type.code}',
      enabled ? '1' : '0',
      userId: userId,
    );
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
  }

  /// Applies a commercial store preset atomically.
  /// Enables target activities, disables others, and activates specialized modules (e.g. installments).
  Future<void> applyStorePreset(
    StorePreset preset, {
    required String userId,
  }) async {
    if (preset == StorePreset.custom) {
      // In custom mode, maintain current configuration without overriding
      final current = await getEnabledActivities();
      if (current.isEmpty) {
        await setActivityEnabled(ActivityType.clothing, true, userId: userId);
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
