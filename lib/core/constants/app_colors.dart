import 'package:flutter/material.dart';

class AppColors {
  // Dynamic primary/secondary theme palette (customizable from Admin Settings)
  static Color primary = const Color(0xFF340588);
  static Color primaryContainer = const Color(0xFF4B2A9E);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);

  static Color surface = const Color(0xFFFDF7FF);
  static Color surfaceContainer = const Color(0xFFF2EAFF);
  static Color surfaceContainerLow = const Color(0xFFF7F2FA);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1D192A);

  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);

  static const Color outline = Color(0xFF7A7585);
  static const Color outlineVariant = Color(0xFFE2DCEB);

  // Status colors
  static const Color success = Color(0xFF2E7D32);
  static const Color successContainer = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFE65100);
  static const Color warningContainer = Color(0xFFFFF3E0);
  static const Color errorContainer = Color(0xFFFFEBEE);

  // Backward compatibility
  static Color get secondary => primaryContainer;
  static Color get background => surface;

  static void applyPalette({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    primary = primaryColor;
    primaryContainer = secondaryColor;
    // Gently tint light surfaces to harmonize with the chosen primary color
    surface = Color.lerp(Colors.white, primaryColor, 0.025) ?? const Color(0xFFFDF7FF);
    surfaceContainer =
        Color.lerp(Colors.white, primaryColor, 0.08) ?? const Color(0xFFF2EAFF);
    surfaceContainerLow =
        Color.lerp(Colors.white, primaryColor, 0.045) ?? const Color(0xFFF7F2FA);
  }
}
