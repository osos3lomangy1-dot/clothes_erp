import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/hotkey_strip_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/services/cashier_permissions_service.dart';
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';
import 'package:clothes_erp/features/categories/data/repositories/category_repository_impl.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/widgets/kitchen_waste_dialog.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_entity.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/purchases/data/datasources/purchases_local_data_source.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:clothes_erp/features/purchases/domain/entities/supplier_entity.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';

class _FakeSuppliersCubit extends Cubit<SuppliersState> implements SuppliersCubit {
  _FakeSuppliersCubit()
      : super(SuppliersState(
          suppliers: [
            SupplierEntity(
              id: 'sup-1',
              branchId: 'branch-1',
              name: 'مورد الدواجن والخضار',
              balance: 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
        ));

  @override
  Future<void> loadSuppliers() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePurchasesCubit extends Cubit<PurchasesState> implements PurchasesCubit {
  _FakePurchasesCubit() : super(const PurchasesState());

  @override
  Future<void> loadPurchases({String? supplierId, String? paymentStatus}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

class _MockProductRepo implements ProductRepository {
  final List<ProductEntity> savedProducts = [];

  @override
  Future<Either<Failure, String>> addProductWithVariants(
      ProductEntity product, dynamic variants) async {
    savedProducts.add(product);
    return Right(product.id.isEmpty ? 'prod_1' : product.id);
  }

  @override
  Future<Either<Failure, Unit>> updateProduct(ProductEntity product) async {
    final idx = savedProducts.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      savedProducts[idx] = product;
    } else {
      savedProducts.add(product);
    }
    return const Right(unit);
  }

  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      Right(savedProducts);

  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() =>
      Stream.value(Right(savedProducts));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepo implements VariantRepository {
  final List<VariantEntity> variants = [];

  @override
  Future<Either<Failure, List<VariantEntity>>> getAllVariants() async =>
      Right(variants);

  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(Right(variants));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  @override
  Future<Either<Failure, String>> getActiveCashierId() async =>
      const Right('cashier_1');

  @override
  Future<Either<Failure, SaleEntity>> createSale(SaleEntity sale) async =>
      Right(sale);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final sl = GetIt.instance;
  late AppDatabase db;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    sl.registerSingleton<AppDatabase>(db);

    final branchProvider = _FakeBranchProvider();
    sl.registerSingleton<BranchProvider>(branchProvider);

    final txWriter = TxWriter(db);
    sl.registerSingleton<TxWriter>(txWriter);

    final authLocalDs = _FakeAuthLocalDataSource();
    final featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    sl.registerSingleton<FeatureGate>(featureGate);

    final activitySettingsService =
        ActivitySettingsService(db, featureGate);
    sl.registerSingleton<ActivitySettingsService>(activitySettingsService);

    final inventoryLocalDataSource =
        InventoryLocalDataSource(db, branchProvider, txWriter);
    sl.registerSingleton<InventoryLocalDataSource>(inventoryLocalDataSource);

    final purchasesDataSource = PurchasesLocalDataSourceImpl(db, branchProvider);
    sl.registerSingleton<PurchasesLocalDataSource>(purchasesDataSource);
    sl.registerFactory<SuppliersCubit>(() => _FakeSuppliersCubit());
    sl.registerFactory<PurchasesCubit>(() => _FakePurchasesCubit());

    final cashierPermissionsService = CashierPermissionsService();
    sl.registerSingleton<CashierPermissionsService>(cashierPermissionsService);

    final shortcutSettingsService = ShortcutSettingsService(db);
    sl.registerSingleton<ShortcutSettingsService>(shortcutSettingsService);

    final hotkeyStripService = HotkeyStripService();
    sl.registerSingleton<HotkeyStripService>(hotkeyStripService);

    final branding = AppBranding();
    sl.registerSingleton<AppBranding>(branding);

    final adminUser = UserModel(
      id: 'admin_1',
      name: 'admin',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    await authLocalDs.cacheUser(adminUser);
    sl.registerSingleton<AuthLocalDataSource>(authLocalDs);
    sl.registerSingleton<AuthCubit>(_FakeAuthCubit(adminUser));

    // Enable restaurantsCafes activity
    await db.into(db.appMeta).insert(
      AppMetaCompanion.insert(
        key: 'activity.restaurantsCafes',
        value: '1',
        updatedAt: DateTime.now(),
      ),
    );

    // Seed hospitality category
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-fnb',
        branchId: 'branch-1',
        name: 'وجبات ومستلزمات مطبخ',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  group('Task 30.5: RecipeItemData & RestaurantCulinaryData Modeling Tests', () {
    test('RecipeItemData serializes and deserializes accurately', () {
      const item = RecipeItemData(
        rawMaterialId: 'raw_meat_1',
        rawMaterialName: 'لحم بقري مفروم',
        quantityNeeded: 0.25,
        yieldLossPercentage: 10.0,
        unit: 'كيلوجرام',
      );

      final json = item.toJson();
      expect(json['rawMaterialId'], 'raw_meat_1');
      expect(json['rawMaterialName'], 'لحم بقري مفروم');
      expect(json['quantityNeeded'], 0.25);
      expect(json['yieldLossPercentage'], 10.0);
      expect(json['unit'], 'كيلوجرام');

      final reconstructed = RecipeItemData.fromJson(json);
      expect(reconstructed, equals(item));
      expect(reconstructed.yieldLossPercentage, 10.0);
    });

    test('RestaurantCulinaryData properly encapsulates isRawMaterial, purchaseUnit and recipeItems', () {
      const culinary = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'شيكارة 25ك',
        recipeItems: [
          RecipeItemData(
            rawMaterialId: 'raw_rice',
            rawMaterialName: 'أرز بسمتي',
            quantityNeeded: 1.0,
            yieldLossPercentage: 5.0,
            unit: 'كيلوجرام',
          ),
        ],
      );

      expect(culinary.isRawMaterial, true);
      expect(culinary.purchaseUnit, 'شيكارة 25ك');
      expect(culinary.recipeItems.length, 1);
      expect(culinary.hasCulinaryInfo, true);

      final encoded = culinary.toEncodedString();
      final parsed = RestaurantCulinaryData.parse(encoded);
      expect(parsed.isRawMaterial, true);
      expect(parsed.purchaseUnit, 'شيكارة 25ك');
      expect(parsed.recipeItems.length, 1);
      expect(parsed.recipeItems.first.rawMaterialName, 'أرز بسمتي');
    });

    test('ProductEntity exposes restaurant raw material getters', () {
      const culinary = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'لتر / جركن',
        recipeItems: [
          RecipeItemData(
            rawMaterialId: 'raw_oil',
            rawMaterialName: 'زيت ذرة',
            quantityNeeded: 0.5,
            yieldLossPercentage: 2.0,
            unit: 'لتر',
          ),
        ],
      );

      final product = ProductEntity(
        id: 'prod_raw_oil',
        name: 'زيت ذرة خام',
        description: culinary.toEncodedString(),
        categoryId: 'cat-fnb',
        categoryName: 'مواد خام',
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );

      expect(product.isRestaurantRawMaterial, true);
      expect(product.restaurantPurchaseUnit, 'لتر / جركن');
      expect(product.restaurantRecipeItems.length, 1);
      expect(product.restaurantRecipeItems.first.rawMaterialId, 'raw_oil');
    });
  });

  group('Task 30.5: POS Raw Material Isolation Tests', () {
    test('PosCubit excludes raw materials from filteredVariants in POS grid', () async {
      final mockProductRepo = _MockProductRepo();
      final fakeVariantRepo = _FakeVariantRepo();
      final fakePosRepo = _FakePosRepo();
      final categoryRepo = CategoryRepositoryImpl(
        CategoryLocalDataSource(db, sl<BranchProvider>()),
      );

      // Meal Product (Sellable)
      const mealCulinary = RestaurantCulinaryData(
        isRawMaterial: false,
        prepTimeMinutes: 15,
      );
      final mealProduct = ProductEntity(
        id: 'meal_burger',
        name: 'برجر لحم مشوي',
        description: mealCulinary.toEncodedString(),
        categoryId: 'cat-fnb',
        categoryName: 'وجبات',
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );

      // Raw Material Product (Hidden from POS Selling Grid)
      const rawCulinary = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'كيلوجرام',
      );
      final rawProduct = ProductEntity(
        id: 'raw_patty',
        name: 'لحم برجر خام مجمد',
        description: rawCulinary.toEncodedString(),
        categoryId: 'cat-fnb',
        categoryName: 'مواد خام',
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );

      mockProductRepo.savedProducts.addAll([mealProduct, rawProduct]);

      final mealVariant = VariantEntity(
        id: 'var_meal_1',
        productId: 'meal_burger',
        productCode: 'MEAL1',
        color: 'افتراضي',
        size: 'ساندوتش',
        quantity: 50,
        costPrice: 4000,
        salePrice: 8500,
        minStock: 5,
        createdAt: DateTime.now(),
      );

      final rawVariant = VariantEntity(
        id: 'var_raw_1',
        productId: 'raw_patty',
        productCode: 'RAW1',
        color: 'خامة',
        size: 'كيلوجرام',
        quantity: 20,
        costPrice: 20000,
        salePrice: 0,
        minStock: 5,
        createdAt: DateTime.now(),
      );

      fakeVariantRepo.variants.addAll([mealVariant, rawVariant]);

      final cubit = PosCubit(
        CreateSaleUseCase(fakePosRepo),
        fakeVariantRepo,
        categoryRepo,
        mockProductRepo,
        fakePosRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Ensure filteredVariants only contains the sellable meal and excludes raw materials
      expect(cubit.state.filteredVariants.length, 1);
      expect(cubit.state.filteredVariants.first.id, 'var_meal_1');
      expect(cubit.state.filteredVariants.any((v) => v.id == 'var_raw_1'), isFalse);
    });
  });

  group('Task 30.5: Hospitality Purchases & Quick Raw Material Tests', () {
    testWidgets('CreatePurchaseScreen renders quick raw material button in hospitality mode', (tester) async {
      await sl<FeatureGate>().setMeta(
        RetailSector.metaKey,
        RetailSector.hospitality,
        userId: 'admin_1',
      );

      await tester.binding.setSurfaceSize(const Size(1280, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreatePurchaseScreen(
              onBack: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Quick raw material button must be present in hospitality mode
      expect(find.byKey(const Key('add_raw_material_btn')), findsOneWidget);
      expect(find.text('+ خامة أو مستلزم جديد'), findsOneWidget);

      // Open quick raw material dialog
      await tester.tap(find.byKey(const Key('add_raw_material_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('raw_material_name_field')), findsOneWidget);
      expect(find.byKey(const Key('raw_material_unit_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('confirm_add_raw_material_btn')), findsOneWidget);

      // Enter raw material details
      await tester.enterText(find.byKey(const Key('raw_material_name_field')), 'صدور فراخ تتبيلة');
      await tester.enterText(find.byKey(const Key('raw_material_cost_field')), '140');
      await tester.enterText(find.byKey(const Key('raw_material_qty_field')), '15');
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.byKey(const Key('confirm_add_raw_material_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check item was inserted into purchase invoice table
      expect(find.text('صدور فراخ تتبيلة'), findsOneWidget);
      expect(find.text('الخامة / المستلزم / الوحدة'), findsOneWidget);
      expect(find.text('الكمية الموردة'), findsOneWidget);

      // Fast-forward past SnackBar timer and unmount widget cleanly
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Task 30.5: Kitchen Waste Management Dialog Tests', () {
    testWidgets('KitchenWasteDialog allows selecting reason and deducts stock on confirm', (tester) async {
      // Seed a raw material variant with 50 units stock
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod_raw_chicken',
          branchId: 'branch-1',
          categoryId: 'cat-fnb',
          name: 'دجاج متبل طازج',
          activityType: const Value('restaurantsCafes'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: 'var_chicken_1',
          branchId: 'branch-1',
          productId: 'prod_raw_chicken',
          sku: 'CHK-KG-1',
          size: 'كيلوجرام',
          color: 'خامة',
          costPrice: 12000,
          sellPrice: 0,
          quantity: const Value(50),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_waste_test_btn'),
                onPressed: () => KitchenWasteDialog.show(ctx, defaultVariantId: 'var_chicken_1'),
                child: const Text('افتح إذن الهالك'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_waste_test_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kitchen_waste_dialog')), findsOneWidget);
      expect(find.byKey(const Key('waste_item_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('waste_quantity_field')), findsOneWidget);
      expect(find.byKey(const Key('waste_reason_dropdown')), findsOneWidget);

      // Enter waste quantity: 6 kg
      await tester.enterText(find.byKey(const Key('waste_quantity_field')), '6');
      await tester.pumpAndSettle();

      // Tap confirm
      await tester.tap(find.byKey(const Key('confirm_kitchen_waste_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check stock in database was reduced from 50 to 44
      final variantRow = await (db.select(db.productVariants)
            ..where((t) => t.id.equals('var_chicken_1')))
          .getSingle();
      expect(variantRow.quantity, 44);

      // Fast-forward past SnackBar timer and unmount
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 30.5: Recipe BOM Auto-Deduction during Sale Tests', () {
    test('PosCubit completeSale automatically deducts recipe raw materials with yield loss', () async {
      // 1. Seed raw material in database
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod_raw_beef',
          branchId: 'branch-1',
          categoryId: 'cat-fnb',
          name: 'لحم بقري خام',
          activityType: const Value('restaurantsCafes'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: 'var_raw_beef_1',
          branchId: 'branch-1',
          productId: 'prod_raw_beef',
          sku: 'BEEF-RAW',
          size: 'كيلوجرام',
          color: 'خامة',
          costPrice: 25000,
          sellPrice: 0,
          quantity: const Value(100), // Starting stock: 100 kg
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 2. Setup repos & cubit
      final mockProductRepo = _MockProductRepo();
      final fakeVariantRepo = _FakeVariantRepo();
      final fakePosRepo = _FakePosRepo();
      final categoryRepo = CategoryRepositoryImpl(
        CategoryLocalDataSource(db, sl<BranchProvider>()),
      );

      // Recipe: each burger needs 2 kg with 10% cooking loss
      // Addendum 30.9 accurate formula: 2 * (1 + 0.10) * 2 meals = 4.4 -> round = 4 kg (100 - 4 = 96)
      final mealCulinary = RestaurantCulinaryData(
        recipeItems: const [
          RecipeItemData(
            rawMaterialId: 'var_raw_beef_1',
            rawMaterialName: 'لحم بقري خام',
            quantityNeeded: 2.0,
            yieldLossPercentage: 10.0,
            unit: 'كيلوجرام',
          ),
        ],
      );

      final mealProduct = ProductEntity(
        id: 'prod_double_burger',
        name: 'وجبة دبل برجر',
        description: mealCulinary.toEncodedString(),
        categoryId: 'cat-fnb',
        categoryName: 'وجبات',
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );

      mockProductRepo.savedProducts.add(mealProduct);

      final mealVariant = VariantEntity(
        id: 'var_double_burger_1',
        productId: 'prod_double_burger',
        productCode: 'DBL-BRG',
        color: 'افتراضي',
        size: 'حجم عائلي',
        quantity: 50,
        costPrice: 6000,
        salePrice: 12000,
        minStock: 5,
        createdAt: DateTime.now(),
      );

      fakeVariantRepo.variants.add(mealVariant);

      final cubit = PosCubit(
        CreateSaleUseCase(fakePosRepo),
        fakeVariantRepo,
        categoryRepo,
        mockProductRepo,
        fakePosRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Add 2 double burger meals to cart
      cubit.addToCart(mealVariant, 2);
      expect(cubit.state.cart.length, 1);
      expect(cubit.state.cart.first.quantity, 2);

      // Complete sale
      final saleSuccess = await cubit.completeSale();
      expect(saleSuccess, isTrue);

      // Verify that raw material stock in DB was deducted by 4 (100 - 4 = 96)
      final rawVariantRow = await (db.select(db.productVariants)
            ..where((t) => t.id.equals('var_raw_beef_1')))
          .getSingle();
      expect(rawVariantRow.quantity, 96);
    });
  });
}
