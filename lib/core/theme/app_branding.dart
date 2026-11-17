import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../features/feature_gate.dart';

class AppBrandingConfig {
  final String appName;
  final Color primaryColor;
  final Color secondaryColor;

  const AppBrandingConfig({
    required this.appName,
    required this.primaryColor,
    required this.secondaryColor,
  });

  static const AppBrandingConfig defaults = AppBrandingConfig(
    appName: 'سيستم مبيعات',
    primaryColor: Color(0xFF340588),
    secondaryColor: Color(0xFF4B2A9E),
  );

  AppBrandingConfig copyWith({
    String? appName,
    Color? primaryColor,
    Color? secondaryColor,
  }) {
    return AppBrandingConfig(
      appName: appName ?? this.appName,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBrandingConfig &&
          runtimeType == other.runtimeType &&
          appName == other.appName &&
          primaryColor.toARGB32() == other.primaryColor.toARGB32() &&
          secondaryColor.toARGB32() == other.secondaryColor.toARGB32();

  @override
  int get hashCode =>
      Object.hash(appName, primaryColor.toARGB32(), secondaryColor.toARGB32());
}

class AppColorPreset {
  final String name;
  final Color primary;
  final Color secondary;

  const AppColorPreset({
    required this.name,
    required this.primary,
    required this.secondary,
  });
}

class AppBranding {
  static const String keyAppName = 'branding.app_name';
  static const String keyPrimaryColor = 'branding.primary_color';
  static const String keySecondaryColor = 'branding.secondary_color';

  static final ValueNotifier<AppBrandingConfig> notifier =
      ValueNotifier<AppBrandingConfig>(AppBrandingConfig.defaults);

  static AppBrandingConfig get current => notifier.value;

  static const List<AppColorPreset> presets = [
    AppColorPreset(
      name: 'بنفسجي ملكي (الافتراضي)',
      primary: Color(0xFF340588),
      secondary: Color(0xFF4B2A9E),
    ),
    AppColorPreset(
      name: 'أزرق تنفيذي',
      primary: Color(0xFF0D47A1),
      secondary: Color(0xFF1976D2),
    ),
    AppColorPreset(
      name: 'أخضر زمردي',
      primary: Color(0xFF00695C),
      secondary: Color(0xFF00897B),
    ),
    AppColorPreset(
      name: 'عنابي كلاسيك',
      primary: Color(0xFF880E4F),
      secondary: Color(0xFFAD1457),
    ),
    AppColorPreset(
      name: 'رمادي فحمي أنيق',
      primary: Color(0xFF263238),
      secondary: Color(0xFF455A64),
    ),
    AppColorPreset(
      name: 'كحلي ليلي',
      primary: Color(0xFF1A237E),
      secondary: Color(0xFF3949AB),
    ),
    AppColorPreset(
      name: 'بني فاخر',
      primary: Color(0xFF4E342E),
      secondary: Color(0xFF6D4C41),
    ),
    AppColorPreset(
      name: 'أخضر غابات',
      primary: Color(0xFF1B5E20),
      secondary: Color(0xFF2E7D32),
    ),
  ];

  static String colorToHex(Color color) {
    final argb = color.toARGB32();
    return argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  static Color? parseHexColor(String? hex) {
    if (hex == null) return null;
    var clean = hex.trim().replaceAll('#', '').toUpperCase();
    if (clean.length == 6) {
      clean = 'FF$clean';
    }
    if (clean.length != 8) return null;
    final val = int.tryParse(clean, radix: 16);
    if (val == null) return null;
    return Color(val);
  }

  static void apply(AppBrandingConfig config) {
    AppColors.applyPalette(
      primaryColor: config.primaryColor,
      secondaryColor: config.secondaryColor,
    );
    notifier.value = config;
  }

  static Future<void> loadFromFeatureGate(FeatureGate gate) async {
    try {
      final name = await gate.getMeta(keyAppName);
      final primaryHex = await gate.getMeta(keyPrimaryColor);
      final secondaryHex = await gate.getMeta(keySecondaryColor);

      final config = AppBrandingConfig(
        appName: (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : AppBrandingConfig.defaults.appName,
        primaryColor: parseHexColor(primaryHex) ??
            AppBrandingConfig.defaults.primaryColor,
        secondaryColor: parseHexColor(secondaryHex) ??
            AppBrandingConfig.defaults.secondaryColor,
      );
      apply(config);
    } catch (_) {
      apply(AppBrandingConfig.defaults);
    }
  }

  static Future<void> save(
    FeatureGate gate, {
    required String appName,
    required Color primaryColor,
    required Color secondaryColor,
    required String userId,
  }) async {
    final cleanName =
        appName.trim().isEmpty ? AppBrandingConfig.defaults.appName : appName.trim();
    await gate.setMeta(keyAppName, cleanName, userId: userId);
    await gate.setMeta(keyPrimaryColor, colorToHex(primaryColor), userId: userId);
    await gate.setMeta(keySecondaryColor, colorToHex(secondaryColor), userId: userId);

    apply(AppBrandingConfig(
      appName: cleanName,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    ));
  }

  static Future<void> resetToDefaults(
    FeatureGate gate, {
    required String userId,
  }) async {
    await save(
      gate,
      appName: AppBrandingConfig.defaults.appName,
      primaryColor: AppBrandingConfig.defaults.primaryColor,
      secondaryColor: AppBrandingConfig.defaults.secondaryColor,
      userId: userId,
    );
  }
}

