import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/domain/repositories/invoices_repository.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
}

class _FakeFeatureGate implements FeatureGate {
  final Map<String, String> _meta = {};

  @override
  Future<bool> isEnabled(String key) async => true;

  @override
  Future<String?> getMeta(String key) async => _meta[key];

  @override
  Stream<Map<String, bool>> watchFeatures() => Stream.value({});

  @override
  Future<void> setMeta(String key, String value, {bool audit = true, required String userId}) async {
    _meta[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepo implements VariantRepository {
  List<VariantEntity> variants = [];
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() => Stream.value(Right(variants));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  List<ProductEntity> products = [];
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async => Right(products);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  List<CategoryEntity> categories = [];
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async => Right(categories);

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

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  final UserModel user;
  _FakeAuthCubit(this.user) : super(AuthAuthenticated(user));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeFeatureGate featureGate;
  late UserModel adminUser;
  late _FakeAuthCubit authCubit;
  late _FakeVariantRepo variantRepo;
  late _FakeProductRepo productRepo;
  late _FakeCategoryRepo categoryRepo;
  late PosRepository posRepo;
  late CreateSaleUseCase createSaleUseCase;
  late PosCubit posCubit;

  final variantBuy450 = VariantEntity(
    id: 'v-buy-450',
    productId: 'prod-shirt',
    productCode: 'SH-001',
    color: 'أزرق',
    size: 'L',
    quantity: 10,
    costPrice: 25000,
    salePrice: 45000, // 450 EGP
    minStock: 2,
    createdAt: DateTime.now(),
    productName: 'قميص كاجوال فاخر',
  );

  final variantReturn300 = VariantEntity(
    id: 'v-ret-300',
    productId: 'prod-tshirt',
    productCode: 'TS-001',
    color: 'أبيض',
    size: 'M',
    quantity: 5,
    costPrice: 15000,
    salePrice: 30000, // 300 EGP
    minStock: 1,
    createdAt: DateTime.now(),
    productName: 'تيشيرت قطن أصلي',
  );

  final variantReturn400 = VariantEntity(
    id: 'v-ret-400',
    productId: 'prod-pants',
    productCode: 'PT-001',
    color: 'رمادي',
    size: '34',
    quantity: 8,
    costPrice: 20000,
    salePrice: 40000, // 400 EGP
    minStock: 1,
    createdAt: DateTime.now(),
    productName: 'بنطلون جينز',
  );

  final variantBuy300 = VariantEntity(
    id: 'v-buy-300',
    productId: 'prod-polo',
    productCode: 'PL-001',
    color: 'كحلي',
    size: 'XL',
    quantity: 12,
    costPrice: 15000,
    salePrice: 30000, // 300 EGP
    minStock: 2,
    createdAt: DateTime.now(),
    productName: 'بولو صيفي',
  );

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    featureGate = _FakeFeatureGate();

    adminUser = UserModel(
      id: 'cashier_user_1',
      name: 'كاشير التجربة',
      email: 'cashier@bay3ah.com',
      role: 'cashier',
      isActive: true,
      createdAt: DateTime.now(),
    );
    authCubit = _FakeAuthCubit(adminUser);

    final inventory = InventoryLocalDataSource(db, branchProvider, txWriter);
    final posLocalDs = PosLocalDataSource(db, branchProvider, txWriter, inventory);
    posRepo = PosRepositoryImpl(posLocalDs, featureGate);
    createSaleUseCase = CreateSaleUseCase(posRepo);

    variantRepo = _FakeVariantRepo();
    variantRepo.variants = [variantBuy450, variantReturn300, variantReturn400, variantBuy300];

    productRepo = _FakeProductRepo();
    productRepo.products = [
      ProductEntity(
        id: 'prod-shirt',
        name: 'قميص كاجوال فاخر',
        description: 'قميص قطن',
        categoryId: 'cat-shirts',
        categoryName: 'قمصان',
        createdAt: DateTime.now(),
      ),
      ProductEntity(
        id: 'prod-tshirt',
        name: 'تيشيرت قطن أصلي',
        description: 'تيشيرت صيفي',
        categoryId: 'cat-tshirts',
        categoryName: 'تيشيرتات',
        createdAt: DateTime.now(),
      ),
    ];
    categoryRepo = _FakeCategoryRepo();

    posCubit = PosCubit(
      createSaleUseCase,
      variantRepo,
      categoryRepo,
      productRepo,
      posRepo,
    );
    posCubit.init();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<InvoicesRepository>(_FakeInvoicesRepo());
    sl.registerFactory<PosCubit>(() => posCubit);
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());

    AppBranding.apply(AppBrandingConfig.defaults);
    ReceiptSettingsService.notifier.value = ReceiptConfig.defaults;
  });

  tearDown(() async {
    if (!posCubit.isClosed) {
      await posCubit.close();
    }
    if (!authCubit.isClosed) {
      await authCubit.close();
    }
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 28: Fast In-Cart Item Exchange Flow & Net Settlement (PosCubit)', () {
    test('addExchangeItem creates item with isReturn=true, negative line total, and updates PosState getters', () {
      posCubit.addToCart(variantBuy450, 1);
      posCubit.addExchangeItem(variantReturn300, 1);

      final state = posCubit.state;
      expect(state.hasExchangeItems, isTrue);
      expect(state.cart.length, equals(2));

      final returnItem = state.cart.firstWhere((i) => i.isReturn);
      expect(returnItem.variantId, equals(variantReturn300.id));
      expect(returnItem.isReturn, isTrue);
      expect(returnItem.total, equals(-30000)); // -300 EGP

      expect(state.newItemsTotal, equals(45000)); // 450 EGP
      expect(state.returnItemsTotal, equals(30000)); // 300 EGP
      expect(state.total, equals(15000)); // Net difference = +150 EGP
      expect(state.isZeroNetExchange, isFalse);
    });

    test('Zero difference exchange sets isZeroNetExchange=true and total=0', () {
      posCubit.addToCart(variantBuy300, 1); // 300 EGP
      posCubit.addExchangeItem(variantReturn300, 1); // 300 EGP

      final state = posCubit.state;
      expect(state.hasExchangeItems, isTrue);
      expect(state.isZeroNetExchange, isTrue);
      expect(state.total, equals(0));
    });

    test('Negative difference exchange reflects customer refund amount', () {
      posCubit.addToCart(variantBuy300, 1); // 300 EGP
      posCubit.addExchangeItem(variantReturn400, 1); // 400 EGP

      final state = posCubit.state;
      expect(state.hasExchangeItems, isTrue);
      expect(state.isZeroNetExchange, isFalse);
      expect(state.total, equals(-10000)); // -100 EGP refund to customer
    });

    test('Quantity controls respect isReturn flag independently from regular items', () {
      // Add same variant as bought and as exchange
      posCubit.addToCart(variantBuy300, 1);
      posCubit.addExchangeItem(variantBuy300, 1);

      expect(posCubit.state.cart.length, equals(2));

      // Increase return quantity
      posCubit.increaseQty(variantBuy300.id, isReturn: true);
      final returnItem = posCubit.state.cart.firstWhere((i) => i.isReturn);
      final regularItem = posCubit.state.cart.firstWhere((i) => !i.isReturn);

      expect(returnItem.quantity, equals(2));
      expect(regularItem.quantity, equals(1));

      // Decrease return quantity
      posCubit.decreaseQty(variantBuy300.id, isReturn: true);
      expect(posCubit.state.cart.firstWhere((i) => i.isReturn).quantity, equals(1));

      // Remove return item
      posCubit.removeFromCart(variantBuy300.id, isReturn: true);
      expect(posCubit.state.cart.length, equals(1));
      expect(posCubit.state.cart.first.isReturn, isFalse);
      expect(posCubit.state.hasExchangeItems, isFalse);
    });
  });

  group('Task 28: Double Stock Balancing & Net Settlement Persistence', () {
    test('Checkout balances inventory: increases stock of returned variant and decreases purchased variant', () async {
      final now = DateTime.now();

      // Seed cashier user
      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'cashier_user_1',
            branchId: 'branch-1',
            username: 'cashier1',
            displayName: 'كاشير التجربة',
            passwordHash: 'hash',
            passwordSalt: 'salt',
            role: 'cashier',
            createdAt: now,
            updatedAt: now,
          ));

      // Seed products and variants into DB
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'prod-shirt',
            branchId: 'branch-1',
            name: 'قميص كاجوال فاخر',
            categoryId: 'cat-shirts',
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'prod-tshirt',
            branchId: 'branch-1',
            name: 'تيشيرت قطن أصلي',
            categoryId: 'cat-tshirts',
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variantBuy450.id,
            branchId: 'branch-1',
            productId: 'prod-shirt',
            sku: variantBuy450.productCode,
            color: variantBuy450.color,
            size: variantBuy450.size,
            quantity: const Value(10), // Initial stock = 10
            costPrice: variantBuy450.costPrice,
            sellPrice: variantBuy450.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variantReturn300.id,
            branchId: 'branch-1',
            productId: 'prod-tshirt',
            sku: variantReturn300.productCode,
            color: variantReturn300.color,
            size: variantReturn300.size,
            quantity: const Value(5), // Initial stock = 5
            costPrice: variantReturn300.costPrice,
            sellPrice: variantReturn300.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      // Cart: Buy 1 of variantBuy450, Exchange 1 of variantReturn300
      posCubit.addToCart(variantBuy450, 1);
      posCubit.addExchangeItem(variantReturn300, 1);

      final success = await posCubit.checkout(
        cashierId: 'cashier_user_1',
        paymentMethod: 'cash',
      );
      expect(success, isTrue);

      // Verify double stock balance in DB
      final updatedBuy = await (db.select(db.productVariants)..where((v) => v.id.equals(variantBuy450.id))).getSingle();
      final updatedReturn = await (db.select(db.productVariants)..where((v) => v.id.equals(variantReturn300.id))).getSingle();

      expect(updatedBuy.quantity, equals(9)); // 10 - 1 = 9
      expect(updatedReturn.quantity, equals(6)); // 5 + 1 = 6 (restocked)

      // Verify stock movements in inventory logs
      final movements = await db.select(db.inventoryLogs).get();
      final buyMovement = movements.firstWhere((m) => m.variantId == variantBuy450.id);
      final returnMovement = movements.firstWhere((m) => m.variantId == variantReturn300.id);

      expect(buyMovement.qtyDelta, equals(-1));
      expect(buyMovement.type, equals('sale'));

      expect(returnMovement.qtyDelta, equals(1));
      expect(returnMovement.type, equals('return_'));
    });

    test('Negative settlement checkout records cash refund in active shift and preserves sales check constraint', () async {
      final now = DateTime.now();

      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'cashier_user_1',
            branchId: 'branch-1',
            username: 'cashier1',
            displayName: 'كاشير التجربة',
            passwordHash: 'hash',
            passwordSalt: 'salt',
            role: 'cashier',
            createdAt: now,
            updatedAt: now,
          ));

      // Open shift
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
            id: 'shift-pos-exchange',
            branchId: 'branch-1',
            cashierId: 'cashier_user_1',
            openingBalance: 10000,
            openedAt: now,
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'prod-polo',
            branchId: 'branch-1',
            name: 'بولو صيفي',
            categoryId: 'cat-shirts',
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'prod-pants',
            branchId: 'branch-1',
            name: 'بنطلون جينز',
            categoryId: 'cat-pants',
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variantBuy300.id,
            branchId: 'branch-1',
            productId: 'prod-polo',
            sku: variantBuy300.productCode,
            color: variantBuy300.color,
            size: variantBuy300.size,
            quantity: const Value(12),
            costPrice: variantBuy300.costPrice,
            sellPrice: variantBuy300.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variantReturn400.id,
            branchId: 'branch-1',
            productId: 'prod-pants',
            sku: variantReturn400.productCode,
            color: variantReturn400.color,
            size: variantReturn400.size,
            quantity: const Value(8),
            costPrice: variantReturn400.costPrice,
            sellPrice: variantReturn400.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      // Buy 300, Return 400 -> Net -100 EGP (-10000 piasters)
      posCubit.addToCart(variantBuy300, 1);
      posCubit.addExchangeItem(variantReturn400, 1);

      expect(posCubit.state.total, equals(-10000));

      final success = await posCubit.checkout(
        cashierId: 'cashier_user_1',
        paymentMethod: 'cash',
      );
      expect(success, isTrue);

      // Verify sales table CHECK (total >= 0) constraint clamped total to 0
      final sales = await db.select(db.sales).get();
      expect(sales.isNotEmpty, isTrue);
      expect(sales.first.total, equals(0));
      expect(sales.first.note, contains('استبدال - استرداد باقي نقدية للعميل'));

      // Verify Cash Movement recorded refund out of the drawer
      final cashMovements = await db.select(db.cashMovements).get();
      final refundMovement = cashMovements.firstWhere((cm) => cm.direction == 'out');
      expect(refundMovement.amountPiasters, equals(10000)); // 100 EGP
      expect(refundMovement.type, equals('refund'));
      expect(refundMovement.notes, contains('صرف باقي استبدال نقدي للعميل'));
    });
  });

  group('Task 28: POS Screen UI Cart & Exchange Item Dialog Tests', () {
    testWidgets('pos_exchange_item_btn opens dialog, search filters variants, and confirmation adds exchange item to cart',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<PosCubit>.value(value: posCubit),
              BlocProvider<AuthCubit>.value(value: authCubit),
            ],
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify exchange button is present in the cart header
      final exchangeBtnFinder = find.byKey(const Key('pos_exchange_item_btn'));
      expect(exchangeBtnFinder, findsOneWidget);

      // Click exchange button to open dialog
      await tester.tap(exchangeBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Search input is focused and rendered
      final searchFinder = find.byKey(const Key('exchange_item_search_field'));
      expect(searchFinder, findsOneWidget);

      // Type to search for specific variant
      await tester.enterText(searchFinder, 'تيشيرت');
      await tester.pump();

      // Confirm button for variantReturn300
      final confirmBtnFinder = find.byKey(Key('confirm_exchange_item_btn_${variantReturn300.id}'));
      expect(confirmBtnFinder, findsOneWidget);

      await tester.tap(confirmBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify dialog dismissed and exchange item badge is in cart
      expect(find.byKey(Key('exchange_item_badge_${variantReturn300.id}')), findsOneWidget);
      expect(find.text('مرتجع استبدال'), findsOneWidget);
    });

    testWidgets('Grand total and checkout button adapt accurately for positive, zero, and negative exchanges',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<PosCubit>.value(value: posCubit),
              BlocProvider<AuthCubit>.value(value: authCubit),
            ],
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final activeCubit = tester.element(find.byType(PosScreen)).read<PosCubit>();

      // 1. Positive difference (Buy 450, Return 300 -> net +150)
      activeCubit.addToCart(variantBuy450, 1);
      activeCubit.addExchangeItem(variantReturn300, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('صافي فرق السعر (المطلوب تحصيله)'), findsOneWidget);
      expect(find.textContaining('تحصيل فرق الاستبدال'), findsOneWidget);

      // 2. Zero difference (Buy 300, Return 300 -> net 0)
      activeCubit.clearCart();
      activeCubit.addToCart(variantBuy300, 1);
      activeCubit.addExchangeItem(variantReturn300, 1);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('صافي تسوية الاستبدال (متطابق)'), findsOneWidget);
      expect(find.textContaining('إتمام استبدال متطابق (بدون دفع)'), findsOneWidget);

      // 3. Negative difference (Buy 300, Return 400 -> net -100)
      activeCubit.clearCart();
      activeCubit.addToCart(variantBuy300, 1);
      activeCubit.addExchangeItem(variantReturn400, 1);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('باقي استبدال مسترد للزبون'), findsOneWidget);
      expect(find.textContaining('صرف باقي استبدال للعميل'), findsOneWidget);
    });
  });
}
