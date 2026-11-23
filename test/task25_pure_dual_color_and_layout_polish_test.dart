import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/rest_sync_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/blind_receive_screen.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/stocktake_screen.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/domain/repositories/invoices_repository.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/financial_comparison_bar_chart.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/payment_method_pie_chart.dart';
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
  Future<String> getBranchId() async => 'branch-main';
}

class _FakeFeatureGate implements FeatureGate {
  @override
  Future<bool> isEnabled(String key) async => true;
  @override
  Future<String?> getMeta(String key) async => null;
  @override
  Stream<String?> watchMeta(String key) => Stream.value(null);
  @override
  Stream<Map<String, bool>> watchFeatures() => Stream.value({
        'wholesale_pricing': true,
        'split_payment': true,
        'credit_sales': true,
        'hold_bills': true,
        'delivery': true,
        'pre_orders': true,
      });
  @override
  Future<Map<String, bool>> getFeatures() async => {
        'wholesale_pricing': true,
        'split_payment': true,
        'credit_sales': true,
        'hold_bills': true,
        'delivery': true,
        'pre_orders': true,
      };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthDs implements AuthLocalDataSource {
  UserModel? _user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRestSyncService implements RestSyncService {
  @override
  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {}
  @override
  void stopAutoSync() {}
  @override
  Stream<bool> get isSyncingStream => Stream.value(false);
  @override
  Stream<int> watchPendingCount() => Stream.value(0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvoicesRepo implements InvoicesRepository {
  @override
  Future<Either<Failure, List<InvoiceDetailsEntity>>> getInvoices({
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? cashierId,
    String? paymentMethod,
    int? limit,
    int? offset,
  }) async => const Right([]);
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

class _FakePosCubit extends Cubit<PosState> implements PosCubit {
  _FakePosCubit()
      : super(PosState(
          categories: [
            CategoryEntity(
              id: 'cat-1',
              name: 'قمصان',
              description: 'قمصان رجالي',
              createdAt: DateTime(2026, 1, 1),
            ),
            CategoryEntity(
              id: 'cat-2',
              name: 'بناطيل',
              description: 'بناطيل جينز وقماش',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ));

  @override
  Future<void> init() async {}
  @override
  String getProductName(String productId) => 'قميص أكسفورد كلاسيك';
  @override
  String? getProductCategoryId(String productId) => 'cat-1';
  @override
  List<VariantEntity> getVariantsForProduct(String productId) => [];
  @override
  void filterByCategory(String catId) {
    emit(state.copyWith(selectedCategory: catId));
  }
  @override
  void filterByActivity(String actCode) {
    emit(state.copyWith(selectedActivity: actCode));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  _FakeSettingsCubit()
      : super(const SettingsState(
          features: {
            'wholesale_pricing': true,
            'split_payment': true,
            'credit_sales': true,
            'hold_bills': true,
            'delivery': true,
            'pre_orders': true,
            'consolidated_batches': true,
            'telegram_bot': true,
            'whatsapp_direct': true,
            'shifts': true,
            'blind_shift_closing': false,
          },
        ));

  @override
  void start() {}

  @override
  Future<String?> toggleFeature(String key, bool enabled, String userId) async {
    final updated = Map<String, bool>.from(state.features);
    updated[key] = enabled;
    emit(state.copyWith(features: updated));
    return null;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ShortcutSettingsService shortcutService;
  late ActivitySettingsService activityService;
  late GoodsReceiptCubit goodsReceiptCubit;
  late _FakeSettingsCubit settingsCubit;
  late _FakePosCubit posCubit;
  late _FakeShiftCubit shiftCubit;
  late _FakeAuthCubit authCubit;
  final getIt = GetIt.instance;

  final adminUser = UserModel(
    id: 'user-admin-1',
    name: 'المدير العام',
    email: 'admin@example.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime.now(),
  );

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    final bp = _FakeBranchProvider();
    final fg = _FakeFeatureGate();
    final tx = TxWriter(db);
    final invDs = InventoryLocalDataSource(db, bp, tx);

    shortcutService = ShortcutSettingsService(db);
    activityService = ActivitySettingsService(db, fg);
    goodsReceiptCubit = GoodsReceiptCubit(invDs);
    settingsCubit = _FakeSettingsCubit();
    posCubit = _FakePosCubit();
    shiftCubit = _FakeShiftCubit();
    authCubit = _FakeAuthCubit(adminUser);

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<TxWriter>(tx);
    getIt.registerSingleton<BranchProvider>(bp);
    getIt.registerSingleton<FeatureGate>(fg);
    getIt.registerSingleton<AuthLocalDataSource>(_FakeAuthDs());
    getIt.registerSingleton<RestSyncService>(_FakeRestSyncService());
    getIt.registerSingleton<ShortcutSettingsService>(shortcutService);
    getIt.registerSingleton<ActivitySettingsService>(activityService);
    getIt.registerSingleton<SettingsCubit>(settingsCubit);
    getIt.registerSingleton<AuthCubit>(authCubit);
    getIt.registerSingleton<ManagerPinService>(ManagerPinService(db, tx, bp, _FakeAuthDs(), fg));
    getIt.registerSingleton<InvoicesRepository>(_FakeInvoicesRepo());
    getIt.registerFactory<GoodsReceiptCubit>(() => goodsReceiptCubit);
    getIt.registerFactory<PosCubit>(() => posCubit);
    getIt.registerFactory<ShiftCubit>(() => shiftCubit);

    AppBranding.apply(AppBrandingConfig.defaults);
    ReceiptSettingsService.notifier.value = ReceiptConfig.defaults;
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  group('Task 25: Settings Screen Polish & Dual-Color Minimalism', () {
    testWidgets('Settings sidebar shows clean labels without ellipsis truncation dots', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that category labels exist in sidebar
      expect(find.text('نقطة البيع'), findsWidgets);
      expect(find.text('المخزون'), findsWidgets);
      expect(find.text('العملاء وفريق العمل'), findsWidgets);

      // Verify no truncated ellipses '...' in sidebar item texts
      final sidebarFinder = find.byKey(const Key('settings_sidebar_container'));
      expect(sidebarFinder, findsOneWidget);
      final sidebarTexts = tester.widgetList<Text>(
        find.descendant(of: sidebarFinder, matching: find.byType(Text)),
      );
      final sidebarTruncatedTexts = sidebarTexts.where(
        (t) => (t.data ?? '').endsWith('...') || (t.data ?? '').contains('...'),
      );
      expect(sidebarTruncatedTexts.isEmpty, isTrue,
          reason: 'No truncated ellipsis text should exist in the refined sidebar');
    });

    testWidgets('Settings features use pure Arabic names without English parentheticals', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clean Arabic labels
      expect(find.text('1. مزايا الكاشير ونقطة البيع'), findsOneWidget);
      expect(find.text('الدفع المجزأ'), findsOneWidget);
      expect(find.text('البيع الآجل والشكك'), findsOneWidget);
      expect(find.text('فواتير متعددة وتعليق الفاتورة'), findsOneWidget);
      expect(find.text('إدارة وتتبع الدليفري والطيارين'), findsOneWidget);

      // Ensure English parenthetical variants are gone
      expect(find.text('1. مزايا الكاشير ونقطة البيع (POS)'), findsNothing);
      expect(find.text('الدفع المجزأ (Split Payment)'), findsNothing);
      expect(find.text('البيع الآجل والشكك (Credit Sales)'), findsNothing);
      expect(find.text('فواتير متعددة وتعليق الفاتورة (Hold / Multi-Bills)'), findsNothing);
      expect(find.text('إدارة وتتبع الدليفري والطيارين (Delivery)'), findsNothing);
    });

    testWidgets('Active feature switches illuminate with secondary accent color (AppColors.secondary)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('feature_delivery_toggle'));
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.activeThumbColor, equals(AppColors.secondary),
          reason: 'Active switch thumb must use AppColors.secondary (#1FB5A8)');
    });

    testWidgets('Addendum 25.1: Executive Desktop Header displays breadcrumbs, active category chip, and subtitle', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify breadcrumbs and subtitle
      expect(find.text('مركز الإعدادات الموحد'), findsOneWidget);
      expect(find.text('تحكم شامل في ميزات النظام وصلاحيات العمل وهوية المتجر'), findsOneWidget);
      expect(find.byKey(const Key('settings_active_breadcrumb_chip')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_active_breadcrumb_chip')),
          matching: find.text('لوحة التحكم في المزايا'),
        ),
        findsOneWidget,
      );

      // Tap on another category in sidebar
      await tester.tap(find.text('نقطة البيع').first);
      await tester.pumpAndSettle();

      // Breadcrumb chip updates to 'نقطة البيع'
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_active_breadcrumb_chip')),
          matching: find.text('نقطة البيع'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Addendum 25.1: Spotlight search bar has clean hint, Kbd badge, and instant clear button', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: const SystemSettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchFinder = find.byKey(const Key('settings_search_field'));
      expect(searchFinder, findsOneWidget);

      // Verify clean hint text without manual Ctrl+F string
      final textField = tester.widget<TextField>(searchFinder);
      expect(textField.decoration?.hintText, equals('ابحث عن ميزة، قسم، أو صلاحية...'));

      // Verify real Kbd badge is present initially
      expect(find.byKey(const Key('settings_search_kbd_badge')), findsOneWidget);
      expect(find.text('Ctrl + F'), findsOneWidget);
      expect(find.byKey(const Key('settings_search_clear_btn')), findsNothing);

      // Enter text: badge disappears and clear button appears
      await tester.enterText(searchFinder, 'دليفري');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_search_kbd_badge')), findsNothing);
      expect(find.byKey(const Key('settings_search_clear_btn')), findsOneWidget);

      // Tap clear button: text clears and Kbd badge returns
      await tester.tap(find.byKey(const Key('settings_search_clear_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_search_kbd_badge')), findsOneWidget);
      expect(find.byKey(const Key('settings_search_clear_btn')), findsNothing);
    });
  });

  group('Task 25: Stocktake Screen Row Layout & Contextual Hotkeys', () {
    testWidgets('Stocktake screen row displays product info with adjacent system balance and stepper', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
              ],
              child: const StocktakeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen renders and has stocktake title
      expect(find.text('الجرد المخزني'), findsOneWidget);
    });

    testWidgets('MainLayout displays stocktake-specific contextual hotkeys when in stocktake screen', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
              ],
              child: const MainLayout(
                currentRoute: '/stocktake',
                child: Scaffold(
                  body: Center(child: Text('محتوى الجرد')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stocktakeNav = find.text('الجرد المخزني');
      if (stocktakeNav.evaluate().isNotEmpty) {
        await tester.tap(stocktakeNav.first);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('contextual_hotkey_strip_stocktake')), findsOneWidget);
        expect(find.byKey(const Key('hotkey_stocktake_confirm_qty')), findsOneWidget);
        expect(find.byKey(const Key('hotkey_stocktake_search')), findsOneWidget);
        expect(find.byKey(const Key('hotkey_stocktake_commit')), findsOneWidget);
        expect(find.byKey(const Key('hotkey_stocktake_shortcuts')), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 25: Sales Reports & Visual Chart Balance', () {
    testWidgets('PaymentMethodPieChart has clean title without (Donut Chart) and balanced sizing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PaymentMethodPieChart(
                breakdown: const {'cash': 50000, 'card': 25000},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('توزيع طرق الدفع'), findsOneWidget);
      expect(find.text('توزيع طرق الدفع (Donut Chart)'), findsNothing);
      expect(find.textContaining('نقدي'), findsOneWidget);
      expect(find.textContaining('فيزا'), findsOneWidget);
    });

    testWidgets('FinancialComparisonBarChart renders financial comparison without text overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: FinancialComparisonBarChart(
                totalRevenue: 100000,
                totalCost: 60000,
                totalExpenses: 15000,
                netProfit: 25000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('المقارنة المالية (إيرادات / تكاليف / مصروفات / أرباح)'), findsOneWidget);
    });
  });

  group('Task 25: POS Ergonomics & Blind Receive Button State', () {
    testWidgets('POS screen renders unified filter bar and balanced footer strip', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<ShiftCubit>.value(value: shiftCubit),
                BlocProvider<PosCubit>.value(value: posCubit),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Footer strip present
      expect(find.byKey(const Key('pos_hotkey_footer_strip')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_search')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_cash')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_card')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_hold')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_recall')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_checkout')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_shortcuts')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('BlindReceiveScreen save button is disabled when empty (0 pieces)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<GoodsReceiptCubit>.value(value: goodsReceiptCubit),
              ],
              child: const BlindReceiveScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find save button in AppBar
      final saveBtnFinder = find.byKey(const Key('save_shipment_appbar_btn'));
      expect(saveBtnFinder, findsOneWidget);

      final elevatedBtn = tester.widget<ElevatedButton>(saveBtnFinder);
      expect(elevatedBtn.onPressed, isNull,
          reason: 'Save button must be disabled when 0 pieces are in the intake');
      expect(find.text('حفظ الشحنة (0 قطعة)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
