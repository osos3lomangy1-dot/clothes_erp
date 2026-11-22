import 'package:clothes_erp/core/database/app_database.dart' hide Promotion;
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/promotions/domain/repositories/promotions_repository.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'main-branch';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  @override
  Future<UserModel?> getCachedUser() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepo implements VariantRepository {
  final List<VariantEntity> variants;
  _FakeVariantRepo(this.variants);
  @override
  Future<Either<Failure, List<VariantEntity>>> getVariants(String pId) async => Right(variants);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async => const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async => const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePromotionsRepo implements PromotionsRepository {
  @override
  Future<Either<Failure, List<Promotion>>> getActivePromotions({DateTime? now}) async => const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Task 18: Adaptive Sector Dimensions Matrix', () {
    test('standardSizes returns realistic industry dimensions for each sector', () {
      // 1. Textiles & Decor (Carpet & Rugs)
      final carpetSizes = ActivityType.textilesDecor.standardSizes;
      expect(carpetSizes, contains('1.5×2 م'));
      expect(carpetSizes, contains('2×3 م'));
      expect(carpetSizes, contains('2.5×3.5 م'));
      expect(carpetSizes, contains('3×4 م'));
      expect(carpetSizes, contains('مشاية 1×3 م'));
      expect(carpetSizes, contains('مشاية 0.8×2 م'));
      expect(ActivityType.textilesDecor.supportsCutToLength, isTrue);

      // 2. Perfumes & Cosmetics
      final perfumeSizes = ActivityType.perfumesCosmetics.standardSizes;
      expect(perfumeSizes, equals(['30 مل', '50 مل', '100 مل', '150 مل', '200 مل']));
      expect(ActivityType.perfumesCosmetics.supportsCutToLength, isFalse);

      // 3. Electronics & Mobiles
      final electronicsSizes = ActivityType.electronicsMobiles.standardSizes;
      expect(electronicsSizes, equals(['64GB', '128GB', '256GB', '512GB', '1TB']));
      expect(ActivityType.electronicsMobiles.supportsCutToLength, isFalse);

      // 4. Footwear & Bags
      final footwearSizes = ActivityType.footwearBags.standardSizes;
      expect(footwearSizes, equals(['38', '39', '40', '41', '42', '43', '44', '45']));
      expect(ActivityType.footwearBags.supportsCutToLength, isFalse);

      // 5. Clothing & Apparel
      final clothingSizes = ActivityType.clothing.standardSizes;
      expect(clothingSizes, equals(['S', 'M', 'L', 'XL', 'XXL', '3XL']));
      expect(ActivityType.clothing.supportsCutToLength, isFalse);
    });

    test('ProductEntity supports sellMode, unit, and rollWidth for carpets and rolls', () {
      final rollProduct = ProductEntity(
        id: 'prod-carpet-roll-1',
        name: 'مشاية تركي رول عرض 1 متر',
        description: 'رول موكيت تركي مقصوص بالمتر',
        categoryId: 'cat-textiles',
        categoryName: 'سجاد ومفروشات',
        createdAt: DateTime.now(),
        activityType: 'textilesDecor',
        sellMode: 'meter',
        unit: 'meter',
        rollWidth: '1.0 م',
      );

      expect(rollProduct.sellMode, equals('meter'));
      expect(rollProduct.unit, equals('meter'));
      expect(rollProduct.rollWidth, equals('1.0 م'));
      expect(rollProduct.activityTypeEnum, equals(ActivityType.textilesDecor));
      expect(rollProduct.activityTypeEnum.supportsCutToLength, isTrue);

      final copy = rollProduct.copyWith(rollWidth: '1.2 م');
      expect(copy.rollWidth, equals('1.2 م'));
      expect(copy.sellMode, equals('meter'));
    });
  });

  group('Task 18: SaleItemEntity & Cut-to-Length Decimal Metrage Calculations', () {
    test('Calculates line total accurately for decimal quantities (3.5 meters)', () {
      // 3.5 meters of carpet at 200.00 EGP (20,000 piasters) per meter
      const item = SaleItemEntity(
        variantId: 'var-carpet-1',
        productName: 'مشاية تركي رول عرض 1م',
        size: 'رول عرض 1.0 م',
        color: 'بيج',
        price: 20000, // 200.00 EGP
        quantity: 4, // Integer fallback ceil
        decimalQuantity: 3.5,
        unit: 'م',
      );

      expect(item.effectiveQuantity, equals(3.5));
      expect(item.formattedQuantity, equals('3.5'));
      // Total: 20,000 * 3.5 = 70,000 piasters (700.00 EGP)
      expect(item.total, equals(70000));
    });

    test('Calculates line total accurately with line discount and promotions on decimal quantities', () {
      const item = SaleItemEntity(
        variantId: 'var-carpet-2',
        productName: 'موكيت قص بالمتر عرض 4م',
        size: 'رول 4م',
        color: 'رصاصي',
        price: 35000, // 350.00 EGP per meter
        quantity: 3,
        decimalQuantity: 2.75, // 2.75 meters
        unit: 'م',
        discount: 2500, // 25.00 EGP discount
        promotionDiscount: 5000, // 50.00 EGP promo discount
      );

      expect(item.effectiveQuantity, equals(2.75));
      // Subtotal: 35,000 * 2.75 = 96,250 piasters
      // Total: 96,250 - 2,500 - 5,000 = 88,750 piasters
      expect(item.total, equals(88750));
    });

    test('Falls back seamlessly to integer quantity when decimalQuantity is null or zero', () {
      const normalItem = SaleItemEntity(
        variantId: 'var-carpet-fixed',
        productName: 'سجادة النساجون 2×3 م',
        size: '2×3 م',
        color: 'كحلي',
        price: 250000, // 2,500.00 EGP
        quantity: 2,
      );

      expect(normalItem.effectiveQuantity, equals(2.0));
      expect(normalItem.formattedQuantity, equals('2'));
      expect(normalItem.total, equals(500000));
    });
  });

  group('Task 18: PosCubit Decimal Quantity Stepping & Cart Management', () {
    test('updateDecimalQuantity updates cart line and computes exact decimal subtotal', () {
      final now = DateTime.now();
      final variant = VariantEntity(
        id: 'var-carpet-meter',
        productId: 'prod-carpet',
        productCode: 'SKU-CARPET-1',
        color: 'بني',
        size: 'رول 1م',
        quantity: 100,
        costPrice: 12000,
        salePrice: 18000, // 180.00 EGP per meter
        minStock: 5,
        createdAt: now,
        productName: 'مشاية حرير رول',
      );

      final db = AppDatabase(NativeDatabase.memory());
      final bp = _FakeBranchProvider();
      final tx = TxWriter(db);
      final inv = InventoryLocalDataSource(db, bp, tx);
      final ds = PosLocalDataSource(db, bp, tx, inv);
      final gate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, bp);
      final posRepo = PosRepositoryImpl(ds, gate);
      final createSale = CreateSaleUseCase(posRepo);

      final cubit = PosCubit(
        createSale,
        _FakeVariantRepo([variant]),
        _FakeCategoryRepo(),
        _FakeProductRepo(),
        posRepo,
        _FakePromotionsRepo(),
      );

      cubit.addToCart(variant, 1);
      expect(cubit.state.cart.length, equals(1));
      expect(cubit.state.total, equals(18000));

      // Update to 4.25 meters
      cubit.updateDecimalQuantity(variant.id, 4.25, 'م');
      final updatedItem = cubit.state.cart.first;
      expect(updatedItem.decimalQuantity, equals(4.25));
      expect(updatedItem.effectiveQuantity, equals(4.25));
      expect(updatedItem.unit, equals('م'));
      // 18,000 * 4.25 = 76,500 piasters (765.00 EGP)
      expect(cubit.state.total, equals(76500));

      // Stepping up and down with increaseQty and decreaseQty
      cubit.increaseQty(variant.id);
      expect(cubit.state.cart.first.decimalQuantity, equals(5.25));
      expect(cubit.state.total, equals((18000 * 5.25).round()));

      cubit.decreaseQty(variant.id);
      expect(cubit.state.cart.first.decimalQuantity, equals(4.25));

      cubit.close();
      db.close();
    });
  });

  group('Task 18: Decimal Stock Deduction on Checkout & AppMeta Tracking', () {
    late AppDatabase db;
    late PosLocalDataSource posDs;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final bp = _FakeBranchProvider();
      final tx = TxWriter(db);
      final inv = InventoryLocalDataSource(db, bp, tx);
      posDs = PosLocalDataSource(db, bp, tx, inv);
    });

    tearDown(() async {
      await db.close();
    });

    test('Checkout deducts exact decimal quantity from bolt stock in database', () async {
      final now = DateTime.now();

      // 1. Seed product & variant with 50 meters initial stock
      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat-textiles',
        branchId: 'main-branch',
        name: 'مفروشات',
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod-bolt-1',
        branchId: 'main-branch',
        name: 'توب موكيت تركي 50 متر',
        categoryId: 'cat-textiles',
        createdAt: now,
        updatedAt: now,
        activityType: const drift.Value('textilesDecor'),
      ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'var-bolt-1',
        productId: 'prod-bolt-1',
        branchId: 'main-branch',
        sku: 'BOLT-TURK-50M',
        size: 'رول عرض 1م',
        color: 'رمادي',
        quantity: const drift.Value(50), // 50 meters
        costPrice: 15000,
        sellPrice: 22000, // 220.00 EGP per meter
        createdAt: now,
        updatedAt: now,
      ));

      // 2. Checkout sale of 3.5 meters
      final saleId = await posDs.checkout(
        items: [
          {
            'variantId': 'var-bolt-1',
            'name': 'توب موكيت تركي 50 متر',
            'color': 'رمادي',
            'size': 'رول عرض 1م',
            'qty': 4, // Ceil fallback for integer column
            'decimalQty': 3.5, // 3.5 meters cut
            'effectiveQty': 3.5,
            'unit': 'م',
            'price': 22000,
            'cost': 15000,
            'discount': 0,
            'promotionDiscount': 0,
          }
        ],
        total: (22000 * 3.5).round(), // 77,000 piasters (770.00 EGP)
        cashierId: 'cashier-test',
        paymentMethod: 'cash',
      );

      expect(saleId, isNotEmpty);

      // 3. Verify exact decimal stock in app_meta (50.0 - 3.5 = 46.5)
      final metaRow = await (db.select(db.appMeta)
            ..where((m) => m.key.equals('stock_decimal_var-bolt-1')))
          .getSingleOrNull();

      expect(metaRow, isNotNull);
      final remainingDecimalStock = double.parse(metaRow!.value);
      expect(remainingDecimalStock, equals(46.5));

      // 4. Verify sale item in database recorded with metrage in size
      final saleItems = await (db.select(db.saleItems)
            ..where((s) => s.saleId.equals(saleId)))
          .get();

      expect(saleItems.length, equals(1));
      expect(saleItems.first.lineTotal, equals(77000));
      expect(saleItems.first.size, contains('3.5 م'));
    });
  });

  group('Task 18: Receipt Formatting with Metrage Unit & Decimal Quantities', () {
    test('InvoiceItemDetailsEntity formats metrage unit and computes line profit', () {
      const invoiceItem = InvoiceItemDetailsEntity(
        id: 'item-1',
        variantId: 'var-bolt-1',
        productName: 'مشاية تركي رول عرض 1م',
        color: 'رصاصي',
        size: 'رول 1م • 3.5 م',
        qty: 4,
        decimalQty: 3.5,
        unit: 'م',
        price: 20000, // 200.00 EGP
        costPrice: 12000, // 120.00 EGP
        lineTotal: 70000, // 700.00 EGP
      );

      expect(invoiceItem.effectiveQuantity, equals(3.5));
      expect(invoiceItem.formattedQuantity, equals('3.5'));
      // Profit: 70,000 - (12,000 * 3.5) = 70,000 - 42,000 = 28,000 piasters (280.00 EGP)
      expect(invoiceItem.profitPiasters, equals(28000));
      expect(invoiceItem.profitMarginPercent, closeTo(40.0, 0.01));
    });
  });
}
