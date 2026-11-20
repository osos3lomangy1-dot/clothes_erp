# دستور التصميم وهندسة واجهات النظام (UI/UX Blueprint)
> **ملاحظة للمطور (Coding Agent):** هذا الملف هو المرجع الأساسي لتعديلات الواجهات والتصميم في مشروع `clothes_erp`. يُرجى الالتزام الصارم بكل التعليمات والألوان المكتوبة هنا وعدم استخدام ألوان عشوائية أو hardcoded خارج هذه المنظومة.

---

## 🎨 الركائز الأساسية لنظام الألوان (قاعدة الـ 3 ألوان 60-30-10)

1. **اللون الحيادي الأساسي (60% - Canvas & Cards):**
   * خلفية التطبيق العامة (`Scaffold`): رمادي ثلجي هادئ مريح للعين طوال اليوم: `#F8FAFC`.
   * البطاقات، الجداول، النوافذ المنبثقة: أبيض ناصع نقي: `#FFFFFF`.
   * حدود البطاقات والفواصل: رمادي ناعم جداً: `#E2E8F0`.
   * خلفيات الحقول غير النشطة: `#F1F5F9`.

2. **لون البنية والنصوص (30% - Slate Structure):**
   * العناوين الكبرى والأيقونات البارزة: رمادي فحمي عميق: `#0F172A`.
   * نصوص القراءة والتسميات العادية: رمادي متوازن واضح: `#475569`.
   * النصوص الثانوية والتلميحات: `#94A3B8`.

3. **اللون التفاعلي وهوية المستخدم (10% - Brand Accent):**
   * اللون المخصص من الإعدادات (`primary` و `secondary`).
   * **ممنوع بتاتاً صبغ الخلفيات العريضة أو الكروت بهذا اللون.**
   * يُستخدم فقط لـ:
     - أزرار الإجراءات الرئيسية (Primary CTA Buttons).
     - التبويب النشط (Active Tab / Selected Pill).
     - حواف الحقول عند التركيز والكتابة (`focusedBorder`).
     - مفاتيح التفعيل النشطة (`Switch` / `Checkbox`).

4. **ألوان الحالات الوظيفية (Functional Colors):**
   * النجاح والأرباح والكاش: أخضر زمردي هادئ `#10B981` (مع خلفية فاتحة جداً `#ECFDF5`).
   * التحذيرات والتنبيهات: برتقالي دافئ `#F59E0B` (مع خلفية `#FFFBEB`).
   * الأخطاء والديون والمرتجعات: أحمر هادئ `#EF4444` (مع خلفية `#FEF2F2`).
   * *لا تُستخدم هذه الألوان إلا للأرقام والحالات فقط، ولا تُصبغ بها بطاقات كاملة.*

---

## 📋 خطة المهام التنفيذية (Tasks Roadmap)

- [x] **المهمة 1 (الحالية):** ضبط محرك الألوان وثيم التطبيق الموحد (`app_colors.dart` + `app_theme.dart`).
- [ ] **المهمة 2:** إعادة هندسة الشريط الجانبي والهيدر العلوي (`main_layout.dart`) ليكون شريطاً رشيقاً ومريحاً.
- [ ] **المهمة 3:** تحديث شاشة نقطة البيع (POS) وحل أخطاء الطفح (Overflow) وضبط ألوان الكروت والسلة.
- [ ] **المهمة 4:** دمج وتوحيد شاشات المنتجات والمخزون في شاشة موحدة.
- [ ] **المهمة 5:** دمج سجل الفواتير والمرتجعات في مركز معاملات موحد.
- [ ] **المهمة 6:** توحيد مركز التقارير والإعدادات.

---

## 🚀 المهمة 1: ضبط محرك الألوان وهندسة الثيم الموحد

### الملف الأول: `lib/core/constants/app_colors.dart`
**الهدف:** منع خلط اللون الأساسي مع ألوان الأسطح لحماية الخلفيات من الصبغ العشوائي، وتثبيت الدرجات الحيادية المريحة للعين.

#### الكود المستهدف لملف `lib/core/constants/app_colors.dart`:
```dart
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
```

---

### الملف الثاني: `lib/core/theme/app_theme.dart`
**الهدف:** 
1. جعل الهيدر العلوي (`AppBar`) أبيض ناصعاً بنصوص فحيمة هادئة بدلاً من الشريط الداكن المجهد للعين.
2. جعل البطاقات (`Card`) عصرية ومسطحة (`elevation: 0`) بحدود رمادية رقيقة وناعمة.
3. توحيد أنماط حقول الإدخال والأزرار.

#### الكود المستهدف لملف `lib/core/theme/app_theme.dart`:
```dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get light => build(
        primary: AppColors.primary,
        secondary: AppColors.primaryContainer,
      );

  static ThemeData build({
    required Color primary,
    required Color secondary,
  }) {
    const fontFamily = 'Cairo';

    final textTheme = ThemeData.light().textTheme.apply(
          fontFamily: fontFamily,
          bodyColor: AppColors.onSurface,
          displayColor: AppColors.onSurface,
        );

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
      fontFamily: fontFamily,
      textTheme: textTheme,
      
      // Modern Light AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceContainerLowest,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        shape: Border(
          bottom: BorderSide(color: AppColors.outlineVariant, width: 1.0),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
        iconTheme: IconThemeData(color: AppColors.onSurface),
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
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13.5,
          color: AppColors.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: fontFamily,
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
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: const BorderSide(color: AppColors.outlineVariant, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 13.5),
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
```

---

### ✅ التحقق واختبار التنفيذ:
بعد تطبيق الكود أعلاه:
1. تأكد من تشغيل `flutter test` أو بناء التطبيق للتأكد من عدم وجود أي خطأ في البناء.
2. تأكد من أن شاشات التطبيق تعمل بخلفية ثلجية مريحة وأن الكروت بيضاء محددة بإطار هادئ.
