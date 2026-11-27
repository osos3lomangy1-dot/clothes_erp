import 'package:flutter/foundation.dart';
import '../../../core/features/feature_gate.dart';
import '../domain/models/cashier_permissions_config.dart';

class CashierPermissionsService {
  static const String metaKey = 'cashier.permissions.config';

  static final ValueNotifier<CashierPermissionsConfig> notifier =
      ValueNotifier<CashierPermissionsConfig>(const CashierPermissionsConfig());

  static CashierPermissionsConfig get current => notifier.value;

  /// Loads cashier permissions from FeatureGate metadata on startup
  static Future<void> loadFromFeatureGate(FeatureGate gate) async {
    try {
      final raw = await gate.getMeta(metaKey);
      if (raw != null && raw.isNotEmpty) {
        notifier.value = CashierPermissionsConfig.fromJson(raw);
      } else {
        notifier.value = const CashierPermissionsConfig();
      }
    } catch (_) {
      notifier.value = const CashierPermissionsConfig();
    }
  }

  /// Saves updated permissions and notifies all listening widgets
  static Future<void> save(
    FeatureGate gate,
    CashierPermissionsConfig config, {
    required String userId,
  }) async {
    notifier.value = config;
    await gate.setMeta(metaKey, config.toJson(), userId: userId);
  }
}
