import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/core/utils/money.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/presentation/screens/receipt_customizer_screen.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/pos/presentation/widgets/fast_matrix_variant_picker_dialog.dart';
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
  Stream<Map<String, bool>> watchFeatures() {
    return Stream.value({});
  }

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
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() {
    return Stream.value(Right(variants));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  List<ProductEntity> products = [];
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async {
    return Right(products);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  List<CategoryEntity> categories = [];
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async {
    return Right(categories);
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

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  final UserModel user;
  _FakeAuthCubit(this.user) : super(AuthAuthenticated(user));
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

  final variant1 = VariantEntity(
    id: 'v-carpet-2x3',
    productId: 'prod-carpet',
    productCode: 'CR-001-2X3',
    color: 'كلاسيك تركي',
    size: '2×3 م',
    quantity: 10,
    costPrice: 150000,
    salePrice: 250000, // 2,500 EGP
    minStock: 2,
    createdAt: DateTime.now(),
    productName: 'سجادة تركي فاخرة',
  );

  final variant2 = VariantEntity(
    id: 'v-carpet-1.5x2',
    productId: 'prod-carpet',
    productCode: 'CR-001-1.5X2',
    color: 'كلاسيك تركي',
    size: '1.5×2 م',
    quantity: 8,
    costPrice: 90000,
    salePrice: 150000, // 1,500 EGP
    minStock: 1,
    createdAt: DateTime.now(),
    productName: 'سجادة تركي فاخرة',
  );

  final variant3 = VariantEntity(
    id: 'v-carpet-1x3',
    productId: 'prod-carpet',
    productCode: 'CR-001-1X3',
    color: 'كلاسيك تركي',
    size: '1×3 م',
    quantity: 5,
    costPrice: 60000,
    salePrice: 100000, // 1,000 EGP
    minStock: 1,
    createdAt: DateTime.now(),
    productName: 'سجادة تركي فاخرة',
  );

  final singleVariantProduct = VariantEntity(
    id: 'v-mat-single',
    productId: 'prod-doormat',
    productCode: 'DM-001',
    color: 'بيج',
    size: 'قياسي',
    quantity: 20,
    costPrice: 2000,
    salePrice: 5000, // 50 EGP
    minStock: 5,
    createdAt: DateTime.now(),
    productName: 'دواسة باب كلاسيك',
  );

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    featureGate = _FakeFeatureGate();

    adminUser = UserModel(
      id: 'admin_user',
      name: 'مدير الفرع',
      email: 'admin@bay3ah.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    authCubit = _FakeAuthCubit(adminUser);

    final inventory = InventoryLocalDataSource(db, branchProvider, txWriter);
    final posLocalDs = PosLocalDataSource(db, branchProvider, txWriter, inventory);
    posRepo = PosRepositoryImpl(posLocalDs, featureGate);
    createSaleUseCase = CreateSaleUseCase(posRepo);

    variantRepo = _FakeVariantRepo();
    variantRepo.variants = [variant1, variant2, variant3, singleVariantProduct];

    productRepo = _FakeProductRepo();
    productRepo.products = [
      ProductEntity(
        id: 'prod-carpet',
        name: 'سجادة تركي فاخرة',
        description: 'سجاد تركي فاخر',
        categoryId: 'cat-carpets',
        categoryName: 'سجاد',
        createdAt: DateTime.now(),
      ),
      ProductEntity(
        id: 'prod-doormat',
        name: 'دواسة باب',
        description: 'دواسة باب عملية',
        categoryId: 'cat-mats',
        categoryName: 'دواسات',
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

    // Register singleton dependencies
    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<AuthCubit>(authCubit);
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

  group('Task 17: Fast Matrix Variant Picker Dialog', () {
    testWidgets('Matrix picker displays all variants and adds bulk quantities atomically to cart',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_dialog_btn'),
                onPressed: () async {
                  dialogResult = await showDialog<bool>(
                    context: ctx,
                    builder: (_) => BlocProvider<PosCubit>.value(
                      value: posCubit,
                      child: FastMatrixVariantPickerDialog(
                        productId: 'prod-carpet',
                        productName: 'سجادة تركي فاخرة',
                        variants: [variant1, variant2, variant3],
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      // Open matrix dialog
      await tester.tap(find.byKey(const Key('open_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fast_matrix_variant_picker_dialog')), findsOneWidget);
      expect(find.text('سجادة تركي فاخرة'), findsWidgets);
      expect(find.text('مقاس: 2×3 م'), findsOneWidget);
      expect(find.text('مقاس: 1.5×2 م'), findsOneWidget);
      expect(find.text('مقاس: 1×3 م'), findsOneWidget);

      // Initially add button is disabled (0 items selected)
      final addBtnFinder = find.byKey(const Key('matrix_picker_add_btn'));
      final initialAddBtn = tester.widget<ElevatedButton>(addBtnFinder);
      expect(initialAddBtn.onPressed, isNull);

      // 1. Increment variant 1 twice (qty = 2)
      final plusV1 = find.byKey(Key('matrix_plus_${variant1.id}'));
      await tester.tap(plusV1);
      await tester.pump();
      await tester.tap(plusV1);
      await tester.pump();

      // 2. Increment variant 2 once (qty = 1)
      final plusV2 = find.byKey(Key('matrix_plus_${variant2.id}'));
      await tester.tap(plusV2);
      await tester.pump();

      // Verify bottom summary: 3 pieces, 2 variants, and total price (2 * 2500 + 1 * 1500 = 6,500 EGP)
      expect(find.text('إجمالي المحدد: 3 قطعة (2 مقاس)'), findsOneWidget);
      expect(find.text('${Money(650000).toDisplay()} ج.م'), findsWidgets);

      // Add to cart
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      // Dialog closed and returned true
      expect(dialogResult, isTrue);

      // Verify PosCubit cart has exactly 2 items with their variant IDs and quantities
      final cart = posCubit.state.cart;
      expect(cart.length, 2);

      final item1 = cart.firstWhere((it) => it.variantId == variant1.id);
      expect(item1.quantity, 2);
      expect(item1.price, 250000);

      final item2 = cart.firstWhere((it) => it.variantId == variant2.id);
      expect(item2.quantity, 1);
      expect(item2.price, 150000);

      // Pos total = 650,000 piasters (6,500 EGP)
      expect(posCubit.state.total, 650000);
    });
  });

  group('Task 17: POS Cart Panel Visual Accordion Grouping', () {
    testWidgets('Groups items of same product under accordion card and keeps single-variant items standalone',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Add 2 variants of 'prod-carpet'
      posCubit.addMultipleToCart({
        variant1: 2,
        variant2: 1,
      });

      // 2. Add 1 standalone item of 'prod-doormat'
      posCubit.addToCart(singleVariantProduct, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Accordion group card for 'prod-carpet' must exist
      final carpetGroupFinder = find.byKey(const Key('cart_group_prod-carpet'));
      expect(carpetGroupFinder, findsOneWidget);

      // Accordion header shows product name, pieces count, and sum (2*2500 + 1*1500 = 6,500 EGP)
      expect(find.text('3 قطع • 2 مقاسات'), findsOneWidget);
      expect(find.text('${Money(650000).toDisplay()} ج.م'), findsWidgets);

      // Single item 'prod-doormat' should NOT have an accordion group card
      expect(find.byKey(const Key('cart_group_prod-doormat')), findsNothing);

      // Individual variant tiles for both items are visible in the expanded accordion
      expect(find.byKey(ValueKey(variant1.id)), findsOneWidget);
      expect(find.byKey(ValueKey(variant2.id)), findsOneWidget);
      expect(find.byKey(ValueKey(singleVariantProduct.id), skipOffstage: false), findsOneWidget);

      // Test collapsing the accordion: tap toggle button
      final toggleBtn = find.byKey(const Key('cart_group_toggle_prod-carpet'));
      await tester.tap(toggleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // After collapse, individual variant tiles of carpet are hidden from screen
      expect(find.byKey(ValueKey(variant1.id)), findsNothing);
      expect(find.byKey(ValueKey(variant2.id)), findsNothing);

      // But single item is still visible
      expect(find.byKey(ValueKey(singleVariantProduct.id)), findsOneWidget);

      // Re-expand accordion
      await tester.tap(toggleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(ValueKey(variant1.id)), findsOneWidget);
      expect(find.byKey(ValueKey(variant2.id)), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 17: Invariable Ledger Rule & Stock Deduction', () {
    test('Checkout deducts stock individually and accurately per variant in database', () async {
      final now = DateTime.now();

      // Seed cashier user
      await db.into(db.users).insert(UsersCompanion.insert(
            id: 'admin_user',
            branchId: 'branch-1',
            username: 'admin',
            displayName: 'مدير الفرع',
            passwordHash: 'hash',
            passwordSalt: 'salt',
            role: 'admin',
            createdAt: now,
            updatedAt: now,
          ));

      // 1. Insert product and variants into SQLite DB
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'prod-carpet',
            branchId: 'branch-1',
            name: 'سجادة تركي فاخرة',
            categoryId: 'cat-carpets',
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variant1.id,
            branchId: 'branch-1',
            productId: 'prod-carpet',
            sku: variant1.productCode,
            color: variant1.color,
            size: variant1.size,
            quantity: const Value(10), // Stock = 10
            costPrice: variant1.costPrice,
            sellPrice: variant1.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variant2.id,
            branchId: 'branch-1',
            productId: 'prod-carpet',
            sku: variant2.productCode,
            color: variant2.color,
            size: variant2.size,
            quantity: const Value(8), // Stock = 8
            costPrice: variant2.costPrice,
            sellPrice: variant2.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variant3.id,
            branchId: 'branch-1',
            productId: 'prod-carpet',
            sku: variant3.productCode,
            color: variant3.color,
            size: variant3.size,
            quantity: const Value(5), // Stock = 5 (Not sold)
            costPrice: variant3.costPrice,
            sellPrice: variant3.salePrice,
            createdAt: now,
            updatedAt: now,
          ));

      // 2. Add 2 of variant 1 and 3 of variant 2 to cart
      posCubit.addMultipleToCart({
        variant1: 2,
        variant2: 3,
      });

      // 3. Execute checkout
      final success = await posCubit.checkout(
        cashierId: 'admin_user',
        paymentMethod: 'cash',
      );
      expect(success, isTrue);

      // 4. Verify each variant's stock was decremented independently
      final dbVariant1 = await (db.select(db.productVariants)..where((v) => v.id.equals(variant1.id))).getSingle();
      expect(dbVariant1.quantity, 8); // 10 - 2 = 8

      final dbVariant2 = await (db.select(db.productVariants)..where((v) => v.id.equals(variant2.id))).getSingle();
      expect(dbVariant2.quantity, 5); // 8 - 3 = 5

      final dbVariant3 = await (db.select(db.productVariants)..where((v) => v.id.equals(variant3.id))).getSingle();
      expect(dbVariant3.quantity, 5); // 5 (unchanged)

      // 5. Verify sale_items rows have individual variant IDs
      final saleItems = await db.select(db.saleItems).get();
      expect(saleItems.length, 2);

      final saleItemV1 = saleItems.firstWhere((si) => si.variantId == variant1.id);
      expect(saleItemV1.qty, 2);
      expect(saleItemV1.priceSnapshot, 250000);

      final saleItemV2 = saleItems.firstWhere((si) => si.variantId == variant2.id);
      expect(saleItemV2.qty, 3);
      expect(saleItemV2.priceSnapshot, 150000);
    });
  });

  group('Task 17: Receipt Variants Grouping Engine', () {
    test('ReceiptConfig and ReceiptSettingsService save and load groupVariantsOnReceipt', () async {
      final config = ReceiptConfig.defaults;
      expect(config.groupVariantsOnReceipt, isTrue);

      // Save with groupVariantsOnReceipt = false
      final updated = config.copyWith(groupVariantsOnReceipt: false);
      await ReceiptSettingsService.save(updated, featureGate, userId: 'admin_user');

      // Reload
      await ReceiptSettingsService.loadFromFeatureGate(featureGate);
      expect(ReceiptSettingsService.current.groupVariantsOnReceipt, isFalse);

      // Re-enable
      await ReceiptSettingsService.save(
        config.copyWith(groupVariantsOnReceipt: true),
        featureGate,
        userId: 'admin_user',
      );
      await ReceiptSettingsService.loadFromFeatureGate(featureGate);
      expect(ReceiptSettingsService.current.groupVariantsOnReceipt, isTrue);
    });

    testWidgets('ReceiptCustomizerScreen contains group variants switch toggle', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const ReceiptCustomizerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('receipt_group_variants_switch'));
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);
    });

    test('ReceiptPdfService generates PDF successfully with grouped variants and single variants', () async {
      final invoice = InvoiceDetailsEntity(
        id: 'inv-001',
        shortRef: 'S1001',
        date: DateTime.now(),
        cashierId: 'cashier-1',
        cashierName: 'أحمد',
        subtotal: 650000,
        discountAmount: 0,
        total: 650000,
        paymentMethod: 'cash',
        items: const [
          InvoiceItemDetailsEntity(
            id: 'item-1',
            variantId: 'v-1',
            productName: 'سجادة تركي فاخرة',
            color: 'كلاسيك',
            size: '2×3 م',
            qty: 2,
            price: 250000,
            lineTotal: 500000,
          ),
          InvoiceItemDetailsEntity(
            id: 'item-2',
            variantId: 'v-2',
            productName: 'سجادة تركي فاخرة',
            color: 'كلاسيك',
            size: '1.5×2 م',
            qty: 1,
            price: 150000,
            lineTotal: 150000,
          ),
        ],
      );

      // 1. Grouped variants enabled (default: true)
      final pdfBytesGrouped = await ReceiptPdfService.generateReceiptPdf(
        invoice,
        config: ReceiptConfig.defaults.copyWith(groupVariantsOnReceipt: true),
      );
      expect(pdfBytesGrouped, isNotEmpty);
      expect(pdfBytesGrouped.length, greaterThan(100));

      // 2. Grouped variants disabled
      final pdfBytesUngrouped = await ReceiptPdfService.generateReceiptPdf(
        invoice,
        config: ReceiptConfig.defaults.copyWith(groupVariantsOnReceipt: false),
      );
      expect(pdfBytesUngrouped, isNotEmpty);
      expect(pdfBytesUngrouped.length, greaterThan(100));
    });
  });
}
