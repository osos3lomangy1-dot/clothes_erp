import 'package:flutter/material.dart';

class AppColors {
  // Theme palette according to enterprise POS design system
  static const Color primary = Color(0xFF340588);
  static const Color primaryContainer = Color(0xFF4B2A9E);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);

  static const Color surface = Color(0xFFFDF7FF);
  static const Color surfaceContainer = Color(0xFFF2EAFF);
  static const Color surfaceContainerLow = Color(0xFFF7F2FA);
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
  static const Color secondary = primaryContainer;
  static const Color background = surface;
}
