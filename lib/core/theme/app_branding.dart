import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../features/feature_gate.dart';

class AppBrandingConfig {
  final String appName;
  final Color primaryColor;
  final Color secondaryColor;
  final String fontFamily;
  final double fontScale;

  const AppBrandingConfig({
    required this.appName,
    required this.primaryColor,
    required this.secondaryColor,
    this.fontFamily = 'Cairo',
    this.fontScale = 1.0,
  });

  static const AppBrandingConfig defaults = AppBrandingConfig(
    appName: 'بيعة',
    primaryColor: Color(0xFF0A2E5C),
    secondaryColor: Color(0xFF1FB5A8),
    fontFamily: 'Cairo',
    fontScale: 1.0,
  );

  AppBrandingConfig copyWith({
    String? appName,
    Color? primaryColor,
    Color? secondaryColor,
    String? fontFamily,
    double? fontScale,
  }) {
    return AppBrandingConfig(
      appName: appName ?? this.appName,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      fontFamily: fontFamily ?? this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBrandingConfig &&
          runtimeType == other.runtimeType &&
          appName == other.appName &&
          primaryColor.toARGB32() == other.primaryColor.toARGB32() &&
          secondaryColor.toARGB32() == other.secondaryColor.toARGB32() &&
          fontFamily == other.fontFamily &&
          fontScale == other.fontScale;

  @override
  int get hashCode => Object.hash(
        appName,
        primaryColor.toARGB32(),
        secondaryColor.toARGB32(),
        fontFamily,
        fontScale,
      );
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
  static const String keyFontFamily = 'branding.font_family';
  static const String keyFontScale = 'branding.font_scale';

  static const List<String> supportedFonts = [
    'Cairo',
    'Almarai',
    'Tajawal',
    'Alexandria',
  ];

  static const List<double> supportedFontScales = [
    0.85,
    1.0,
    1.15,
    1.30,
  ];

  static final ValueNotifier<AppBrandingConfig> notifier =
      ValueNotifier<AppBrandingConfig>(AppBrandingConfig.defaults);

  static AppBrandingConfig get current => notifier.value;

  static const List<AppColorPreset> presets = [
    AppColorPreset(
      name: 'بيعة (الافتراضي)',
      primary: Color(0xFF0A2E5C),
      secondary: Color(0xFF1FB5A8),
    ),
    AppColorPreset(
      name: 'بنفسجي ملكي',
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
      final fontFamily = await gate.getMeta(keyFontFamily);
      final fontScaleStr = await gate.getMeta(keyFontScale);
      final fontScale =
          fontScaleStr != null ? double.tryParse(fontScaleStr) : null;

      final config = AppBrandingConfig(
        appName: (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : AppBrandingConfig.defaults.appName,
        primaryColor: parseHexColor(primaryHex) ??
            AppBrandingConfig.defaults.primaryColor,
        secondaryColor: parseHexColor(secondaryHex) ??
            AppBrandingConfig.defaults.secondaryColor,
        fontFamily: (fontFamily != null && fontFamily.trim().isNotEmpty)
            ? fontFamily.trim()
            : AppBrandingConfig.defaults.fontFamily,
        fontScale: fontScale ?? AppBrandingConfig.defaults.fontScale,
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
    String? fontFamily,
    double? fontScale,
    required String userId,
  }) async {
    final cleanName =
        appName.trim().isEmpty ? AppBrandingConfig.defaults.appName : appName.trim();
    final effectiveFontFamily = (fontFamily != null && fontFamily.trim().isNotEmpty)
        ? fontFamily.trim()
        : current.fontFamily;
    final effectiveFontScale = fontScale ?? current.fontScale;

    await gate.setMeta(keyAppName, cleanName, userId: userId);
    await gate.setMeta(keyPrimaryColor, colorToHex(primaryColor), userId: userId);
    await gate.setMeta(keySecondaryColor, colorToHex(secondaryColor), userId: userId);
    await gate.setMeta(keyFontFamily, effectiveFontFamily, userId: userId);
    await gate.setMeta(keyFontScale, effectiveFontScale.toString(), userId: userId);

    apply(AppBrandingConfig(
      appName: cleanName,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      fontFamily: effectiveFontFamily,
      fontScale: effectiveFontScale,
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
      fontFamily: AppBrandingConfig.defaults.fontFamily,
      fontScale: AppBrandingConfig.defaults.fontScale,
      userId: userId,
    );
  }
}

