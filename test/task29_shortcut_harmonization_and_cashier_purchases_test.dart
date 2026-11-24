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
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
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

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  _FakeSettingsCubit(FeatureGate gate) : super(const SettingsState(features: {}));
  @override
  Future<void> start() async {
    emit(state.copyWith(
      features: {
        FeatureKeys.purchases: true,
        FeatureKeys.suppliers: true,
      },
      isLoading: false,
    ));
  }
  @override
  Future<String?> toggleFeature(String key, bool val, String userId) async {
    final updated = Map<String, bool>.from(state.features);
    updated[key] = val;
    emit(state.copyWith(features: updated));
    return null;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ShortcutSettingsService shortcutService;
  late AuthLocalDataSource authLocalDs;
  late AuthCubit authCubit;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    authLocalDs = _FakeAuthLocalDataSource();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);

    featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    shortcutService = ShortcutSettingsService(db);

    final adminUser = UserModel(
      id: 'admin_1',
      name: 'المدير',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    await authLocalDs.cacheUser(adminUser);
    authCubit = _FakeAuthCubit(adminUser);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ShortcutSettingsService>(shortcutService);
    sl.registerSingleton<AuthCubit>(authCubit);

    sl.registerFactory<PosCubit>(() => PosCubit(
          _FakeCreateSaleUseCase(),
          _FakeVariantRepo(),
          _FakeCategoryRepo(),
          _FakeProductRepo(),
          _FakePosRepo(),
        ));
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
    sl.registerFactory<SettingsCubit>(() => _FakeSettingsCubit(featureGate));

    AppBranding.apply(AppBrandingConfig.defaults);
    CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
    HotkeyStripService.isVisible.value = true;
  });

  tearDown(() async {
    await authCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 29: Universal Shortcut Harmonization & Hidden Shortcuts Documentation', () {
    test('F1 is universally mapped to openShortcuts and Alt+P opens POS', () {
      expect(ShortcutSettingsService.defaultShortcuts['openShortcuts'], equals('F1'));
      expect(ShortcutSettingsService.defaultShortcuts['openPos'], equals('Alt+P'));

      final actShortcuts = shortcutService.getActivator('openShortcuts');
      expect(actShortcuts.trigger, equals(LogicalKeyboardKey.f1));
      expect(actShortcuts.alt, isFalse);
      expect(actShortcuts.control, isFalse);

      final actPos = shortcutService.getActivator('openPos');
      expect(actPos.trigger, equals(LogicalKeyboardKey.keyP));
      expect(actPos.alt, isTrue);
      expect(actPos.control, isFalse);
    });

    test('All newly documented operational shortcuts exist in definitions', () {
      final defs = ShortcutSettingsService.definitions;

      final preOrdersDef = defs.firstWhere((d) => d.action == 'preOrders');
      expect(preOrdersDef.label, equals('الحجز المسبق والطلبات الخاصة'));
      expect(preOrdersDef.defaultCombo, equals('F7'));
      expect(preOrdersDef.category, equals('pos'));

      final reprintDef = defs.firstWhere((d) => d.action == 'reprintReceipt');
      expect(reprintDef.label, equals('إعادة طباعة آخر فاتورة'));
      expect(reprintDef.defaultCombo, equals('F9'));
      expect(reprintDef.category, equals('pos'));

      final navDef = defs.firstWhere((d) => d.action == 'gridNavigation');
      expect(navDef.label, equals('التنقل بالأسهم في شبكة المنتجات والإضافة بـ Enter'));
      expect(navDef.defaultCombo, equals('↑ ↓ ← →'));
      expect(navDef.category, equals('pos'));

      final escDef = defs.firstWhere((d) => d.action == 'cancelSelection');
      expect(escDef.label, equals('إلغاء التحديد أو الخروج من النوافذ'));
      expect(escDef.defaultCombo, equals('Esc'));
      expect(escDef.category, equals('pos'));
    });

    test('parseCombo parses Esc, Alt+P, and F1 accurately', () {
      final escAct = ShortcutSettingsService.parseCombo('Esc');
      expect(escAct.trigger, equals(LogicalKeyboardKey.escape));

      final altPAct = ShortcutSettingsService.parseCombo('Alt+P');
      expect(altPAct.trigger, equals(LogicalKeyboardKey.keyP));
      expect(altPAct.alt, isTrue);

      final f1Act = ShortcutSettingsService.parseCombo('F1');
      expect(f1Act.trigger, equals(LogicalKeyboardKey.f1));
    });
  });

  group('Task 29: Adaptive Hotkey Footer Strip Toggle', () {
    test('HotkeyStripService loads, toggles temporarily, and persists to app_meta', () async {
      // Default state
      expect(HotkeyStripService.current, isTrue);

      // Temporary toggle
      HotkeyStripService.toggleTemporary(false);
      expect(HotkeyStripService.current, isFalse);

      HotkeyStripService.toggleTemporary(true);
      expect(HotkeyStripService.current, isTrue);

      // Persist to app_meta via setVisible
      await HotkeyStripService.setVisible(featureGate, false, userId: 'admin_1');
      expect(HotkeyStripService.current, isFalse);

      final metaVal = await featureGate.getMeta(HotkeyStripService.metaKey);
      expect(metaVal, equals('0'));

      // Reload from FeatureGate
      await HotkeyStripService.loadFromFeatureGate(featureGate);
      expect(HotkeyStripService.current, isFalse);

      await HotkeyStripService.setVisible(featureGate, true, userId: 'admin_1');
      expect(HotkeyStripService.current, isTrue);
    });

    testWidgets('PosScreen hides hotkey strip when isVisible is false and collapse button toggles it', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      HotkeyStripService.isVisible.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Hotkey strip is visible initially
      expect(find.byKey(const Key('pos_hotkey_footer_strip')), findsOneWidget);
      expect(find.byKey(const Key('pos_collapse_hotkey_strip_btn')), findsOneWidget);

      // Tap collapse button
      await tester.tap(find.byKey(const Key('pos_collapse_hotkey_strip_btn')));
      await tester.pump();

      // Hotkey strip should be collapsed/hidden
      expect(find.byKey(const Key('pos_hotkey_footer_strip')), findsNothing);
      expect(HotkeyStripService.current, isFalse);

      // Re-enable
      HotkeyStripService.isVisible.value = true;
      await tester.pump();
      expect(find.byKey(const Key('pos_hotkey_footer_strip')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('SystemSettingsScreen allows toggling hotkey strip via switch', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      HotkeyStripService.isVisible.value = true;

      final adminUser = UserModel(
        id: 'admin_1',
        name: 'المدير',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );
      await authLocalDs.cacheUser(adminUser);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<SettingsCubit>(create: (_) => _FakeSettingsCubit(featureGate)),
            ],
            child: const SystemSettingsScreen(initialCategory: 'store'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Find switch
      final switchFinder = find.byKey(const Key('setting_show_hotkey_strip'));
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();
      expect(switchFinder, findsOneWidget);

      // Verify initial value is true
      final initialSwitch = tester.widget<SwitchListTile>(switchFinder);
      expect(initialSwitch.value, isTrue);

      // Toggle switch to false
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(HotkeyStripService.current, isFalse);
      final metaVal = await featureGate.getMeta('ui.show_bottom_hotkey_strip');
      expect(metaVal, equals('0'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 29: Cashier Purchases Permission', () {
    test('CashierPermissionsConfig handles allowViewPurchases flag correctly', () {
      const config = CashierPermissionsConfig();
      expect(config.allowViewPurchases, isFalse);

      final updated = config.copyWith(allowViewPurchases: true);
      expect(updated.allowViewPurchases, isTrue);

      final map = updated.toMap();
      expect(map['allowViewPurchases'], isTrue);

      final fromMap = CashierPermissionsConfig.fromMap(map);
      expect(fromMap.allowViewPurchases, isTrue);
    });

    testWidgets('MainLayout hides purchases from cashier when permission is false, and reveals it when true', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Enable purchases and suppliers in FeatureGate
      await featureGate.setFeatureEnabled(FeatureKeys.purchases, true, userId: 'system');
      await featureGate.setFeatureEnabled(FeatureKeys.suppliers, true, userId: 'system');

      // Cashier user (non-admin)
      final cashierUser = UserModel(
        id: 'cashier_1',
        name: 'كاشير الفرع',
        email: 'cashier@test.com',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      );
      await authLocalDs.cacheUser(cashierUser);

      // 1. Initially allowViewPurchases is false
      CashierPermissionsService.notifier.value =
          const CashierPermissionsConfig(allowViewPurchases: false);

      final cashierCubit = _FakeAuthCubit(cashierUser);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: cashierCubit,
            child: const MainLayout(
              currentRoute: '/dashboard',
              child: Scaffold(body: Text('لوحة الكاشير')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Sidebar should hide Purchases
      expect(find.text('المشتريات والموردين'), findsNothing);

      // 2. Grant allowViewPurchases = true
      CashierPermissionsService.notifier.value =
          const CashierPermissionsConfig(allowViewPurchases: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Sidebar should now reveal Purchases
      expect(find.text('المشتريات والموردين'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('SystemSettingsScreen allows toggling allowViewPurchases in cashier permissions card', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final adminUser = UserModel(
        id: 'admin_1',
        name: 'المدير',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );
      await authLocalDs.cacheUser(adminUser);

      CashierPermissionsService.notifier.value =
          const CashierPermissionsConfig(allowViewPurchases: false);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<SettingsCubit>(create: (_) => _FakeSettingsCubit(featureGate)),
            ],
            child: const SystemSettingsScreen(initialCategory: 'staff'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final permSwitchFinder = find.byKey(const Key('cashier_perm_allow_purchases'));
      expect(permSwitchFinder, findsOneWidget);

      final permSwitch = tester.widget<SwitchListTile>(permSwitchFinder);
      expect(permSwitch.value, isFalse);

      // Toggle switch to true
      await tester.tap(permSwitchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(CashierPermissionsService.current.allowViewPurchases, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 29.1: F1 Dialog Debounce/Singleton & Real-Time Cart Quantity Sync', () {
    testWidgets('ShortcutsConfigDialog.show opens only one dialog when invoked multiple times concurrently', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                // Call show multiple times in immediate succession
                ShortcutsConfigDialog.show(context);
                ShortcutsConfigDialog.show(context);
                ShortcutsConfigDialog.show(context);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ShortcutsConfigDialog), findsOneWidget);
      expect(ShortcutsConfigDialog.isOpen, isTrue);

      // Close the open dialog
      Navigator.of(tester.element(find.byType(ShortcutsConfigDialog))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ShortcutsConfigDialog), findsNothing);
      expect(ShortcutsConfigDialog.isOpen, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Editing cart quantity field and blurring (unfocus) applies new quantity immediately without Enter', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
      await tester.pump(const Duration(milliseconds: 400));

      final posCubit = tester.element(find.byType(Scaffold)).read<PosCubit>();
      final testVariant = VariantEntity(
        id: 'var_test_1',
        productId: 'prod_test_1',
        productCode: 'SHIRT-WHT-L',
        productName: 'قميص تجريبي',
        size: 'L',
        color: 'أبيض',
        salePrice: 10000,
        costPrice: 5000,
        quantity: 20,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      posCubit.addToCart(testVariant, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final qtyFieldFinder = find.byKey(const Key('cart_qty_input_var_test_1'));
      expect(qtyFieldFinder, findsOneWidget);
      expect(posCubit.state.cart.first.quantity, equals(1));

      // Enter 4 in the quantity field
      await tester.tap(qtyFieldFinder);
      await tester.pump();
      await tester.enterText(qtyFieldFinder, '4');
      await tester.pump();

      // Blur / unfocus (simulating tapping outside or losing focus)
      final focusNode = tester.widget<TextField>(qtyFieldFinder).focusNode!;
      focusNode.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Quantity must be committed to cubit state without Enter key
      expect(posCubit.state.cart.first.quantity, equals(4));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Entering Eastern Arabic digits (e.g. ٥) normalizes and updates quantity to 5 upon blur', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
      await tester.pump(const Duration(milliseconds: 400));

      final posCubit = tester.element(find.byType(Scaffold)).read<PosCubit>();
      final testVariant = VariantEntity(
        id: 'var_test_2',
        productId: 'prod_test_2',
        productCode: 'PANTS-BLK-32',
        productName: 'بنطلون تجريبي',
        size: '32',
        color: 'أسود',
        salePrice: 20000,
        costPrice: 10000,
        quantity: 15,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      posCubit.addToCart(testVariant, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final qtyFieldFinder = find.byKey(const Key('cart_qty_input_var_test_2'));
      expect(qtyFieldFinder, findsOneWidget);

      // Enter Eastern Arabic numeral '٥'
      await tester.tap(qtyFieldFinder);
      await tester.pump();
      await tester.enterText(qtyFieldFinder, '٥');
      await tester.pump();

      // Blur / unfocus
      final focusNode = tester.widget<TextField>(qtyFieldFinder).focusNode!;
      focusNode.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Eastern Arabic '٥' is normalized and committed as 5
      expect(posCubit.state.cart.firstWhere((i) => i.variantId == 'var_test_2').quantity, equals(5));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
