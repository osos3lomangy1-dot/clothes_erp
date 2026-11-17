import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
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

class _SpyPosCubit extends Cubit<PosState> implements PosCubit {
  bool clearCartCalled = false;
  bool checkoutCalled = false;

  _SpyPosCubit(super.initial);

  @override
  Future<void> init() async {}

  @override
  void clearCart() {
    clearCartCalled = true;
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
    return false;
  }

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

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late UserModel admin;
  late _SpyPosCubit spyPosCubit;

  const sampleCartItem = SaleItemEntity(
    variantId: 'v1',
    productId: 'p1',
    productName: 'بلوزة',
    color: 'أسود',
    size: 'M',
    price: 15000,
    quantity: 1,
  );

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    admin = UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'a@a.a',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final authDs = _FakeAuthDs()..setUser(admin);
    final tx = TxWriter(db);
    final branch = BranchProvider(db);
    gate = FeatureGate(db, authDs, tx, branch);
    spyPosCubit = _SpyPosCubit(const PosLoaded(cart: [sampleCartItem]));

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerFactory<PosCubit>(() => spyPosCubit);
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  testWidgets('POS shortcuts F2, F12, and Esc work globally even when no input is focused',
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
        home: BlocProvider<AuthCubit>.value(
          value: _FakeAuthCubit(admin),
          child: const PosScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Unfocus search field completely
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // 1. Press F2 -> search TextField gains focus!
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.focusNode?.hasFocus, isTrue);

    // 2. Press F12 -> triggers checkout!
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(spyPosCubit.checkoutCalled, isTrue);

    // 3. Press Esc -> clears cart!
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(spyPosCubit.clearCartCalled, isTrue);
    expect(spyPosCubit.state.cart, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
