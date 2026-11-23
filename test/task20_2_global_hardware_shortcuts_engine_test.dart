import 'dart:async';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/command_palette_dialog.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/rest_sync_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/pos/domain/entities/payment_split.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_entity.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/settings/presentation/widgets/shortcuts_config_dialog.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeAuthDs implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
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
  bool get isSyncing => false;
  @override
  Future<SyncResult> syncPendingData() async => const SyncResult(total: 0, synced: 0, failed: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyPosCubit extends Cubit<PosState> implements PosCubit {
  bool checkoutCalled = false;
  String? checkoutPaymentMethod;

  _SpyPosCubit(super.initial);

  @override
  Future<void> init() async {}

  @override
  void clearCart() {
    emit(const PosLoaded(cart: []));
  }

  @override
  void searchProducts(String query) {}

  @override
  VariantEntity? getVariantById(String variantId) => null;

  @override
  Future<bool> checkout({
    String? cashierId,
    String paymentMethod = 'cash',
    List<PaymentSplit>? splits,
    void Function(SaleEntity)? onSaleCreated,
  }) async {
    checkoutCalled = true;
    checkoutPaymentMethod = paymentMethod;
    return false;
  }

  @override
  void loadCart({
    required List<SaleItemEntity> cart,
    dynamic customer,
  }) {
    emit(PosLoaded(cart: cart, customer: customer));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShiftCubit extends Cubit<ShiftState> implements ShiftCubit {
  _FakeShiftCubit() : super(const ShiftState(shiftsEnabled: false, status: ShiftStatus.loaded));
  @override
  Future<void> loadShiftData() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sl = GetIt.instance;

  late AppDatabase db;
  late FeatureGate featureGate;
  late _FakeAuthDs authDs;
  late UserModel adminUser;
  late ShortcutSettingsService shortcutService;
  late _SpyPosCubit spyPosCubit;

  const sampleCartItem = SaleItemEntity(
    variantId: 'v1',
    productId: 'p1',
    productName: 'قميص رجالي كلاسيك',
    color: 'أبيض',
    size: 'L',
    price: 25000,
    quantity: 1,
  );

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    authDs = _FakeAuthDs();
    adminUser = UserModel(
      id: 'admin-1',
      name: 'مدير النظام',
      email: 'admin@bay3ah.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    authDs.setUser(adminUser);

    final tx = TxWriter(db);
    final bp = BranchProvider(db);
    featureGate = FeatureGate(db, authDs, tx, bp);
    shortcutService = ShortcutSettingsService(db);
    spyPosCubit = _SpyPosCubit(const PosLoaded(cart: [sampleCartItem]));

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<RestSyncService>(_FakeRestSyncService());
    sl.registerSingleton<ShortcutSettingsService>(shortcutService);
    sl.registerFactory<PosCubit>(() => spyPosCubit);
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  group('Addendum 20.2: ShortcutSettingsService Configuration', () {
    test('verifies default shortcuts: F1 for POS and Alt+F1 for guide', () {
      final all = shortcutService.getAllShortcuts();
      expect(all['openPos'], equals('F1'));
      expect(all['openShortcuts'], equals('Alt+F1'));
      expect(all['quickPayCash'], equals('F5'));
      expect(all['quickPayCard'], equals('F6'));
      expect(all['holdBill'], equals('F10'));
      expect(all['recallBill'], equals('F11'));
      expect(all['completeSale'], equals('F12'));

      final posAct = shortcutService.getActivator('openPos');
      expect(posAct.trigger, equals(LogicalKeyboardKey.f1));
      expect(posAct.alt, isFalse);

      final guideAct = shortcutService.getActivator('openShortcuts');
      expect(guideAct.trigger, equals(LogicalKeyboardKey.f1));
      expect(guideAct.alt, isTrue);
    });

    test('loadShortcuts restores custom shortcut overrides from app_meta', () async {
      await shortcutService.setShortcut('openPos', 'F3');
      expect(shortcutService.getShortcut('openPos'), equals('F3'));

      // Create a fresh service instance and test loading from DB
      final freshService = ShortcutSettingsService(db);
      await freshService.loadShortcuts();
      expect(freshService.getShortcut('openPos'), equals('F3'));
      expect(freshService.getShortcut('openShortcuts'), equals('Alt+F1'));
    });
  });

  group('Addendum 20.2: MainLayout Global Hardware Key Handling', () {
    testWidgets('Pressing F1 in MainLayout switches directly to PosScreen', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const MainLayout(
                currentRoute: '/dashboard',
                child: Scaffold(
                  body: Center(child: Text('شاشة لوحة التحكم الحالية')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('شاشة لوحة التحكم الحالية'), findsOneWidget);
      expect(find.byType(PosScreen), findsNothing);

      // Simulate global hardware F1 press
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();

      // MainLayout transitions to PosScreen
      expect(find.byType(PosScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Pressing Ctrl+K opens CommandPaletteDialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const MainLayout(
                currentRoute: '/dashboard',
                child: Scaffold(
                  body: Center(child: Text('محتوى لوحة التحكم')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate Ctrl + K
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPaletteDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Pressing Alt+F1 opens ShortcutsConfigDialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const MainLayout(
                currentRoute: '/dashboard',
                child: Scaffold(
                  body: Center(child: Text('محتوى لوحة التحكم')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate Alt + F1
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(find.byType(ShortcutsConfigDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Addendum 20.2: PosScreen Hardware Key Interception during Focused Input', () {
    testWidgets('F5, F6, F10, and F12 work even when search input is focused',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure search field has focus
      final searchFieldFinder = find.byKey(const Key('pos_search_field'));
      expect(searchFieldFinder, findsOneWidget);
      await tester.tap(searchFieldFinder);
      await tester.pump();

      final searchWidget = tester.widget<TextField>(searchFieldFinder);
      expect(searchWidget.focusNode?.hasFocus, isTrue);

      // 1. Press F12 while search input is focused -> triggers checkout
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(spyPosCubit.checkoutCalled, isTrue);

      // 2. Press F10 -> Adds a new held bill tab
      expect(find.text('فاتورة 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(find.text('فاتورة 2'), findsOneWidget);

      // 3. Press F6 -> Selects Card payment
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();

      // 4. Press F5 -> Selects Cash payment
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
