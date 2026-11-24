import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/core/theme/app_theme.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeFeatureGate implements FeatureGate {
  final Map<String, String> _meta = {};
  final Map<String, bool> _features = {
    'installments': true,
  };

  @override
  Future<bool> isEnabled(String key) async => _features[key] ?? false;

  @override
  Future<String?> getMeta(String key) async => _meta[key];

  @override
  Future<void> setMeta(String key, String value, {required String userId, bool audit = true}) async {
    _meta[key] = value;
  }

  @override
  Stream<String?> watchMeta(String key) => Stream.value(_meta[key]);

  @override
  Stream<Map<String, bool>> watchFeatures() => Stream.value(_features);

  @override
  Future<Map<String, bool>> getFeatures() async => _features;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit()
      : super(
          AuthAuthenticated(
            UserModel(
              id: 'admin-1',
              name: 'مدير النظام',
              email: 'admin@bay3ah.com',
              role: 'admin',
              isActive: true,
              createdAt: DateTime(2026, 1, 1),
            ),
          ),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeActivitySettingsService implements ActivitySettingsService {
  final Set<ActivityType> _activities;
  _FakeActivitySettingsService(this._activities);

  @override
  List<ActivityType> get cachedEnabledActivities => _activities.toList();

  @override
  Future<bool> isActivityEnabled(ActivityType type) async => _activities.contains(type);

  @override
  Future<List<ActivityType>> getEnabledActivities() async => _activities.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sl = GetIt.instance;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await sl.reset();
    final db = AppDatabase(NativeDatabase.memory());
    sl.registerSingleton<AppDatabase>(db);
    final mockGate = _FakeFeatureGate();
    sl.registerSingleton<FeatureGate>(mockGate);
    final actService = _FakeActivitySettingsService({ActivityType.clothing});
    sl.registerSingleton<ActivitySettingsService>(actService);
    AppBranding.apply(AppBrandingConfig.defaults);
  });

  tearDown(() async {
    if (sl.isRegistered<AppDatabase>()) {
      await sl<AppDatabase>().close();
    }
  });

  group('Task 30.8: AppBrandingConfig & AppBranding Typography Tests', () {
    test('Default values contain Cairo font and 1.0 font scale', () {
      const config = AppBrandingConfig.defaults;
      expect(config.appName, 'بيعة');
      expect(config.fontFamily, 'Cairo');
      expect(config.fontScale, 1.0);
    });

    test('copyWith updates fontFamily and fontScale correctly', () {
      final config = AppBrandingConfig.defaults.copyWith(
        fontFamily: 'Almarai',
        fontScale: 1.15,
      );
      expect(config.fontFamily, 'Almarai');
      expect(config.fontScale, 1.15);
      expect(config.appName, 'بيعة');
    });

    test('Equality and hashCode respect fontFamily and fontScale', () {
      final config1 = AppBrandingConfig.defaults.copyWith(
        fontFamily: 'Tajawal',
        fontScale: 0.85,
      );
      final config2 = AppBrandingConfig.defaults.copyWith(
        fontFamily: 'Tajawal',
        fontScale: 0.85,
      );
      final config3 = AppBrandingConfig.defaults.copyWith(
        fontFamily: 'Alexandria',
        fontScale: 0.85,
      );

      expect(config1 == config2, true);
      expect(config1.hashCode == config2.hashCode, true);
      expect(config1 == config3, false);
    });

    test('AppBranding.save persists fontFamily and fontScale to FeatureGate', () async {
      final gate = sl<FeatureGate>();

      await AppBranding.save(
        gate,
        appName: 'سوبر ماركت النور',
        primaryColor: const Color(0xFF0D47A1),
        secondaryColor: const Color(0xFF1976D2),
        fontFamily: 'Almarai',
        fontScale: 1.15,
        userId: 'admin-1',
      );

      expect(await gate.getMeta(AppBranding.keyFontFamily), 'Almarai');
      expect(await gate.getMeta(AppBranding.keyFontScale), '1.15');
      expect(AppBranding.current.fontFamily, 'Almarai');
      expect(AppBranding.current.fontScale, 1.15);
    });

    test('AppBranding.loadFromFeatureGate loads persisted fontFamily and fontScale', () async {
      final gate = sl<FeatureGate>();
      await gate.setMeta(AppBranding.keyAppName, 'مقهى السعادة', userId: 'admin-1');
      await gate.setMeta(AppBranding.keyFontFamily, 'Alexandria', userId: 'admin-1');
      await gate.setMeta(AppBranding.keyFontScale, '1.3', userId: 'admin-1');

      await AppBranding.loadFromFeatureGate(gate);

      expect(AppBranding.current.appName, 'مقهى السعادة');
      expect(AppBranding.current.fontFamily, 'Alexandria');
      expect(AppBranding.current.fontScale, 1.3);
    });

    test('AppBranding.resetToDefaults resets fontFamily and fontScale to defaults', () async {
      final gate = sl<FeatureGate>();
      await AppBranding.save(
        gate,
        appName: 'مطعم البركة',
        primaryColor: const Color(0xFF00695C),
        secondaryColor: const Color(0xFF00897B),
        fontFamily: 'Tajawal',
        fontScale: 0.85,
        userId: 'admin-1',
      );

      await AppBranding.resetToDefaults(gate, userId: 'admin-1');

      expect(AppBranding.current.fontFamily, 'Cairo');
      expect(AppBranding.current.fontScale, 1.0);
      expect(await gate.getMeta(AppBranding.keyFontFamily), 'Cairo');
      expect(await gate.getMeta(AppBranding.keyFontScale), '1.0');
    });
  });

  group('Task 30.8: AppTheme & Typography Engine Tests', () {
    test('AppTheme.build creates valid ThemeData with custom font families', () {
      final themeCairo = AppTheme.build(
        primary: const Color(0xFF0A2E5C),
        secondary: const Color(0xFF1FB5A8),
        fontFamily: 'Cairo',
      );
      expect(themeCairo.appBarTheme.titleTextStyle?.fontFamily, contains('Cairo'));

      final themeAlmarai = AppTheme.build(
        primary: const Color(0xFF0A2E5C),
        secondary: const Color(0xFF1FB5A8),
        fontFamily: 'Almarai',
      );
      expect(themeAlmarai.appBarTheme.titleTextStyle?.fontFamily, contains('Almarai'));

      final themeTajawal = AppTheme.build(
        primary: const Color(0xFF0A2E5C),
        secondary: const Color(0xFF1FB5A8),
        fontFamily: 'Tajawal',
      );
      expect(themeTajawal.appBarTheme.titleTextStyle?.fontFamily, contains('Tajawal'));

      final themeAlexandria = AppTheme.build(
        primary: const Color(0xFF0A2E5C),
        secondary: const Color(0xFF1FB5A8),
        fontFamily: 'Alexandria',
      );
      expect(themeAlexandria.appBarTheme.titleTextStyle?.fontFamily, contains('Alexandria'));
    });

    test('AppTheme.getTextStyle returns styled text with target font family', () {
      final styleCairo = AppTheme.getTextStyle(fontFamily: 'Cairo', fontSize: 16);
      expect(styleCairo.fontSize, 16);
      expect(styleCairo.fontFamily, contains('Cairo'));

      final styleAlmarai = AppTheme.getTextStyle(fontFamily: 'Almarai', fontSize: 14);
      expect(styleAlmarai.fontSize, 14);
      expect(styleAlmarai.fontFamily, contains('Almarai'));

      final styleTajawal = AppTheme.getTextStyle(fontFamily: 'Tajawal', fontSize: 12);
      expect(styleTajawal.fontSize, 12);
      expect(styleTajawal.fontFamily, contains('Tajawal'));

      final styleAlexandria = AppTheme.getTextStyle(fontFamily: 'Alexandria', fontSize: 18);
      expect(styleAlexandria.fontSize, 18);
      expect(styleAlexandria.fontFamily, contains('Alexandria'));
    });

    testWidgets('TextScaler.linear scales widget text sizes accurately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData().copyWith(
                textScaler: const TextScaler.linear(1.30),
              ),
              child: const Scaffold(
                body: Text('نظام بيعة لإدارة المبيعات'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('نظام بيعة لإدارة المبيعات'));
      expect(textWidget.data, 'نظام بيعة لإدارة المبيعات');
    });
  });

  group('Task 30.8: SystemSettingsScreen Typography Controls Widget Tests', () {
    testWidgets('Renders typography capsules, scale chips and live preview box', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authCubit = _FakeAuthCubit();
      final settingsCubit = SettingsCubit(sl<FeatureGate>());
      settingsCubit.start();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(initialCategory: 'store'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify typography section title
      expect(find.text('نوع وحجم الخط (Typography & Text Scale):'), findsOneWidget);

      // Verify font family capsules
      expect(find.text('Cairo (الافتراضي)'), findsOneWidget);
      expect(find.text('Almarai (المراعي)'), findsOneWidget);
      expect(find.text('Tajawal (تجوال)'), findsOneWidget);
      expect(find.text('Alexandria (الإسكندرية)'), findsOneWidget);

      // Verify font scale capsules
      expect(find.text('85% مدمج'), findsOneWidget);
      expect(find.text('100% قياسي'), findsOneWidget);
      expect(find.text('115% مريح'), findsOneWidget);
      expect(find.text('130% كبير'), findsOneWidget);

      // Verify live preview text box
      expect(find.byKey(const Key('typography_live_preview_box')), findsOneWidget);
      expect(find.byKey(const Key('typography_live_preview_text')), findsOneWidget);
      expect(find.text('نظام بيعة لإدارة المبيعات والمطاعم - 1234567890'), findsOneWidget);
    });

    testWidgets('Tapping font family and scale capsules updates live preview and saving persists', (tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authCubit = _FakeAuthCubit();
      final settingsCubit = SettingsCubit(sl<FeatureGate>());
      settingsCubit.start();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(initialCategory: 'store'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scroll to font family capsule and tap Almarai
      await tester.ensureVisible(find.text('Almarai (المراعي)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Almarai (المراعي)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Scroll to font scale capsule and tap 115%
      await tester.ensureVisible(find.text('115% مريح'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('115% مريح'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Live preview box header text reflects Almarai - 115%
      expect(find.textContaining('Almarai - 115%'), findsOneWidget);

      // Scroll to and click save button
      await tester.ensureVisible(find.byKey(const Key('branding_save_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('branding_save_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that AppBranding now holds Almarai and 1.15
      expect(AppBranding.current.fontFamily, 'Almarai');
      expect(AppBranding.current.fontScale, 1.15);

      // Verify that FeatureGate has stored the updated metadata
      final gate = sl<FeatureGate>();
      expect(await gate.getMeta(AppBranding.keyFontFamily), 'Almarai');
      expect(await gate.getMeta(AppBranding.keyFontScale), '1.15');
    });
  });
}
