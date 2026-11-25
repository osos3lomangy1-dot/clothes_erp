import 'dart:async';

import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/hotkey_strip_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
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
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/blind_receive_screen.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_state.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_state.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_form_screen.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_list_screen.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/purchases_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/widgets/shortcuts_config_dialog.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      Right([
        CategoryEntity(
          id: 'cat-1',
          name: 'تصنيف عام',
          description: '',
          createdAt: DateTime(2025, 1, 1),
        ),
      ]);
  Stream<Either<Failure, List<CategoryEntity>>> watchCategories() =>
      Stream.value(Right([
        CategoryEntity(
          id: 'cat-1',
          name: 'تصنيف عام',
          description: '',
          createdAt: DateTime(2025, 1, 1),
        ),
      ]));
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

class _FakeProductCubit extends Cubit<ProductState> implements ProductCubit {
  _FakeProductCubit([List<ProductEntity> products = const []])
      : super(ProductLoaded(products));
  @override
  Future<void> getProducts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryCubit extends Cubit<CategoryState> implements CategoryCubit {
  _FakeCategoryCubit([List<CategoryEntity>? categories])
      : super(CategoryLoaded(categories ??
            [
              CategoryEntity(
                id: 'cat-1',
                name: 'تصنيف عام',
                description: '',
                createdAt: DateTime(2025, 1, 1),
              ),
            ]));
  @override
  Future<void> getCategories() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductFormCubit extends Cubit<ProductFormState>
    implements ProductFormCubit {
  int submitCount = 0;
  String? lastSubmittedName;

  _FakeProductFormCubit()
      : super(
          ProductFormState(
            status: ProductFormStatus.initial,
            categories: [
              CategoryEntity(
                id: 'cat-1',
                name: 'تصنيف عام',
                description: '',
                createdAt: DateTime(2025, 1, 1),
              ),
            ],
            categoryId: 'cat-1',
            categoryName: 'تصنيف عام',
          ),
        );

  @override
  Future<void> init(ProductEntity? product) async {
    emit(state.copyWith(status: ProductFormStatus.initial));
  }

  @override
  void onNameChanged(String val) => emit(state.copyWith(name: val));
  @override
  void onCategoryChanged(String id, String name) =>
      emit(state.copyWith(categoryId: id, categoryName: name));
  @override
  void onDescriptionChanged(String val) => emit(state.copyWith(description: val));
  @override
  void onMinStockChanged(int val) => emit(state.copyWith(minStock: val));
  @override
  Future<void> onActivityTypeChanged(String val) async =>
      emit(state.copyWith(activityType: val));
  @override
  void onWarrantyPeriodChanged(String? val) {}
  @override
  void onBrandOrModelChanged(String? val) {}
  @override
  void onInstallmentEligibleChanged(bool val) {}

  @override
  Future<void> submitWithVariants({
    String? id,
    required List<VariantInput> variants,
  }) async {
    submitCount++;
    lastSubmittedName = state.name;
    emit(state.copyWith(status: ProductFormStatus.success));
  }

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
  _FakeSuppliersCubit()
      : super(const SuppliersState(status: SuppliersStatus.loaded, suppliers: []));
  @override
  Future<void> loadSuppliers() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _sendCombo(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
  bool alt = false,
}) async {
  if (ctrl) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (alt) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (alt) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  if (ctrl) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late ShortcutSettingsService shortcutService;
  late _FakeAuthLocalDataSource authLocalDs;
  late _FakeAuthCubit authCubit;
  _FakeProductFormCubit? lastProductFormCubit;
  late UserModel adminUser;
  late UserModel cashierUser;

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
    lastProductFormCubit = null;

    adminUser = UserModel(
      id: 'admin_1',
      name: 'المدير العام',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2025, 1, 1),
    );
    cashierUser = UserModel(
      id: 'cashier_1',
      name: 'الكاشير',
      email: 'cashier@test.com',
      role: 'cashier',
      isActive: true,
      createdAt: DateTime(2025, 1, 1),
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
    sl.registerSingleton<VariantRepository>(_FakeVariantRepo());

    sl.registerFactory<PosCubit>(() => PosCubit(
          _FakeCreateSaleUseCase(),
          _FakeVariantRepo(),
          _FakeCategoryRepo(),
          _FakeProductRepo(),
          _FakePosRepo(),
        ));
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
    sl.registerFactory<DashboardCubit>(() => _FakeDashboardCubit());
    sl.registerFactory<ProductCubit>(() => _FakeProductCubit());
    sl.registerFactory<CategoryCubit>(() => _FakeCategoryCubit());
    sl.registerFactory<ProductFormCubit>(() {
      final cubit = _FakeProductFormCubit();
      lastProductFormCubit = cubit;
      return cubit;
    });
    sl.registerFactory<PurchasesCubit>(() => _FakePurchasesCubit());
    sl.registerFactory<SuppliersCubit>(() => _FakeSuppliersCubit());
    sl.registerFactory<GoodsReceiptCubit>(
      () => GoodsReceiptCubit(InventoryLocalDataSource(db, branchProvider, txWriter)),
    );

    await featureGate.setMeta(RetailSector.metaKey, RetailSector.supermarket,
        userId: 'admin_1');
    AppBranding.apply(AppBrandingConfig.defaults);
    CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
    HotkeyStripService.isVisible.value = true;
  });

  tearDown(() async {
    await authCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 35: ShortcutSettingsService & F1 Cheatsheet', () {
    test('default shortcuts include Alt+A, Alt+R, Alt+B and parse activators', () {
      final all = shortcutService.getAllShortcuts();
      expect(all['openAddProduct'], equals('Alt+A'));
      expect(all['openBlindReceive'], equals('Alt+R'));
      expect(all['openCreatePurchase'], equals('Alt+B'));

      final addAct = shortcutService.getActivator('openAddProduct');
      expect(addAct.trigger, equals(LogicalKeyboardKey.keyA));
      expect(addAct.alt, isTrue);

      final recAct = shortcutService.getActivator('openBlindReceive');
      expect(recAct.trigger, equals(LogicalKeyboardKey.keyR));
      expect(recAct.alt, isTrue);

      final purAct = shortcutService.getActivator('openCreatePurchase');
      expect(purAct.trigger, equals(LogicalKeyboardKey.keyB));
      expect(purAct.alt, isTrue);
    });

    testWidgets('ShortcutsConfigDialog opens Role-Aware Cheatsheet and filters search',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: ShortcutsConfigDialog()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shortcuts_cheatsheet_tab')), findsOneWidget);
      expect(find.byKey(const Key('shortcuts_customizer_tab')), findsOneWidget);
      expect(find.text('إتمام ودفع الفاتورة'), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();

      expect(find.text('Alt+A'), findsOneWidget);
      expect(find.text('Alt+R'), findsOneWidget);
      expect(find.text('Alt+B'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('shortcuts_cheatsheet_search_field')),
        'Alt+B',
      );
      await tester.pumpAndSettle();

      expect(find.text('الانتقال لشاشة إنشاء فاتورة مشتريات جديدة'), findsOneWidget);
      expect(find.text('إتمام ودفع الفاتورة'), findsNothing);
    });

    testWidgets('ShortcutsConfigDialog hides admin-only groups from unpermitted cashier',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cAuth = _FakeAuthCubit(cashierUser);
      addTearDown(cAuth.close);
      CashierPermissionsService.notifier.value = const CashierPermissionsConfig(
        allowGoodsIntake: false,
        allowViewPurchases: false,
      );

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: cAuth,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: ShortcutsConfigDialog()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إتمام ودفع الفاتورة'), findsOneWidget);
      expect(find.text('إضافة صنف جديد فوراً'), findsNothing);
      expect(find.text('المشتريات وفواتير الموردين'), findsNothing);
    });
  });

  group('Task 35: MainLayout Global Quick Jumps & Hotkey Strip', () {
    testWidgets('Alt+A, Alt+R, Alt+B jump cleanly and update hotkey strip',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MainLayout(
                currentRoute: '/',
                child: Center(child: Text('الرئيسية')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // General strip advertises Alt+A, Alt+R, Alt+B
      expect(find.byKey(const Key('contextual_hotkey_strip_general')), findsOneWidget);
      expect(find.text('Alt+A إضافة صنف'), findsOneWidget);
      expect(find.text('Alt+R استلام شحنة'), findsOneWidget);
      expect(find.text('Alt+B فاتورة شراء'), findsOneWidget);

      // 1. Alt+B -> CreatePurchaseScreen + purchases hotkey strip
      await _sendCombo(tester, LogicalKeyboardKey.keyB, alt: true);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePurchaseScreen), findsOneWidget);
      expect(
        find.byKey(const Key('contextual_hotkey_strip_create_purchase')),
        findsOneWidget,
      );
      expect(find.text('Ctrl+S / F12 حفظ الفاتورة'), findsOneWidget);

      // 2. Alt+R -> BlindReceiveScreen + blind receive hotkey strip
      await _sendCombo(tester, LogicalKeyboardKey.keyR, alt: true);
      await tester.pumpAndSettle();
      expect(find.byType(BlindReceiveScreen), findsOneWidget);
      expect(
        find.byKey(const Key('contextual_hotkey_strip_blind_receive')),
        findsOneWidget,
      );
      expect(find.text('F2 تركيز الباركود'), findsOneWidget);

      // 3. Alt+A -> ProductListScreen + opens SimpleProductFormDialog immediately
      await _sendCombo(tester, LogicalKeyboardKey.keyA, alt: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ProductListScreen), findsOneWidget);
      expect(find.byType(SimpleProductFormDialog), findsOneWidget);
      expect(
        find.byKey(const Key('contextual_hotkey_strip_products')),
        findsOneWidget,
      );
      expect(find.text('Ctrl+N / F3 صنف جديد'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('Alt+A and Alt+B blocked for cashier without permission',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cAuth = _FakeAuthCubit(cashierUser);
      addTearDown(cAuth.close);
      CashierPermissionsService.notifier.value = const CashierPermissionsConfig(
        allowGoodsIntake: false,
        allowViewPurchases: false,
      );

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: cAuth,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: MainLayout(
                currentRoute: '/',
                child: Center(child: Text('الرئيسية')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alt+A إضافة صنف'), findsNothing);
      expect(find.text('Alt+R استلام شحنة'), findsNothing);
      expect(find.text('Alt+B فاتورة شراء'), findsNothing);

      await _sendCombo(tester, LogicalKeyboardKey.keyA, alt: true);
      await tester.pumpAndSettle();
      expect(find.byType(ProductListScreen), findsNothing);

      await _sendCombo(tester, LogicalKeyboardKey.keyB, alt: true);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePurchaseScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('Task 35: ProductListScreen & SimpleProductFormDialog Keyboard Flow', () {
    testWidgets('Ctrl+N / F3 opens form and F2 focuses search in ProductListScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ProductListScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // F2 focuses search field
      await _sendCombo(tester, LogicalKeyboardKey.f2);
      await tester.pump();
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('product_list_search_field')),
      );
      expect(searchField.focusNode?.hasFocus, isTrue);

      // Ctrl+N opens add product dialog
      await _sendCombo(tester, LogicalKeyboardKey.keyN, ctrl: true);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleProductFormDialog), findsOneWidget);

      // Esc closes dialog
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleProductFormDialog), findsNothing);

      // F3 also opens add product dialog
      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleProductFormDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('SimpleProductFormDialog saves on Ctrl+S and closes on submit',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => showDialog(
                      context: ctx,
                      builder: (_) => const SimpleProductFormDialog(),
                    ),
                    child: const Text('فتح'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();

      // Fill required fields
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'منتج بالكيبورد');
      await tester.enterText(fields.at(2), '50');
      await tester.enterText(fields.at(3), '80');
      await tester.enterText(fields.at(5), '10');
      await tester.pump();

      await _sendCombo(tester, LogicalKeyboardKey.keyS, ctrl: true);
      await tester.pumpAndSettle();

      expect(lastProductFormCubit?.submitCount, equals(1));
      expect(lastProductFormCubit?.lastSubmittedName, equals('منتج بالكيبورد'));
      expect(find.byType(SimpleProductFormDialog), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('Task 35: Purchases & BlindReceive Keyboard Flow', () {
    testWidgets('PurchasesScreen Ctrl+N opens CreatePurchaseScreen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: PurchasesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _sendCombo(tester, LogicalKeyboardKey.keyN, ctrl: true);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePurchaseScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('CreatePurchaseScreen F3 opens add variant dialog',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime(2025, 1, 1);
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-p',
              name: 'تصنيف المشتريات',
              branchId: 'branch-1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-1',
              name: 'صنف اختبار',
              categoryId: 'cat-p',
              branchId: 'branch-1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'var-1',
              productId: 'prod-1',
              sku: 'SKU-100',
              size: '-',
              color: '-',
              costPrice: 5000,
              sellPrice: 8000,
              branchId: 'branch-1',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CreatePurchaseScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('اختيار صنف للفاتورة'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('BlindReceiveScreen F2 focuses barcode and F3 opens ProductFormDialog',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: BlindReceiveScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _sendCombo(tester, LogicalKeyboardKey.f2);
      await tester.pump();
      final barcodeField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'مسح بالباركود (Scanner)',
        ),
      );
      expect(barcodeField.focusNode?.hasFocus, isTrue);

      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byType(ProductFormDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
