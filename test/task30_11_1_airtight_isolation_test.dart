import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
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
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';
import 'package:clothes_erp/features/categories/data/repositories/category_repository_impl.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_state.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_state.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_state.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/presentation/screens/receipt_customizer_screen.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/purchases_screen.dart';
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
  final List<VariantEntity> items;
  _FakeVariantRepo([this.items = const []]);
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(Right(items));
  @override
  Future<Either<Failure, List<VariantEntity>>> getAllVariants() async =>
      Right(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  final List<ProductEntity> items;
  _FakeProductRepo([this.items = const []]);
  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() =>
      Stream.value(Right(items));
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      Right(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async =>
      const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
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

class _FakeInventoryCubit extends Cubit<InventoryState> implements InventoryCubit {
  _FakeInventoryCubit() : super(const InventoryLoaded([]));
  @override
  Future<void> loadInventory({bool lowStockOnly = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePurchasesCubit extends Cubit<PurchasesState> implements PurchasesCubit {
  _FakePurchasesCubit() : super(const PurchasesState());
  @override
  Future<void> loadPurchases({String? paymentStatus, String? supplierId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSuppliersCubit extends Cubit<SuppliersState> implements SuppliersCubit {
  _FakeSuppliersCubit() : super(const SuppliersState());
  @override
  Future<void> loadSuppliers({String? query}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoodsReceiptCubit extends Cubit<GoodsReceiptState>
    implements GoodsReceiptCubit {
  _FakeGoodsReceiptCubit() : super(const GoodsReceiptState());
  @override
  Future<void> loadGoodsReceipts({String? status, String? supplierId}) async {}
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late AuthCubit authCubit;
  late UserModel adminUser;

  final sl = GetIt.instance;

  setUp(() async {
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    final authLocalDs = _FakeAuthLocalDataSource();
    featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    activityService = ActivitySettingsService(db, featureGate);

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

    AppBranding.apply(AppBrandingConfig.defaults);
    CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
    HotkeyStripService.isVisible.value = true;
    ReceiptSettingsService.notifier.value = ReceiptConfig.defaults;

    final legacyMealProduct = ProductEntity(
      id: 'legacy_meal_1',
      name: 'وجبة برجر قديمة',
      categoryId: 'cat_1',
      categoryName: 'أصناف',
      activityType: 'restaurantsCafes',
      description: const RestaurantCulinaryData(
        calories: 780,
        ingredients: 'لحم، خبز، جبن',
        prepTimeMinutes: 12,
        kitchenStation: 'جريل',
      ).toEncodedString(),
      createdAt: DateTime.now(),
    );

    final shirtProduct = ProductEntity(
      id: 'shirt_1',
      name: 'تيشيرت قطن',
      description: '',
      categoryId: 'cat_1',
      categoryName: 'أصناف',
      activityType: 'clothing',
      createdAt: DateTime.now(),
    );

    final mealVariant = VariantEntity(
      id: 'var_legacy_meal_1',
      productId: 'legacy_meal_1',
      productName: 'وجبة برجر قديمة',
      productCode: 'REST-780',
      size: 'L',
      color: 'أساسي',
      costPrice: 5000,
      salePrice: 12000,
      quantity: 25,
      minStock: 5,
      createdAt: DateTime.now(),
    );

    final shirtVariant = VariantEntity(
      id: 'var_shirt_1',
      productId: 'shirt_1',
      productName: 'تيشيرت قطن',
      productCode: 'SHIRT-1',
      size: 'M',
      color: 'أبيض',
      costPrice: 10000,
      salePrice: 20000,
      quantity: 15,
      minStock: 5,
      createdAt: DateTime.now(),
    );

    final productRepo = _FakeProductRepo([legacyMealProduct, shirtProduct]);
    final variantRepo = _FakeVariantRepo([mealVariant, shirtVariant]);
    final categoryRepo = _FakeCategoryRepo();
    final posRepo = _FakePosRepo();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<BranchProvider>(branchProvider);
    sl.registerSingleton<TxWriter>(txWriter);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<ShortcutSettingsService>(ShortcutSettingsService(db));
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<ProductRepository>(productRepo);
    sl.registerSingleton<VariantRepository>(variantRepo);
    sl.registerSingleton<CategoryRepository>(categoryRepo);
    sl.registerSingleton<PosRepository>(posRepo);

    sl.registerFactory<PosCubit>(
      () => PosCubit(
        CreateSaleUseCase(posRepo),
        variantRepo,
        categoryRepo,
        productRepo,
        posRepo,
      ),
    );
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
    sl.registerFactory<InventoryCubit>(() => _FakeInventoryCubit());
    sl.registerFactory<PurchasesCubit>(() => _FakePurchasesCubit());
    sl.registerFactory<SuppliersCubit>(() => _FakeSuppliersCubit());
    sl.registerFactory<GoodsReceiptCubit>(() => _FakeGoodsReceiptCubit());
    sl.registerFactory<DashboardCubit>(() => _FakeDashboardCubit());
    sl.registerFactory<SettingsCubit>(() => SettingsCubit(featureGate));
  });

  tearDown(() async {
    await authCubit.close();
    await db.close();
    await sl.reset();
  });

  group('Addendum 30.11.1: Centralized Isolation Helper', () {
    test('isHospitalityResolved treats unconfigured 18-activity default and apparel mode as NON-hospitality', () async {
      // Fresh DB: getEnabledActivities returns all 18 activities by default
      final all18 = await activityService.getEnabledActivities();
      expect(all18.length, greaterThan(1));
      expect(all18.contains(ActivityType.restaurantsCafes), isTrue);

      expect(
        ActivitySettingsService.isHospitalityResolved(
          sectorMode: RetailSector.apparel,
          enabledActivities: all18,
        ),
        isFalse,
      );

      expect(
        ActivitySettingsService.isHospitalityResolved(
          sectorMode: RetailSector.supermarket,
          enabledActivities: all18,
        ),
        isFalse,
      );

      // Even if explicitly clothing + restaurantsCafes are active
      expect(
        ActivitySettingsService.isHospitalityResolved(
          sectorMode: RetailSector.apparel,
          enabledActivities: const [
            ActivityType.clothing,
            ActivityType.restaurantsCafes,
          ],
        ),
        isFalse,
      );

      // Returns true ONLY when RetailSector.hospitality OR restaurantsCafes is the sole active activity
      expect(
        ActivitySettingsService.isHospitalityResolved(
          sectorMode: RetailSector.hospitality,
          enabledActivities: all18,
        ),
        isTrue,
      );
      expect(
        ActivitySettingsService.isHospitalityResolved(
          sectorMode: RetailSector.apparel,
          enabledActivities: const [ActivityType.restaurantsCafes],
        ),
        isTrue,
      );
    });

    test('CategoryRepositoryImpl does NOT auto-seed restaurant categories in default unconfigured store', () async {
      final repo = CategoryRepositoryImpl(
        CategoryLocalDataSource(db, sl<BranchProvider>()),
      );
      // Fresh DB has all 18 activities unregistered & apparel default sector
      await activityService.getEnabledActivities();
      final res = await repo.getCategories();
      expect(res.isRight(), isTrue);
      expect(res.getOrElse(() => []), isEmpty);
    });
  });

  group('Addendum 30.11.1: Zero Hospitality Leakage in Default / Apparel Mode (even with legacy restaurant product & 18 defaults)', () {
    testWidgets('1. PosScreen hides petty cash, kitchen waste, hospitality bar, and meal card culinary badges', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Populate cache with default 18 activities (restaurantsCafes is true among all 18, sectorMode is apparel)
      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<ShiftCubit>.value(value: _FakeShiftCubit()),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('pos_petty_cash_btn')), findsNothing);
      expect(find.byKey(const Key('kitchen_waste_btn')), findsNothing);
      expect(find.byKey(const Key('hospitality_dine_in')), findsNothing);
      expect(find.byKey(const Key('hospitality_table_selector')), findsNothing);
      expect(find.byKey(const Key('print_kot_button')), findsNothing);
      expect(find.byKey(const Key('tip_chip_5')), findsNothing);

      // Even though legacy_meal_1 has activityType: restaurantsCafes & 780 kcal,
      // POS card must NOT display restaurant badges in apparel store mode.
      expect(find.text('وجبة برجر قديمة'), findsOneWidget);
      expect(find.byKey(const Key('product_calorie_badge_legacy_meal_1')), findsNothing);
      expect(find.byKey(const Key('product_culinary_info_btn_legacy_meal_1')), findsNothing);

      // Tapping the legacy product in apparel mode adds it directly to cart instead of opening meal customizer
      await tester.tap(find.text('وجبة برجر قديمة'));
      await tester.pump();
      expect(find.byKey(const Key('meal_customizer_modal')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('2. InventoryScreen hides kitchen_waste_btn and kitchen tabs in apparel/default mode', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const InventoryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kitchen_waste_btn')), findsNothing);
      expect(
        find.text('تقييم رأس المال، متابعة الأرصدة، تسوية التالف، وحركات كل صنف'),
        findsOneWidget,
      );
      expect(find.text('تقييم تكلفة الوجبات، مخزون المواد الخام، والهالك'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('3. ReceiptCustomizerScreen hides Dine-In Service Charge & hospitality body button in apparel mode', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const ReceiptCustomizerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down ListView so _buildLayoutOptionsCard, _buildTaxAndServiceCard and _buildFooterPoliciesCard build
      final listViewFinder = find.byType(ListView).first;
      await tester.drag(listViewFinder, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt_show_details_switch')), findsOneWidget);
      expect(find.byKey(const Key('receipt_group_variants_switch')), findsOneWidget);

      await tester.drag(listViewFinder, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt_service_charge_enabled_switch')), findsNothing);
      expect(find.text('التحكم في ضريبة القيمة المضافة (VAT)'), findsOneWidget);
      expect(find.text('التحكم في الضريبة وخدمة الصالة للمطاعم والكافيهات'), findsNothing);

      await tester.drag(listViewFinder, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('apply_hospitality_template_body_btn')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 30.11.1: Settings Sync & Reactive Stream Isolation', () {
    testWidgets('4. Switching sector to apparel & toggling isolation switch OFF disables restaurantsCafes safely without min-1 exception', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Start from hospitality exclusive mode
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.hospitality,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );
      final settingsCubit = sl<SettingsCubit>()..start();
      addTearDown(() => settingsCubit.close());

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
      await tester.pumpAndSettle();

      // Tap apparel sector tile
      final apparelTile = find.byKey(const Key('sector_tile_apparel'));
      await tester.ensureVisible(apparelTile);
      await tester.tap(apparelTile);
      await tester.pumpAndSettle();

      expect(await featureGate.getMeta(RetailSector.metaKey), equals(RetailSector.apparel));
      expect(await activityService.isActivityEnabled(ActivityType.restaurantsCafes), isFalse);
      expect(await activityService.isActivityEnabled(ActivityType.clothing), isTrue);

      // Now navigate to activities tab and toggle pure hospitality switch ON -> OFF
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(initialCategory: 'activities'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final isoSwitch = find.byKey(const Key('setting_pure_hospitality_isolation'));
      // Drag into center of scrollable viewport so sticky header doesn't intercept hit testing
      await tester.scrollUntilVisible(
        isoSwitch,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(isoSwitch).value, isFalse);

      // Toggle ON
      await tester.tap(isoSwitch);
      await tester.pumpAndSettle();
      expect(await featureGate.getMeta(RetailSector.metaKey), equals(RetailSector.hospitality));
      expect(await activityService.getEnabledActivities(), equals([ActivityType.restaurantsCafes]));
      expect(tester.widget<Switch>(isoSwitch).value, isTrue);

      // Toggle OFF -> activates clothing first, disables restaurantsCafes safely with zero exception
      await tester.tap(isoSwitch);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await featureGate.getMeta(RetailSector.metaKey), equals(RetailSector.apparel));
      expect(await activityService.isActivityEnabled(ActivityType.clothing), isTrue);
      expect(await activityService.isActivityEnabled(ActivityType.restaurantsCafes), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('5. PurchasesScreen and PosScreen react immediately when sectorMode streams change', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await StorePresetsEngine.applyPreset(
        preset: StorePreset.fashion,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );

      // Mount PurchasesScreen in apparel mode (4 tabs including Pending Receipts)
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const PurchasesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('استلامات معلقة (Pending Receipts)'), findsOneWidget);

      // Dynamically switch sector to hospitality while PurchasesScreen is alive
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.hospitality,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('استلامات معلقة (Pending Receipts)'), findsNothing);

      // Switch back to PosScreen and toggle dynamically from apparel -> hospitality
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.fashion,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<ShiftCubit>.value(value: _FakeShiftCubit()),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('pos_petty_cash_btn')), findsNothing);

      await StorePresetsEngine.applyPreset(
        preset: StorePreset.hospitality,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('pos_petty_cash_btn')), findsOneWidget);
      expect(find.byKey(const Key('kitchen_waste_btn')), findsOneWidget);
      expect(find.byKey(const Key('hospitality_dine_in')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 30.11.1: Full Hospitality Features Shown & Retail Features Purged When Hospitality Active', () {
    testWidgets('6. In hospitality mode: InventoryScreen shows kitchen_waste_btn & ReceiptCustomizerScreen isolates apparel switches', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await StorePresetsEngine.applyPreset(
        preset: StorePreset.hospitality,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );
      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const InventoryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kitchen_waste_btn')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const ReceiptCustomizerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listViewFinder = find.byType(ListView).first;
      await tester.drag(listViewFinder, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt_show_details_switch')), findsNothing);
      expect(find.byKey(const Key('receipt_group_variants_switch')), findsNothing);

      await tester.drag(listViewFinder, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt_service_charge_enabled_switch')), findsOneWidget);

      await tester.drag(listViewFinder, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('apply_hospitality_template_body_btn')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('7. In hospitality mode: MainLayout shows hospitality POS and hides installments/pre-orders/barcodes', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await StorePresetsEngine.applyPreset(
        preset: StorePreset.hospitality,
        featureGate: featureGate,
        activityService: activityService,
        userId: 'admin_1',
      );

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

      expect(find.text('كاشير المطعم والصالة'), findsOneWidget);
      expect(find.text('التقسيط'), findsNothing);
      expect(find.text('الحجز المسبق والعربونات'), findsNothing);
      expect(find.text('طباعة الباركود والملصقات'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
