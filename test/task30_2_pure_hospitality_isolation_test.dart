import 'dart:async';

import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/command_palette_dialog.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/hotkey_strip_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/core/services/store_presets_engine.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/domain/models/cashier_permissions_config.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/services/cashier_permissions_service.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_cubit.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_state.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_state.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_state.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_list_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _cached;
  @override
  Future<void> cacheUser(UserModel user) async => _cached = user;
  @override
  Future<UserModel?> getCachedUser() async => _cached;
  @override
  Future<void> clearCache() async => _cached = null;
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepo implements VariantRepository {
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(const Right([]));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() =>
      Stream.value(const Right([]));
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async =>
      const Right([]);
  Stream<Either<Failure, List<CategoryEntity>>> watchCategories() =>
      Stream.value(const Right([]));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCreateSaleUseCase implements CreateSaleUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShiftCubit extends Cubit<ShiftState> implements ShiftCubit {
  _FakeShiftCubit()
      : super(const ShiftState(shiftsEnabled: false, status: ShiftStatus.loaded));
  @override
  Future<void> loadShiftData() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDashboardCubit extends Cubit<DashboardState> implements DashboardCubit {
  _FakeDashboardCubit() : super(const DashboardState());
  @override
  Future<void> loadStats({bool silent = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  final FeatureGate _featureGate;
  _FakeSettingsCubit(this._featureGate) : super(const SettingsState(features: {}));

  @override
  Future<void> start() async {
    final mode = await _featureGate.getMeta(RetailSector.metaKey);
    emit(state.copyWith(sectorMode: mode ?? RetailSector.apparel));
  }

  @override
  Future<String?> setSectorMode(String mode, String userId) async {
    await _featureGate.setMeta(RetailSector.metaKey, mode, userId: userId);
    emit(state.copyWith(sectorMode: mode));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductCubit extends Cubit<ProductState> implements ProductCubit {
  _FakeProductCubit([List<ProductEntity> products = const []]) : super(ProductLoaded(products));
  @override
  Future<void> getProducts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryCubit extends Cubit<CategoryState> implements CategoryCubit {
  _FakeCategoryCubit([List<CategoryEntity> categories = const []]) : super(CategoryLoaded(categories));
  @override
  Future<void> getCategories() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late ShortcutSettingsService shortcutService;
  late _FakeAuthLocalDataSource authLocalDs;
  late _FakeAuthCubit authCubit;
  late _FakeSettingsCubit settingsCubit;
  late UserModel adminUser;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    authLocalDs = _FakeAuthLocalDataSource();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);

    featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    activityService = ActivitySettingsService(db, featureGate);
    shortcutService = ShortcutSettingsService(db);
    settingsCubit = _FakeSettingsCubit(featureGate);

    adminUser = UserModel(
      id: 'admin_1',
      name: 'المدير العام',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    await authLocalDs.cacheUser(adminUser);
    authCubit = _FakeAuthCubit(adminUser);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<ShortcutSettingsService>(shortcutService);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<ProductRepository>(_FakeProductRepo());
    sl.registerSingleton<CategoryRepository>(_FakeCategoryRepo());

    sl.registerFactory<PosCubit>(() => PosCubit(
          _FakeCreateSaleUseCase(),
          _FakeVariantRepo(),
          _FakeCategoryRepo(),
          _FakeProductRepo(),
          _FakePosRepo(),
        ));
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
    sl.registerFactory<DashboardCubit>(() => _FakeDashboardCubit());
    sl.registerFactory<SettingsCubit>(() => settingsCubit);
    sl.registerFactory<ProductCubit>(() => _FakeProductCubit());
    sl.registerFactory<CategoryCubit>(() => _FakeCategoryCubit());

    AppBranding.apply(AppBrandingConfig.defaults);
    CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
    HotkeyStripService.isVisible.value = true;
  });

  tearDown(() async {
    await authCubit.close();
    await settingsCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Addendum 30.2: RetailSector Definitions & Presets Engine', () {
    test('RetailSector definitions and helpers correctly distinguish hospitality', () {
      expect(RetailSector.all.contains(RetailSector.hospitality), isTrue);
      expect(RetailSector.isHospitalityMode(RetailSector.hospitality), isTrue);
      expect(RetailSector.isHospitalityMode(RetailSector.apparel), isFalse);
      expect(RetailSector.isHospitalityMode(RetailSector.supermarket), isFalse);

      expect(RetailSector.isSingleProductMode(RetailSector.hospitality), isTrue);
      expect(RetailSector.isSingleProductMode(RetailSector.supermarket), isTrue);
      expect(RetailSector.isSingleProductMode(RetailSector.houseware), isTrue);
      expect(RetailSector.isSingleProductMode(RetailSector.apparel), isFalse);

      expect(RetailSector.getLabel(RetailSector.hospitality), equals('مطاعم وكافيهات وضيافة'));
      expect(RetailSector.getDescription(RetailSector.hospitality), contains('استثناءات المطبخ'));
    });

    test('StorePresetsEngine.applyPreset sets retail.sector_mode to hospitality for StorePreset.hospitality', () async {
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.hospitality,
        featureGate: featureGate,
        activityService: activityService,
      );

      final sector = await featureGate.getMeta(RetailSector.metaKey);
      expect(sector, equals(RetailSector.hospitality));

      final presetCode = await featureGate.getMeta('store.preset');
      expect(presetCode, equals(StorePreset.hospitality.code));
    });
  });

  group('Addendum 30.2: MainLayout Pure Hospitality Isolation', () {
    testWidgets('Hospitality Mode: POS title becomes "كاشير المطعم والصالة" and hides Barcode, Installments, Batches', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Enable relevant features in FeatureGate
      await featureGate.setFeatureEnabled(FeatureKeys.pos, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.installments, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.preOrders, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.inventory, true, userId: 'system');

      // Set hospitality mode
      await featureGate.setMeta(RetailSector.metaKey, RetailSector.hospitality, userId: 'system');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const MainLayout(
              currentRoute: '/dashboard',
              child: Scaffold(body: Text('لوحة تحكم المطعم')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Check Cashier title is "كاشير المطعم والصالة"
      expect(find.text('كاشير المطعم والصالة'), findsOneWidget);
      expect(find.text('نقطة البيع (الكاشير)'), findsNothing);

      // 2. Cross-sector noise items are strictly hidden from Sidebar
      expect(find.text('التقسيط'), findsNothing);
      expect(find.text('الحجز المسبق والعربونات'), findsNothing);
      expect(find.text('طباعة الباركود والملصقات'), findsNothing);

      // 3. Open Command Palette and verify isolation
      final cmdPaletteBtn = find.byKey(const Key('command_palette_trigger_btn'));
      await tester.tap(cmdPaletteBtn);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPaletteDialog), findsOneWidget);
      final searchField = find.byKey(const Key('command_palette_search_field'));

      // In hospitality mode: searching for installments yields no results
      await tester.enterText(searchField, 'أقساط');
      await tester.pump();
      expect(find.text('إدارة عقود الأقساط'), findsNothing);

      // Searching for import batches yields no results
      await tester.enterText(searchField, 'شحنات');
      await tester.pump();
      expect(find.text('الحجز المسبق وشحنات الاستيراد'), findsNothing);

      // Searching for barcode printing yields no results
      await tester.enterText(searchField, 'طباعة الباركود');
      await tester.pump();
      expect(find.text('طباعة الباركود والملصقات'), findsNothing);

      // Close dialog cleanly
      Navigator.of(tester.element(find.byType(CommandPaletteDialog))).pop();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Apparel Mode: POS title is standard and Barcode, Installments, Batches are visible', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Enable relevant features in FeatureGate
      await featureGate.setFeatureEnabled(FeatureKeys.pos, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.installments, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.preOrders, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.inventory, true, userId: 'system');

      // Set apparel mode
      await featureGate.setMeta(RetailSector.metaKey, RetailSector.apparel, userId: 'system');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const MainLayout(
              currentRoute: '/dashboard',
              child: Scaffold(body: Text('لوحة تحكم الملابس')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Standard POS title
      expect(find.text('نقطة البيع (الكاشير)'), findsOneWidget);
      expect(find.text('كاشير المطعم والصالة'), findsNothing);

      // 2. Apparel items are visible
      expect(find.text('التقسيط'), findsOneWidget);
      expect(find.text('الحجز المسبق والعربونات'), findsOneWidget);
      expect(find.text('طباعة الباركود والملصقات'), findsOneWidget);

      // 3. Open Command Palette and verify items are present
      final cmdPaletteBtn = find.byKey(const Key('command_palette_trigger_btn'));
      await tester.tap(cmdPaletteBtn);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPaletteDialog), findsOneWidget);
      final searchField = find.byKey(const Key('command_palette_search_field'));

      // In apparel mode: searching for installments finds the item
      await tester.enterText(searchField, 'أقساط');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(CommandPaletteDialog),
          matching: find.text('إدارة عقود الأقساط'),
        ),
        findsOneWidget,
      );

      // Searching for import batches finds the item
      await tester.enterText(searchField, 'شحنات');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(CommandPaletteDialog),
          matching: find.text('الحجز المسبق وشحنات الاستيراد'),
        ),
        findsOneWidget,
      );

      // Searching for barcode printing finds the item
      await tester.enterText(searchField, 'طباعة الباركود');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(CommandPaletteDialog),
          matching: find.text('طباعة الباركود والملصقات'),
        ),
        findsOneWidget,
      );

      // Close dialog cleanly
      Navigator.of(tester.element(find.byType(CommandPaletteDialog))).pop();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 30.2: Contextual Hotkey Footer Strip Purge', () {
    testWidgets('Products Screen in Hospitality Mode: purges F3 new size and F4 barcode, shows restaurant hotkeys', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await featureGate.setFeatureEnabled(FeatureKeys.pos, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.inventory, true, userId: 'system');
      await featureGate.setMeta(RetailSector.metaKey, RetailSector.hospitality, userId: 'system');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const MainLayout(
              currentRoute: '/products',
              child: Scaffold(body: Text('قائمة المنتجات والتصنيفات')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Navigate to products via sidebar to ensure active title matches
      final productsNav = find.text('المنتجات والتصنيفات');
      await tester.tap(productsNav);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Apparel hotkeys must be purged
      expect(find.text('F3 سطر مقاس جديد'), findsNothing);
      expect(find.text('F4 طباعة باركود'), findsNothing);

      // Restaurant pure hotkeys must be visible
      expect(find.byKey(const Key('hotkey_products_new_meal')), findsOneWidget);
      expect(find.byKey(const Key('hotkey_products_grid_nav')), findsOneWidget);
      expect(find.byKey(const Key('hotkey_products_shortcuts')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('contextual_hotkey_strip_products')),
          matching: find.text('إضافة وجبة / مشروب'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('contextual_hotkey_strip_products')),
          matching: find.text('F1 دليل ومفاتيح'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Products Screen in Apparel Mode: shows standard apparel hotkeys', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await featureGate.setFeatureEnabled(FeatureKeys.pos, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.inventory, true, userId: 'system');
      await featureGate.setMeta(RetailSector.metaKey, RetailSector.apparel, userId: 'system');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const MainLayout(
              currentRoute: '/products',
              child: Scaffold(body: Text('قائمة المنتجات والتصنيفات')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Navigate to products via sidebar
      final productsNav = find.text('المنتجات والتصنيفات');
      await tester.tap(productsNav);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Standard apparel hotkeys must be present
      expect(find.text('F3 سطر مقاس جديد'), findsOneWidget);
      expect(find.text('F4 طباعة باركود'), findsOneWidget);
      expect(find.text('تنقل شبكي بالأسهم'), findsOneWidget);
      expect(find.text('F1 اختصارات'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 30.2: Auto-Detection Fallback & Explicit Settings Switch', () {
    testWidgets('Auto-Detection Fallback: When only restaurantsCafes activity is active, system auto-isolates hospitality', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Enable features
      await featureGate.setFeatureEnabled(FeatureKeys.pos, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.installments, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.preOrders, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.inventory, true, userId: 'system');

      // Set sector mode to apparel initially
      await featureGate.setMeta(RetailSector.metaKey, RetailSector.apparel, userId: 'system');

      // Enable ONLY restaurantsCafes activity
      await activityService.setActivityEnabled(ActivityType.restaurantsCafes, true, userId: 'system');
      for (final act in ActivityType.values) {
        if (act != ActivityType.restaurantsCafes) {
          await featureGate.setMeta('activity.${act.code}', '0', userId: 'system');
        }
      }
      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const MainLayout(
              currentRoute: '/dashboard',
              child: Scaffold(body: Text('لوحة التحكم')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should auto-detect hospitality mode
      expect(find.text('كاشير المطعم والصالة'), findsOneWidget);
      expect(find.text('التقسيط'), findsNothing);
      expect(find.text('الحجز المسبق والعربونات'), findsNothing);
      expect(find.text('طباعة الباركود والملصقات'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('SystemSettingsScreen allows toggling setting_pure_hospitality_isolation switch', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await featureGate.setMeta(RetailSector.metaKey, RetailSector.apparel, userId: 'system');
      await settingsCubit.start();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: const SystemSettingsScreen(initialCategory: 'activities'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify switch exists
      final switchFinder = find.byKey(const Key('setting_pure_hospitality_isolation'));
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isFalse);

      // Toggle switch ON
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Meta must be updated to hospitality
      final updatedSector = await featureGate.getMeta(RetailSector.metaKey);
      expect(updatedSector, equals(RetailSector.hospitality));

      // Switch should now be true
      final toggledSwitch = tester.widget<Switch>(switchFinder);
      expect(toggledSwitch.value, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 30.2: ProductListScreen Adaptive Isolation', () {
    testWidgets('Hospitality Mode: shows "إضافة وجبة / مشروب" and hides rapid scan button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await featureGate.setMeta(RetailSector.metaKey, RetailSector.hospitality, userId: 'system');

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<ProductCubit>(create: (_) => _FakeProductCubit()),
              BlocProvider<CategoryCubit>(create: (_) => _FakeCategoryCubit()),
            ],
            child: const ProductListScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Button says "إضافة وجبة / مشروب"
      expect(find.text('إضافة وجبة / مشروب'), findsOneWidget);
      expect(find.text('إضافة صنف جديد'), findsNothing);
      expect(find.text('إضافة منتج جديد'), findsNothing);

      // Rapid scan button is hidden for restaurants
      expect(find.byKey(const Key('rapid_scan_button')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Supermarket Mode: shows "إضافة صنف جديد" and reveals rapid scan button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await featureGate.setMeta(RetailSector.metaKey, RetailSector.supermarket, userId: 'system');

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<ProductCubit>(create: (_) => _FakeProductCubit()),
              BlocProvider<CategoryCubit>(create: (_) => _FakeCategoryCubit()),
            ],
            child: const ProductListScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Button says "إضافة صنف جديد"
      expect(find.text('إضافة صنف جديد'), findsOneWidget);

      // Rapid scan button is visible for supermarkets
      expect(find.byKey(const Key('rapid_scan_button')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
