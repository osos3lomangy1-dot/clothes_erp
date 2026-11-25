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
import 'package:clothes_erp/features/customers/data/services/customer_ledger_service.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/customers/presentation/cubits/customer_cubit.dart';
import 'package:clothes_erp/features/customers/presentation/screens/customer_screen.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_state.dart';
import 'package:clothes_erp/features/expenses/domain/entities/expense_entity.dart';
import 'package:clothes_erp/features/expenses/presentation/cubits/expenses_cubit.dart';
import 'package:clothes_erp/features/expenses/presentation/cubits/expenses_state.dart';
import 'package:clothes_erp/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/blind_receive_screen.dart';
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
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
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
  final List<CustomerEntity> added = [];
  String lastSearch = '';

  _FakeCustomerCubit()
      : super(
          CustomerState(
            status: CustomerStatus.success,
            customers: [
              CustomerEntity(
                id: 'c-1',
                name: 'أحمد محمود',
                phone: '01011111111',
                loyaltyPoints: 10,
                createdAt: DateTime(2025, 1, 1),
              ),
            ],
          ),
        );

  @override
  Future<void> loadCustomers({String? search}) async {}

  @override
  void searchCustomers(String query) {
    lastSearch = query;
    emit(state.copyWith(searchQuery: query));
  }

  @override
  Future<bool> addCustomer(CustomerEntity customer) async {
    added.add(customer);
    emit(state.copyWith(
      status: CustomerStatus.success,
      customers: [...state.customers, customer.copyWith(id: 'c-${added.length + 1}')],
    ));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExpensesCubit extends Cubit<ExpensesState> implements ExpensesCubit {
  final List<Map<String, dynamic>> added = [];

  _FakeExpensesCubit()
      : super(
          ExpensesState(
            status: ExpensesStatus.loaded,
            expenses: [
              ExpenseEntity(
                id: 'e-1',
                branchId: 'branch-1',
                category: 'كهرباء ومرافق',
                amount: 15000,
                note: 'فاتورة يناير',
                expenseDate: DateTime(2025, 1, 10),
                userId: 'admin',
                createdAt: DateTime(2025, 1, 10),
              ),
              ExpenseEntity(
                id: 'e-2',
                branchId: 'branch-1',
                category: 'إيجار المحل',
                amount: 500000,
                note: 'إيجار شهر فبراير',
                expenseDate: DateTime(2025, 2, 1),
                userId: 'admin',
                createdAt: DateTime(2025, 2, 1),
              ),
            ],
            totalAmount: 515000,
          ),
        );

  @override
  Future<void> loadExpenses({
    DateTime? from,
    DateTime? to,
    String? category,
  }) async {}

  @override
  Future<bool> addExpense({
    required String category,
    required int amount,
    String? note,
    required DateTime expenseDate,
    required String userId,
  }) async {
    added.add({'category': category, 'amount': amount, 'note': note});
    final exp = ExpenseEntity(
      id: 'e-${added.length + 10}',
      branchId: 'branch-1',
      category: category,
      amount: amount,
      note: note,
      expenseDate: expenseDate,
      userId: userId,
      createdAt: DateTime.now(),
    );
    emit(state.copyWith(
      status: ExpensesStatus.loaded,
      expenses: [...state.expenses, exp],
      totalAmount: state.totalAmount + amount,
    ));
    return true;
  }

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
  _FakeCustomerCubit? lastCustomerCubit;
  _FakeExpensesCubit? lastExpensesCubit;
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
    lastCustomerCubit = null;
    lastExpensesCubit = null;

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
    sl.registerFactory<PurchasesCubit>(() => _FakePurchasesCubit());
    sl.registerFactory<SuppliersCubit>(() => _FakeSuppliersCubit());
    sl.registerFactory<GoodsReceiptCubit>(
      () => GoodsReceiptCubit(InventoryLocalDataSource(db, branchProvider, txWriter)),
    );
    sl.registerFactory<CustomerCubit>(() {
      final c = _FakeCustomerCubit();
      lastCustomerCubit = c;
      return c;
    });
    sl.registerFactory<ExpensesCubit>(() {
      final e = _FakeExpensesCubit();
      lastExpensesCubit = e;
      return e;
    });

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

  group('Smart Esc across ProductListScreen, BlindReceiveScreen, CreatePurchaseScreen', () {
    testWidgets('ProductListScreen Esc clears search first, then pops page',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(builder: (_) => const ProductListScreen()),
                    ),
                    child: const Text('افتح المنتجات'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('افتح المنتجات'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductListScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('product_list_search_field')),
        'بنطلون',
      );
      await tester.pump();
      expect(find.text('بنطلون'), findsOneWidget);

      // 1st Esc clears search only
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProductListScreen), findsOneWidget);
      expect(find.text('بنطلون'), findsNothing);

      // 2nd Esc pops page
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProductListScreen), findsNothing);
      expect(find.text('افتح المنتجات'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('CreatePurchaseScreen Esc backs immediately when empty, confirms when dirty',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int backCount = 0;

      // Case 1: empty invoice -> immediate onBack
      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CreatePurchaseScreen(onBack: () => backCount++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(backCount, equals(1));
      expect(find.text('تأكيد الرجوع'), findsNothing);

      // Case 2: dirty invoice -> asks confirmation
      backCount = 0;
      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CreatePurchaseScreen(
                key: const ValueKey('dirty_purchase'),
                onBack: () => backCount++,
                initialItems: const [
                  PurchaseInitialItem(
                    variantId: 'v-1',
                    productName: 'صنف 1',
                    sku: 'SKU-1',
                    color: '-',
                    size: '-',
                    qty: 2,
                    costPricePounds: 50,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('تأكيد الرجوع'), findsOneWidget);
      expect(backCount, equals(0));

      await tester.tap(find.byKey(const Key('confirm_discard_esc_btn')));
      await tester.pumpAndSettle();
      expect(backCount, equals(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('BlindReceiveScreen Esc backs immediately when empty, confirms when dirty',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime(2025, 1, 1);
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              name: 'تصنيف',
              branchId: 'branch-1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p-1',
              name: 'تيشيرت',
              categoryId: 'cat-1',
              branchId: 'branch-1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v-1',
              productId: 'p-1',
              sku: 'BR-100',
              size: 'L',
              color: 'أسود',
              costPrice: 10000,
              sellPrice: 15000,
              branchId: 'branch-1',
              createdAt: now,
              updatedAt: now,
            ),
          );

      int backCount = 0;

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: BlindReceiveScreen(onBack: () => backCount++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty -> immediate back
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(backCount, equals(1));

      // Scan barcode so _lines is non-empty
      backCount = 0;
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'مسح بالباركود (Scanner)',
        ),
        'BR-100',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('تأكيد الرجوع'), findsOneWidget);
      expect(backCount, equals(0));

      await tester.tap(find.byKey(const Key('confirm_discard_esc_btn')));
      await tester.pumpAndSettle();
      expect(backCount, equals(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('Customers Screen F2 / F3 / Ctrl+S / F12 / Esc', () {
    testWidgets('F2 focuses search, F3 opens dialog, F12 saves, Esc clears/pops',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => CustomerScreen(
                          ledgerOverride: _FakeCustomerLedgerService(),
                        ),
                      ),
                    ),
                    child: const Text('فتح العملاء'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('فتح العملاء'));
      await tester.pumpAndSettle();

      // F2 focuses search
      await _sendCombo(tester, LogicalKeyboardKey.f2);
      await tester.pump();
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('customer_search_field')),
      );
      expect(searchField.focusNode?.hasFocus, isTrue);

      // F3 opens Add Customer dialog
      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.text('إضافة عميل جديد'), findsNWidgets(2)); // button + dialog title

      // Esc closes dialog without saving
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsNothing);
      expect(lastCustomerCubit?.added, isEmpty);

      // Re-open with F3, fill fields, save with F12
      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), 'عميل كيبورد');
      await tester.enterText(dialogFields.at(1), '01099998888');
      await tester.pump();

      await _sendCombo(tester, LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(lastCustomerCubit?.added.length, equals(1));
      expect(lastCustomerCubit?.added.first.name, equals('عميل كيبورد'));
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsNothing);

      // Smart Esc clears search first, then pops screen
      await tester.enterText(find.byKey(const Key('customer_search_field')), 'عميل');
      await tester.pump();
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(lastCustomerCubit?.lastSearch, equals(''));
      expect(find.byType(CustomerScreen), findsOneWidget);

      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CustomerScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('Cashier without allowManageCustomers cannot open dialog via F3',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
              child: CustomerScreen(ledgerOverride: _FakeCustomerLedgerService()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customer_dialog_save_btn')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('Expenses Screen F2 / F3 / Ctrl+S / F12 / Esc', () {
    testWidgets('F2 focuses search and filters, F3 opens dialog, Ctrl+S saves, Esc clears/pops',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                    ),
                    child: const Text('فتح المصروفات'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('فتح المصروفات'));
      await tester.pumpAndSettle();

      // F2 focuses search & filtering works
      await _sendCombo(tester, LogicalKeyboardKey.f2);
      await tester.pump();
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('expenses_search_field')),
      );
      expect(searchField.focusNode?.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('expenses_search_field')),
        'فبراير',
      );
      await tester.pump();
      expect(find.text('إيجار شهر فبراير'), findsOneWidget);
      expect(find.text('فاتورة يناير'), findsNothing);

      // 1st Esc clears search and restores all items
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('فاتورة يناير'), findsOneWidget);
      expect(find.byType(ExpensesScreen), findsOneWidget);

      // F3 opens Add Expense dialog
      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_expense_btn')), findsOneWidget);

      // Esc closes dialog without saving
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_expense_btn')), findsNothing);
      expect(lastExpensesCubit?.added, isEmpty);

      // Re-open with F3 and save with Ctrl+S
      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      final amountField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(amountField.at(0), '250');
      await tester.pump();

      await _sendCombo(tester, LogicalKeyboardKey.keyS, ctrl: true);
      await tester.pumpAndSettle();
      expect(lastExpensesCubit?.added.length, equals(1));
      expect(lastExpensesCubit?.added.first['amount'], equals(25000));
      expect(find.byKey(const Key('save_expense_btn')), findsNothing);

      // Esc pops screen
      await _sendCombo(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ExpensesScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('Cashier without allowCashExpenses cannot open dialog via F3',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cAuth = _FakeAuthCubit(cashierUser);
      addTearDown(cAuth.close);
      CashierPermissionsService.notifier.value =
          const CashierPermissionsConfig(allowCashExpenses: false);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: cAuth,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ExpensesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _sendCombo(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save_expense_btn')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('MainLayout Esc badge & F1 Cheatsheet updates', () {
    testWidgets('MainLayout shows unified Esc badge on hotkey strip',
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

      expect(find.text('Esc إلغاء / رجوع'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('ShortcutsConfigDialog Cheatsheet includes Customers, Expenses & Smart Esc',
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

      await tester.enterText(
        find.byKey(const Key('shortcuts_cheatsheet_search_field')),
        'العملاء',
      );
      await tester.pumpAndSettle();

      expect(find.text('العملاء والمصروفات'), findsOneWidget);
      expect(find.text('التركيز على بحث العملاء'), findsOneWidget);
      expect(find.text('فتح نافذة تسجيل مصروف جديد'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
