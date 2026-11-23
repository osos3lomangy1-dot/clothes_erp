import 'package:flutter/foundation.dart';
import '../features/feature_gate.dart';

/// Service to manage the visibility state of the bottom hotkey strip across POS and MainLayout
class HotkeyStripService {
  static const String metaKey = 'ui.show_bottom_hotkey_strip';

  static final ValueNotifier<bool> isVisible = ValueNotifier<bool>(true);

  static bool get current => isVisible.value;

  /// Loads hotkey strip visibility setting from FeatureGate metadata on startup
  static Future<void> loadFromFeatureGate(FeatureGate gate) async {
    try {
      final raw = await gate.getMeta(metaKey);
      if (raw != null && raw.isNotEmpty) {
        isVisible.value = raw == '1' || raw.toLowerCase() == 'true';
      } else {
        isVisible.value = true;
      }
    } catch (_) {
      isVisible.value = true;
    }
  }

  /// Saves updated setting to app_meta and notifies all listening widgets
  static Future<void> setVisible(
    FeatureGate gate,
    bool visible, {
    String userId = 'admin',
  }) async {
    isVisible.value = visible;
    await gate.setMeta(
      metaKey,
      visible ? '1' : '0',
      userId: userId,
    );
  }

  /// Toggles visibility temporarily (e.g. collapse button in the footer strip)
  static void toggleTemporary([bool? visible]) {
    isVisible.value = visible ?? !isVisible.value;
  }
}

