import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/data/repositories/variant_repository_impl.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class TestBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'test_branch';
}

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter txWriter;
  late VariantLocalDataSource variantDataSource;
  late VariantRepositoryImpl variantRepository;
  late DashboardLocalDataSource dashboardDataSource;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = TestBranchProvider();
    txWriter = TxWriter(db);
    variantDataSource = VariantLocalDataSource(db, branchProvider, txWriter);
    variantRepository = VariantRepositoryImpl(variantDataSource);
    dashboardDataSource = DashboardLocalDataSourceImpl(db);

    // Seed category
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'cat_1',
      branchId: 'test_branch',
      name: 'ملابس رجالي',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  });

  tearDown(() async {
    await db.close();
  });

  test('VariantLocalDataSource persists minStock to parent product and repository reads it', () async {
    const prodId = 'prod_oxford';
    final now = DateTime.now();

    // 1. Create a product with default minStock (5)
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId,
      branchId: 'test_branch',
      name: 'قميص أكسفورد',
      categoryId: 'cat_1',
      minStock: const Value(5),
      createdAt: now,
      updatedAt: now,
    ));

    var prod = await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    expect(prod.minStock, 5);

    // 2. Add a variant specifying minStock = 8
    await variantRepository.addVariant(VariantEntity(
      id: '',
      productId: prodId,
      productCode: 'OXF-BLU-L',
      color: 'أزرق',
      size: 'L',
      quantity: 10,
      costPrice: 20000,
      salePrice: 35000,
      wholesalePrice: 28000,
      minStock: 8,
      createdAt: now,
    ));

    // Verify parent product minStock updated in DB to 8
    prod = await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    expect(prod.minStock, 8);

    // 3. Fetch variants via repository and verify variant.minStock reflects parent product
    final variantsEither = await variantRepository.getVariants(prodId);
    final variants = variantsEither.getOrElse(() => []);
    expect(variants.length, 1);
    expect(variants.first.minStock, 8);

    // 4. Update variant with a lower minStock = 2
    final existingVariant = variants.first;
    await variantRepository.updateVariant(existingVariant.copyWith(minStock: 2));

    // Verify parent product minStock updated to 2
    prod = await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    expect(prod.minStock, 2);

    final updatedEither = await variantRepository.getVariants(prodId);
    expect(updatedEither.getOrElse(() => []).first.minStock, 2);
  });

  test('Dashboard low stock alert updates reactively when minStock changes', () async {
    const prodId = 'prod_polo';
    final now = DateTime.now();

    // 1. Create product with minStock = 5
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId,
      branchId: 'test_branch',
      name: 'تيشيرت بولو',
      categoryId: 'cat_1',
      minStock: const Value(5),
      createdAt: now,
      updatedAt: now,
    ));

    // 2. Add variant with qty = 3 (3 <= 5 so it IS in low stock initially)
    await variantDataSource.createVariant(
      productId: prodId,
      sku: 'POLO-WHT-M',
      color: 'أبيض',
      size: 'M',
      costPrice: 15000,
      sellPrice: 25000,
      quantity: 3,
    );

    var stats = await dashboardDataSource.getDashboardStats();
    expect(stats.lowStockCount, 1);
    expect(stats.lowStockVariants.first.productCode, 'POLO-WHT-M');

    // 3. Admin lowers minStock to 2 (now qty 3 > minStock 2 -> alert clears!)
    final variant = (await variantDataSource.getVariants(prodId)).first;
    await variantDataSource.updateVariant(
      variant.id,
      minStock: 2,
    );

    stats = await dashboardDataSource.getDashboardStats();
    expect(stats.lowStockCount, 0, reason: 'Qty 3 is greater than updated minStock 2, so low stock alert should clear');
    expect(stats.lowStockVariants.isEmpty, true);

    // 4. Admin raises minStock to 10 (qty 3 <= 10 -> alert appears again!)
    await variantDataSource.updateVariant(
      variant.id,
      minStock: 10,
    );

    stats = await dashboardDataSource.getDashboardStats();
    expect(stats.lowStockCount, 1);
    expect(stats.lowStockVariants.first.productCode, 'POLO-WHT-M');
  });

  test('Dashboard watchDashboardUpdates emits on database changes', () async {
    final stream = dashboardDataSource.watchDashboardUpdates();

    bool emitted = false;
    final sub = stream.listen((_) {
      emitted = true;
    });

    // Create a product
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'prod_jeans',
      branchId: 'test_branch',
      name: 'بنطلون جينز',
      categoryId: 'cat_1',
      minStock: const Value(3),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    // Wait a brief pump for drift table update to fire
    await Future.delayed(const Duration(milliseconds: 50));
    expect(emitted, true);

    await sub.cancel();
  });

  test('InventoryLocalDataSource.updateProductMinStock updates product minStock and syncs to DB', () async {
    final inventoryDataSource = InventoryLocalDataSource(db, branchProvider, txWriter);

    const prodId = 'prod_shirt';
    final now = DateTime.now();

    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId,
      branchId: 'test_branch',
      name: 'قميص كتان',
      categoryId: 'cat_1',
      minStock: const Value(5),
      createdAt: now,
      updatedAt: now,
    ));

    // Admin edits minStock directly from inventory to 12
    await inventoryDataSource.updateProductMinStock(
      productId: prodId,
      minStock: 12,
    );

    final prod = await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    expect(prod.minStock, 12);
  });
}
