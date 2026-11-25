import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
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
import 'package:clothes_erp/features/customers/data/services/customer_ledger_service.dart';
import 'package:clothes_erp/features/customers/presentation/cubits/customer_cubit.dart';
import 'package:clothes_erp/features/customers/presentation/screens/customer_screen.dart';
import 'package:clothes_erp/features/expenses/domain/entities/expense_entity.dart';
import 'package:clothes_erp/features/expenses/presentation/cubits/expenses_cubit.dart';
import 'package:clothes_erp/features/expenses/presentation/cubits/expenses_state.dart';
import 'package:clothes_erp/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_state.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_state.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_list_screen.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/purchases_screen.dart';
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
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductCubit extends Cubit<ProductState> implements ProductCubit {
  _FakeProductCubit() : super(const ProductLoaded([]));
  @override
  Future<void> getProducts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryCubit extends Cubit<CategoryState> implements CategoryCubit {
  _FakeCategoryCubit() : super(const CategoryLoaded([]));
  @override
  Future<void> getCategories() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductFormCubit extends Cubit<ProductFormState>
    implements ProductFormCubit {
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
  Future<void> init(ProductEntity? product) async {}
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

class _FakeCustomerLedgerService implements CustomerLedgerService {
  @override
  Future<Map<String, CustomerFinancialSummary>> getAllCustomerSummaries() async =>
      const {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerCubit extends Cubit<CustomerState> implements CustomerCubit {
  _FakeCustomerCubit() : super(const CustomerState(status: CustomerStatus.success));
  @override
  Future<void> loadCustomers({String? search}) async {}
  @override
  void searchCustomers(String query) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExpensesCubit extends Cubit<ExpensesState> implements ExpensesCubit {
  _FakeExpensesCubit()
      : super(const ExpensesState(status: ExpensesStatus.loaded, expenses: <ExpenseEntity>[]));
  @override
  Future<void> loadExpenses({
    DateTime? from,
    DateTime? to,
    String? category,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyPosCubit extends Cubit<PosState> implements PosCubit {
  final Map<String, VariantEntity> variantsById;

  _SpyPosCubit(super.initial, {this.variantsById = const {}});

  @override
  Future<void> init() async {}

  @override
  void searchProducts(String query) {}

  @override
  VariantEntity? getVariantById(String variantId) => variantsById[variantId];

  @override
  String? getProductCategoryId(String productId) => null;

  @override
  List<VariantEntity> getVariantsForProduct(String productId) =>
      variantsById.values.where((v) => v.productId == productId).toList();

  @override
  void increaseQty(String variantId, {bool? isReturn}) {
    final updated = state.cart.map((it) {
      if (it.variantId == variantId && (isReturn == null || it.isReturn == isReturn)) {
        return it.copyWith(quantity: it.quantity + 1);
      }
      return it;
    }).toList();
    emit(PosLoaded(
      filteredVariants: state.filteredVariants,
      cart: updated,
    ));
  }

  @override
  void decreaseQty(String variantId, {bool? isReturn}) {
    final List<SaleItemEntity> updated = [];
    for (final it in state.cart) {
      if (it.variantId == variantId && (isReturn == null || it.isReturn == isReturn)) {
        if (it.quantity > 1) {
          updated.add(it.copyWith(quantity: it.quantity - 1));
        }
      } else {
        updated.add(it);
      }
    }
    emit(PosLoaded(
      filteredVariants: state.filteredVariants,
      cart: updated,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _sendKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late _FakeAuthCubit authCubit;
  late UserModel adminUser;
  late UserModel cashierUser;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final bp = _FakeBranchProvider();
    final tx = TxWriter(db);
    final authDs = _FakeAuthDs();
    adminUser = UserModel(
      id: 'admin_1',
      name: 'المدير',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2025, 1, 1),
    );
    cashierUser = UserModel(
      id: 'cashier_1',
      name: 'كاشير',
      email: 'cashier@test.com',
      role: 'cashier',
      isActive: true,
      createdAt: DateTime(2025, 1, 1),
    );
    await authDs.cacheUser(adminUser);

    featureGate = FeatureGate(db, authDs, tx, bp);
    await featureGate.setMeta(RetailSector.metaKey, RetailSector.supermarket,
        userId: 'admin_1');
    authCubit = _FakeAuthCubit(adminUser);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ShortcutSettingsService>(ShortcutSettingsService(db));
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<ProductRepository>(_FakeProductRepo());
    sl.registerSingleton<CategoryRepository>(_FakeCategoryRepo());

    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
    sl.registerFactory<ProductCubit>(() => _FakeProductCubit());
    sl.registerFactory<CategoryCubit>(() => _FakeCategoryCubit());
    sl.registerFactory<ProductFormCubit>(() => _FakeProductFormCubit());
    sl.registerFactory<PurchasesCubit>(() => _FakePurchasesCubit());
    sl.registerFactory<SuppliersCubit>(() => _FakeSuppliersCubit());
    sl.registerFactory<GoodsReceiptCubit>(
      () => GoodsReceiptCubit(InventoryLocalDataSource(db, bp, tx)),
    );
    sl.registerFactory<CustomerCubit>(() => _FakeCustomerCubit());
    sl.registerFactory<ExpensesCubit>(() => _FakeExpensesCubit());

    CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
  });

  tearDown(() async {
    await authCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Numpad (+) Add-New Shortcuts across Screens', () {
    testWidgets('ProductListScreen Numpad+ opens form only when search not focused',
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

      // Numpad+ when focus is NOT in search opens dialog
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleProductFormDialog), findsOneWidget);

      // Esc closes dialog
      await _sendKey(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleProductFormDialog), findsNothing);

      // Focus search field -> Numpad+ must NOT open dialog
      await tester.tap(find.byKey(const Key('product_list_search_field')));
      await tester.pump();
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleProductFormDialog), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('PurchasesScreen Numpad+ opens CreatePurchaseScreen',
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

      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePurchaseScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('CustomerScreen Numpad+ opens dialog only when permitted & not typing',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CustomerScreen(ledgerOverride: _FakeCustomerLedgerService()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Numpad+ when search NOT focused -> opens dialog
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsOneWidget);

      await _sendKey(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsNothing);

      // Focus search -> Numpad+ ignored
      await tester.tap(find.byKey(const Key('customer_search_field')));
      await tester.pump();
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsNothing);

      // Unpermitted cashier -> Numpad+ blocked
      final cAuth = _FakeAuthCubit(cashierUser);
      addTearDown(cAuth.close);
      CashierPermissionsService.notifier.value =
          const CashierPermissionsConfig(allowManageCustomers: false);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: cAuth,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CustomerScreen(
                key: const ValueKey('cashier_cust'),
                ledgerOverride: _FakeCustomerLedgerService(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('ExpensesScreen Numpad+ opens dialog only when permitted & not typing',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ExpensesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_expense_btn')), findsOneWidget);

      await _sendKey(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_expense_btn')), findsNothing);

      await tester.tap(find.byKey(const Key('expenses_search_field')));
      await tester.pump();
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_expense_btn')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('PosScreen Numpad (+) and (-) Cart Quantity Shortcuts', () {
    testWidgets('Numpad+ / Numpad- adjust last cart item respecting stock & text focus',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime(2025, 1, 1);
      final v1 = VariantEntity(
        id: 'v1',
        productId: 'p1',
        productName: 'قميص',
        size: 'L',
        color: 'أبيض',
        productCode: 'SKU-1',
        costPrice: 5000,
        salePrice: 10000,
        quantity: 5,
        minStock: 1,
        createdAt: now,
      );
      final v2 = VariantEntity(
        id: 'v2',
        productId: 'p2',
        productName: 'بنطلون',
        size: '42',
        color: 'أزرق',
        productCode: 'SKU-2',
        costPrice: 8000,
        salePrice: 15000,
        quantity: 2,
        minStock: 1,
        createdAt: now,
      );

      final posCubit = _SpyPosCubit(
        const PosLoaded(
          cart: [
            SaleItemEntity(
              variantId: 'v1',
              productId: 'p1',
              productName: 'قميص',
              size: 'L',
              color: 'أبيض',
              price: 10000,
              quantity: 1,
            ),
            SaleItemEntity(
              variantId: 'v2',
              productId: 'p2',
              productName: 'بنطلون',
              size: '42',
              color: 'أزرق',
              price: 15000,
              quantity: 1,
            ),
          ],
        ),
        variantsById: {'v1': v1, 'v2': v2},
      );
      GetIt.instance.registerFactory<PosCubit>(() => posCubit);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Search bar gets autofocus on start -> Numpad+ must NOT modify cart
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pump();
      expect(posCubit.state.cart.last.quantity, equals(1));

      // Unfocus search completely -> now focus is NOT inside any text field
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // 2. Numpad+ increments last item (v2) from 1 -> 2
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pump();
      var cart = posCubit.state.cart;
      expect(cart.length, equals(2));
      expect(cart[0].quantity, equals(1)); // v1 unchanged
      expect(cart[1].quantity, equals(2)); // v2 incremented

      // 3. Numpad+ again respects maxStock (2) -> stays 2 and notifies user
      await _sendKey(tester, LogicalKeyboardKey.numpadAdd);
      await tester.pump();
      cart = posCubit.state.cart;
      expect(cart[1].quantity, equals(2));
      expect(find.text('الحد الأقصى المتاح في المخزون (2)'), findsOneWidget);

      // 4. Numpad- decrements last item (v2) from 2 -> 1
      await _sendKey(tester, LogicalKeyboardKey.numpadSubtract);
      await tester.pump();
      cart = posCubit.state.cart;
      expect(cart.length, equals(2));
      expect(cart[1].quantity, equals(1));

      // 5. Numpad- again removes v2 (qty -> 0), leaving v1
      await _sendKey(tester, LogicalKeyboardKey.numpadSubtract);
      await tester.pump();
      cart = posCubit.state.cart;
      expect(cart.length, equals(1));
      expect(cart[0].variantId, equals('v1'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
