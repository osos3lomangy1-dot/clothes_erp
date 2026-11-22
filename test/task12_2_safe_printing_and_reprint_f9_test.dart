import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:drift/native.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/repositories/invoices_repository.dart';
import 'package:clothes_erp/features/pos/domain/entities/payment_split.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_entity.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';

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
  bool checkoutCalled = false;

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
    return true;
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

class _FakeInvoicesRepository implements InvoicesRepository {
  List<InvoiceDetailsEntity> invoices = [];

  @override
  Future<Either<Failure, List<InvoiceDetailsEntity>>> getInvoices({
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? cashierId,
    String? paymentMethod,
    int limit = 100,
  }) async {
    return Right(invoices.take(limit).toList());
  }

  @override
  Future<Either<Failure, InvoiceDetailsEntity?>> getInvoiceById(String id) async {
    final match = invoices.where((i) => i.id == id).firstOrNull;
    return Right(match);
  }

  @override
  Future<Either<Failure, InvoiceDetailsEntity?>> getInvoiceByShortRef(String shortRef) async {
    final match = invoices.where((i) => i.shortRef == shortRef).firstOrNull;
    return Right(match);
  }
}

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late UserModel admin;
  late _SpyPosCubit spyPosCubit;
  late _FakeInvoicesRepository fakeInvoicesRepo;

  final sampleInvoice = InvoiceDetailsEntity(
    id: 'inv_test_001',
    shortRef: 'INV-1001',
    date: DateTime.now(),
    cashierId: 'cashier-1',
    cashierName: 'أحمد',
    subtotal: 15000,
    total: 15000,
    paymentMethod: 'cash',
    status: 'completed',
    items: const [
      InvoiceItemDetailsEntity(
        id: 'item_1',
        variantId: 'v1',
        productName: 'قميص رجالي',
        color: 'أبيض',
        size: 'L',
        qty: 1,
        price: 15000,
        lineTotal: 15000,
      ),
    ],
  );

  const sampleCartItem = SaleItemEntity(
    variantId: 'v1',
    productId: 'p1',
    productName: 'قميص رجالي',
    color: 'أبيض',
    size: 'L',
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
    fakeInvoicesRepo = _FakeInvoicesRepository();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<InvoicesRepository>(fakeInvoicesRepo);
    sl.registerFactory<PosCubit>(() => spyPosCubit);
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  group('Task 12.2 - Safe Printing Fallback & Quick Re-Print [F9] Tests', () {
    testWidgets('Header renders Re-Print button [F9] disabled when no prior invoice exists', (tester) async {
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

      final reprintButtonFinder = find.byKey(const Key('pos_reprint_last_invoice_button'));
      expect(reprintButtonFinder, findsOneWidget);

      final button = tester.widget<OutlinedButton>(reprintButtonFinder);
      expect(button.onPressed, isNull); // disabled

      expect(find.text('إعادة طباعة [F9]'), findsOneWidget);
      expect(find.byIcon(Icons.print_outlined), findsOneWidget);
    });

    testWidgets('Pressing [F9] without a previous invoice displays gentle warning', (tester) async {
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

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();

      expect(find.text('لا توجد فاتورة سابقة لإعادة طباعتها'), findsOneWidget);
    });

    testWidgets('When previous invoice exists, button is enabled and F9 triggers reprint successfully', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      fakeInvoicesRepo.invoices = [sampleInvoice];
      InvoiceDetailsEntity? printedInvoice;

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
            child: PosScreen(
              printReceiptOverride: (inv) async {
                printedInvoice = inv;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final reprintButtonFinder = find.byKey(const Key('pos_reprint_last_invoice_button'));
      expect(reprintButtonFinder, findsOneWidget);

      final button = tester.widget<OutlinedButton>(reprintButtonFinder);
      expect(button.onPressed, isNotNull); // enabled!

      // Press F9 shortcut -> triggers reprint
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();

      expect(printedInvoice, isNotNull);
      expect(printedInvoice?.id, sampleInvoice.id);
    });

    testWidgets('When printer fails, safe fallback message is displayed without crashing', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      fakeInvoicesRepo.invoices = [sampleInvoice];

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
            child: PosScreen(
              printReceiptOverride: (inv) async {
                throw Exception('Printer offline or paper jam');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger reprint via header button click
      final reprintButtonFinder = find.byKey(const Key('pos_reprint_last_invoice_button'));
      await tester.tap(reprintButtonFinder);
      await tester.pumpAndSettle();

      // Verify the calm fallback notice is shown
      expect(
        find.text('تم حفظ الفاتورة بنجاح. تعذر الاتصال بالطابعة، يمكنك إعادة الطباعة بالضغط على [F9] بعد التحقق من الورق والكابل.'),
        findsOneWidget,
      );
    });
  });
}
