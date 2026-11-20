import 'package:flutter/material.dart';

class AppColors {
  // Brand Dynamic Accent (10% Usage)
  static Color primary = const Color(0xFF6366F1); // Indigo / Modern Accent
  static Color primaryContainer = const Color(0xFF818CF8);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);

  // Neutral Surfaces (60% Usage - Eye Relaxing)
  static const Color surface = Color(0xFFF8FAFC); // Slate 50 (Calm Canvas)
  static const Color surfaceContainer = Color(0xFFF1F5F9); // Slate 100
  static const Color surfaceContainerLow = Color(0xFFF8FAFC);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF); // Pure White Cards
  
  // Slate Typography & Icons (30% Usage)
  static const Color onSurface = Color(0xFF0F172A); // Slate 900
  static const Color onSurfaceVariant = Color(0xFF475569); // Slate 600
  static const Color outline = Color(0xFF94A3B8); // Slate 400
  static const Color outlineVariant = Color(0xFFE2E8F0); // Slate 200 (Soft Dividers)

  // Functional Semantic Colors (Muted & Accessible)
  static const Color success = Color(0xFF10B981);
  static const Color successContainer = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFFFBEB);
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEF2F2);
  static const Color onError = Color(0xFFFFFFFF);

  // Backward Compatibility
  static Color get secondary => primaryContainer;
  static Color get background => surface;
  static const Color textMuted = onSurfaceVariant;

  /// Apply custom user palette safely without polluting the clean neutral surfaces
  static void applyPalette({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    primary = primaryColor;
    primaryContainer = secondaryColor;
    // We intentionally keep surface & surfaceContainerLowest neutral (white & light slate)
    // to maintain maximum eye comfort and prevent visual clutter.
  }
}
