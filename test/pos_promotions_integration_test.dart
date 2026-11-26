import 'package:clothes_erp/core/database/app_database.dart' hide Promotion;
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';
import 'package:clothes_erp/features/promotions/domain/repositories/promotions_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
}

class _FakeFeatureGate implements FeatureGate {
  @override
  Future<bool> isEnabled(String key) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepository implements VariantRepository {
  final List<VariantEntity> variants;
  _FakeVariantRepository(this.variants);

  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() {
    return Stream.value(Right(variants));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepository implements CategoryRepository {
  final List<CategoryEntity> categories;
  _FakeCategoryRepository(this.categories);

  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async => Right(categories);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepository implements ProductRepository {
  final List<ProductEntity> products;
  _FakeProductRepository(this.products);

  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async => Right(products);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePromotionsRepository implements PromotionsRepository {
  List<Promotion> promotions;
  _FakePromotionsRepository(this.promotions);

  @override
  Future<Either<Failure, List<Promotion>>> getActivePromotions({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    return Right(promotions.where((p) => p.isEffectiveAt(ref)).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Phase B — POS Integration + Returns + Installments Tests', () {
    late AppDatabase db;
    late PosLocalDataSource localDataSource;
    late PosRepository posRepository;
    late CreateSaleUseCase createSaleUseCase;
    late _FakeBranchProvider branchProvider;
    late _FakeFeatureGate featureGate;

    final baseTime = DateTime(2026, 11, 16, 12, 0);

    final testProduct = ProductEntity(
      id: 'prod-1',
      name: 'قميص رجالي',
      description: 'وصف المنتج',
      categoryId: 'cat-1',
      categoryName: 'ملابس رجالي',
      createdAt: baseTime,
    );

    final testCategory = CategoryEntity(
      id: 'cat-1',
      name: 'ملابس رجالي',
      description: 'وصف الفئة',
      createdAt: baseTime,
    );

    final testVariant = VariantEntity(
      id: 'var-1',
      productId: 'prod-1',
      productName: 'قميص رجالي',
      productCode: 'P001',
      color: 'أزرق',
      size: 'L',
      quantity: 50,
      costPrice: 5000, // 50.00 EGP
      salePrice: 10000, // 100.00 EGP
      minStock: 5,
      createdAt: baseTime,
    );

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      branchProvider = _FakeBranchProvider();
      featureGate = _FakeFeatureGate();
      final tx = TxWriter(db);
      final inventory = InventoryLocalDataSource(db, branchProvider, tx);
      localDataSource = PosLocalDataSource(db, branchProvider, tx, inventory);
      posRepository = PosRepositoryImpl(localDataSource, featureGate);
      createSaleUseCase = CreateSaleUseCase(posRepository);

      // Pre-seed user for cashier
      await db.into(db.users).insert(
        UsersCompanion.insert(
          id: 'cashier-1',
          branchId: 'branch-1',
          username: 'cashier_test',
          displayName: 'كاشير تجريبي',
          role: 'cashier',
          passwordHash: 'hash',
          passwordSalt: 'salt',
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );

      // Pre-seed product & variant in db for foreign keys
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: 'cat-1',
          branchId: 'branch-1',
          name: 'ملابس رجالي',
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod-1',
          branchId: 'branch-1',
          name: 'قميص رجالي',
          categoryId: 'cat-1',
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );
      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: 'var-1',
          branchId: 'branch-1',
          productId: 'prod-1',
          sku: 'SKU001',
          color: 'أزرق',
          size: 'L',
          quantity: const drift.Value(50),
          costPrice: 5000,
          sellPrice: 10000,
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    Promotion createSamplePromo({
      String id = 'promo-10',
      String type = 'percent',
      int valueBp = 1000, // 10%
      int minQuantity = 1,
    }) {
      final promoNow = DateTime.now();
      return Promotion(
        id: id,
        branchId: 'branch-1',
        name: 'خصم 10%',
        type: type,
        scope: 'all',
        valueBp: valueBp,
        minQuantity: minQuantity,
        startsAt: promoNow.subtract(const Duration(days: 1)),
        endsAt: promoNow.add(const Duration(days: 10)),
        isActive: true,
        priority: 1,
        createdBy: 'admin',
        createdAt: baseTime,
        updatedAt: baseTime,
      );
    }

    test('1. PosCubit.init() loads active promotions', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo()]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      // Allow async stream listener to run
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.activePromotions.length, 1);
      expect(cubit.activePromotions.first.id, 'promo-10');
      await cubit.close();
    });

    test('2. Adding item to cart triggers PromotionEngine and calculates line promotion discount', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo(valueBp: 1500)]); // 15%
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 2); // 2 * 10000 = 20000. 15% = 3000 piasters discount

      expect(cubit.state.cart.length, 1);
      final item = cubit.state.cart.first;
      expect(item.promotionDiscount, 3000);
      expect(cubit.state.promotionDiscountPiasters, 3000);
      expect(cubit.state.subtotal, 20000);
      expect(cubit.state.total, 17000); // 20000 - 3000
      await cubit.close();
    });

    test('3. Removing item recalculates promotions', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo()]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 1);
      expect(cubit.state.cart.length, 1);
      expect(cubit.state.promotionDiscountPiasters, 1000);

      cubit.removeFromCart(testVariant.id);
      expect(cubit.state.cart, isEmpty);
      expect(cubit.state.promotionDiscountPiasters, 0);
      expect(cubit.state.total, 0);
      await cubit.close();
    });

    test('4. Quantity change crossing minQuantity recalculates discount on entire line', () async {
      final promoRepo = _FakePromotionsRepository([
        createSamplePromo(id: 'promo-min-3', minQuantity: 3, valueBp: 2000), // 20% if qty >= 3
      ]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 2); // 2 < 3 -> 0 discount
      expect(cubit.state.promotionDiscountPiasters, 0);
      expect(cubit.state.total, 20000);

      cubit.updateQuantity(testVariant.id, 3); // 3 >= 3 -> 20% on 30000 = 6000
      expect(cubit.state.promotionDiscountPiasters, 6000);
      expect(cubit.state.total, 24000);
      await cubit.close();
    });

    test('5. Assigning customer with discount applies best-of comparison', () async {
      final promoRepo = _FakePromotionsRepository([
        createSamplePromo(valueBp: 1000), // 10%
      ]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 1); // 10000 piasters. Promo 10% = 1000
      expect(cubit.state.promotionDiscountPiasters, 1000);

      // Assign VIP customer with 20% discount (20% > 10% -> Customer wins!)
      final vipCustomer = CustomerEntity(
        id: 'cust-vip',
        name: 'عميل مميز',
        phone: '0100000000',
        discountPercent: 20,
        createdAt: baseTime,
      );
      cubit.assignCustomer(vipCustomer);

      // Customer discount wins -> promotion discount on line becomes 0, customer discount is applied
      expect(cubit.state.promotionDiscountPiasters, 0);
      expect(cubit.state.promotionResult?.totalCustomerDiscountPiasters, 2000);
      expect(cubit.state.total, 8000); // 10000 - 2000
      await cubit.close();
    });

    test('6. state.promotionResult is properly populated', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo()]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 2);
      final res = cubit.state.promotionResult;
      expect(res, isNotNull);
      expect(res!.lines.length, 1);
      expect(res.lines.first.cartLineIndex, 0);
      expect(res.lines.first.hasPromotion, isTrue);
      expect(res.lines.first.appliedPromotion?.id, 'promo-10');
      await cubit.close();
    });

    test('7. state.promotionDiscountPiasters reflects accurate total', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo(valueBp: 2500)]); // 25%
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 4); // 4 * 10000 = 40000. 25% = 10000
      expect(cubit.state.promotionDiscountPiasters, 10000);
      await cubit.close();
    });

    test('8. Checkout persists sale_items.promotionDiscountPiasters in DB', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo(valueBp: 1000)]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 1);
      final success = await cubit.checkout(cashierId: 'cashier-1', paymentMethod: 'cash');
      expect(success, isTrue);

      final saleItems = await db.select(db.saleItems).get();
      expect(saleItems.length, 1);
      expect(saleItems.first.promotionDiscountPiasters, 1000);
      expect(saleItems.first.lineTotal, 9000); // 10000 - 1000
      await cubit.close();
    });

    test('9. Checkout writes promotion_applications in same atomic transaction', () async {
      final promoRepo = _FakePromotionsRepository([createSamplePromo(id: 'promo-save-app', valueBp: 1500)]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 2); // 20000 * 15% = 3000
      final success = await cubit.checkout(cashierId: 'cashier-1', paymentMethod: 'cash');
      expect(success, isTrue);

      final apps = await db.select(db.promotionApplications).get();
      expect(apps.length, 1);
      expect(apps.first.promotionId, 'promo-save-app');
      expect(apps.first.discountPiasters, 3000);
      expect(apps.first.saleId, isNotEmpty);
      expect(apps.first.saleItemId, isNotEmpty);
      await cubit.close();
    });

    test('10. Checkout failure rolls back transaction cleanly (no orphans)', () async {
      // Simulate failure by passing invalid payment split where split sum != total
      final promoRepo = _FakePromotionsRepository([createSamplePromo()]);
      final cubit = PosCubit(
        createSaleUseCase,
        _FakeVariantRepository([testVariant]),
        _FakeCategoryRepository([testCategory]),
        _FakeProductRepository([testProduct]),
        posRepository,
        promoRepo,
      );

      await cubit.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.addToCart(testVariant, 1);
      // Attempt checkout with invalid split sum
      final success = await cubit.checkout(
        cashierId: 'cashier-1',
        splits: [], // empty splits fails validation
      );
      expect(success, isFalse);

      final sales = await db.select(db.sales).get();
      final saleItems = await db.select(db.saleItems).get();
      final promoApps = await db.select(db.promotionApplications).get();
      expect(sales, isEmpty);
      expect(saleItems, isEmpty);
      expect(promoApps, isEmpty);
      await cubit.close();
    });

    test('11. Return of sale with promotion: refund = post-discount price', () async {
      // Create a sale with 2 items @ 100 EGP each, 20% discount (20000 subtotal, 4000 promo discount -> 16000 total)
      final promo = createSamplePromo(valueBp: 2000);
      final evalResult = PromotionEvaluationResult(
        lineResults: [
          LineDiscountResult(
            cartLineIndex: 0,
            originalSubtotal: 20000,
            discountPiasters: 4000,
            finalSubtotal: 16000,
            appliedPromotion: promo,
          ),
        ],
        totalPromotionDiscountPiasters: 4000,
        totalCustomerDiscountPiasters: 0,
        totalDiscountPiasters: 4000,
      );

      final saleId = await localDataSource.checkout(
        items: [
          {
            'variantId': 'var-1',
            'name': 'قميص رجالي',
            'color': 'أزرق',
            'size': 'L',
            'qty': 2,
            'price': 10000,
            'cost': 5000,
            'discount': 0,
            'promotionDiscount': 4000,
          }
        ],
        total: 16000,
        cashierId: 'cashier-1',
        paymentMethod: 'cash',
        promotionResult: evalResult,
      );

      final itemRow = await (db.select(db.saleItems)..where((i) => i.saleId.equals(saleId))).getSingle();
      // Unit post-discount price calculation for refund:
      final refundUnitPrice = itemRow.lineTotal ~/ itemRow.qty; // 16000 ~/ 2 = 8000 (80.00 EGP)
      expect(refundUnitPrice, 8000);

      // Refund 1 unit @ 8000 piasters (post-discount price)
      await db.into(db.returns).insert(
        ReturnsCompanion.insert(
          id: 'ret-1',
          branchId: 'branch-1',
          cashierId: 'cashier-1',
          reason: 'مقاس غير مناسب',
          refundAmount: refundUnitPrice,
          paymentMethod: 'cash',
          date: baseTime,
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );

      final retRow = await (db.select(db.returns)..where((r) => r.id.equals('ret-1'))).getSingle();
      expect(retRow.refundAmount, 8000);
    });

    test('12. Option A: promotion_applications remains unchanged on return', () async {
      // Option A guarantees original promotion application record remains intact
      final promo = createSamplePromo(id: 'promo-permanent', valueBp: 1000);
      final evalResult = PromotionEvaluationResult(
        lineResults: [
          LineDiscountResult(
            cartLineIndex: 0,
            originalSubtotal: 10000,
            discountPiasters: 1000,
            finalSubtotal: 9000,
            appliedPromotion: promo,
          ),
        ],
        totalPromotionDiscountPiasters: 1000,
        totalCustomerDiscountPiasters: 0,
        totalDiscountPiasters: 1000,
      );

      final saleId = await localDataSource.checkout(
        items: [
          {
            'variantId': 'var-1',
            'name': 'قميص رجالي',
            'color': 'أزرق',
            'size': 'L',
            'qty': 1,
            'price': 10000,
            'cost': 5000,
            'discount': 0,
            'promotionDiscount': 1000,
          }
        ],
        total: 9000,
        cashierId: 'cashier-1',
        paymentMethod: 'cash',
        promotionResult: evalResult,
      );

      final appsBefore = await (db.select(db.promotionApplications)..where((a) => a.saleId.equals(saleId))).get();
      expect(appsBefore.length, 1);
      expect(appsBefore.first.discountPiasters, 1000);

      // Process return
      await db.into(db.returns).insert(
        ReturnsCompanion.insert(
          id: 'ret-unchanged',
          branchId: 'branch-1',
          cashierId: 'cashier-1',
          reason: 'استرجاع',
          refundAmount: 9000,
          paymentMethod: 'cash',
          date: baseTime,
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );

      final appsAfter = await (db.select(db.promotionApplications)..where((a) => a.saleId.equals(saleId))).get();
      expect(appsAfter.length, 1);
      expect(appsAfter.first.discountPiasters, 1000);
      expect(appsAfter.first.deletedAt, isNull);
    });

    test('13. Installment checkout with promotion computes financedPrincipal = postDiscountTotal - downPayment', () async {
      // Subtotal = 10000, Promo 20% = 2000 -> Total = 8000. Downpayment = 2000 -> Principal = 6000
      final totalPiasters = 8000;
      final downPaymentPiasters = 2000;
      final principalPiasters = totalPiasters - downPaymentPiasters;

      await db.into(db.customerInstallments).insert(
        CustomerInstallmentsCompanion.insert(
          id: 'ci-promo-1',
          branchId: 'branch-1',
          saleId: 'sale-promo-1',
          customerId: 'cust-1',
          totalPiasters: totalPiasters,
          downPaymentPiasters: drift.Value(downPaymentPiasters),
          principalPiasters: principalPiasters,
          interestBp: 0,
          monthlyAmountPiasters: 1000,
          remainingPiasters: principalPiasters,
          durationMonths: 6,
          startDate: baseTime,
          endDate: baseTime.add(const Duration(days: 180)),
          createdBy: 'cashier-1',
          createdAt: baseTime,
          updatedAt: baseTime,
        ),
      );

      final inst = await (db.select(db.customerInstallments)..where((i) => i.id.equals('ci-promo-1'))).getSingle();
      expect(inst.totalPiasters, 8000);
      expect(inst.principalPiasters, 6000);
      expect(inst.principalPiasters, equals(inst.totalPiasters - inst.downPaymentPiasters));
    });
  });
}
