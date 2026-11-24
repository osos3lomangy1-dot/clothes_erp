import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get light => build(
        primary: AppColors.primary,
        secondary: AppColors.primaryContainer,
      );

  static TextStyle getTextStyle({
    required String fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    final clean = fontFamily.trim();
    try {
      switch (clean.toLowerCase()) {
        case 'almarai':
          return GoogleFonts.almarai(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
          );
        case 'tajawal':
          return GoogleFonts.tajawal(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
          );
        case 'alexandria':
          return GoogleFonts.alexandria(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
          );
        case 'cairo':
        default:
          return TextStyle(
            fontFamily: 'Cairo',
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            height: height,
          );
      }
    } catch (_) {
      return TextStyle(
        fontFamily: 'Cairo',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );
    }
  }

  static TextTheme _createTextTheme(String fontFamily) {
    final base = ThemeData.light().textTheme;
    try {
      switch (fontFamily.toLowerCase()) {
        case 'almarai':
          return GoogleFonts.almaraiTextTheme(base).apply(
            bodyColor: AppColors.onSurface,
            displayColor: AppColors.onSurface,
          );
        case 'tajawal':
          return GoogleFonts.tajawalTextTheme(base).apply(
            bodyColor: AppColors.onSurface,
            displayColor: AppColors.onSurface,
          );
        case 'alexandria':
          return GoogleFonts.alexandriaTextTheme(base).apply(
            bodyColor: AppColors.onSurface,
            displayColor: AppColors.onSurface,
          );
        case 'cairo':
        default:
          return base.apply(
            fontFamily: 'Cairo',
            bodyColor: AppColors.onSurface,
            displayColor: AppColors.onSurface,
          );
      }
    } catch (_) {
      return base.apply(
        fontFamily: 'Cairo',
        bodyColor: AppColors.onSurface,
        displayColor: AppColors.onSurface,
      );
    }
  }

  static ThemeData build({
    required Color primary,
    required Color secondary,
    String fontFamily = 'Cairo',
  }) {
    final effectiveFontFamily =
        fontFamily.trim().isEmpty ? 'Cairo' : fontFamily.trim();

    final textTheme = _createTextTheme(effectiveFontFamily);

    final colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: secondary,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: secondary,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      error: AppColors.error,
      onError: AppColors.onError,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: effectiveFontFamily,
      textTheme: textTheme,
      
      // Modern Light AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceContainerLowest,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant, width: 1.0),
        ),
        titleTextStyle: getTextStyle(
          fontFamily: effectiveFontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
        iconTheme: const IconThemeData(color: AppColors.onSurface),
      ),

      // Modern Flat Card with soft border
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.outlineVariant, width: 1.0),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      ),

      // Clean Accessible Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        labelStyle: getTextStyle(
          fontFamily: effectiveFontFamily,
          fontSize: 13.5,
          color: AppColors.onSurfaceVariant,
        ),
        floatingLabelStyle: getTextStyle(
          fontFamily: effectiveFontFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.outlineVariant, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.outlineVariant, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: AppColors.error, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),

      // Buttons Styling
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: getTextStyle(
            fontFamily: effectiveFontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: const BorderSide(color: AppColors.outlineVariant, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: getTextStyle(
            fontFamily: effectiveFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: getTextStyle(
            fontFamily: effectiveFontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1.0,
        space: 1.0,
      ),
    );
  }
}
