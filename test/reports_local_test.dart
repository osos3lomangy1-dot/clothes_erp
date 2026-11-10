import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';

void main() {
  late AppDatabase db;
  late ReportsLocalDataSource dataSource;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dataSource = ReportsLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('reports calculates revenue, cost, profit, and payment breakdown correctly', () async {
    final now = DateTime.now();

    // 1. Seed Product & Variant with costPrice 1200, sellPrice 2000
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'cat1',
      branchId: branchId,
      name: 'Pants',
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'prod1',
      branchId: branchId,
      name: 'Jeans',
      categoryId: 'cat1',
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: 'v1',
      branchId: branchId,
      productId: 'prod1',
      sku: 'JNS-32',
      color: 'Black',
      size: '32',
      costPrice: 1200,
      sellPrice: 2000,
      quantity: const Value(50),
      createdAt: now,
      updatedAt: now,
    ));

    // 2. Sale 1: Cash, total 4000, 2 items (cost 2400)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's1',
      branchId: branchId,
      shortRef: 'S101',
      cashierId: 'c1',
      subtotal: 4000,
      discountType: 'none',
      total: 4000,
      paymentMethod: 'cash',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      id: 'si1',
      branchId: branchId,
      saleId: 's1',
      variantId: 'v1',
      productName: 'Jeans',
      color: 'Black',
      size: '32',
      qty: 2,
      priceSnapshot: 2000,
      costSnapshot: 1200,
      lineTotal: 4000,
      createdAt: now,
    ));

    // 3. Sale 2: Card, total 2000, 1 item (cost 1200)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's2',
      branchId: branchId,
      shortRef: 'S102',
      cashierId: 'c1',
      subtotal: 2000,
      discountType: 'none',
      total: 2000,
      paymentMethod: 'card',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      id: 'si2',
      branchId: branchId,
      saleId: 's2',
      variantId: 'v1',
      productName: 'Jeans',
      color: 'Black',
      size: '32',
      qty: 1,
      priceSnapshot: 2000,
      costSnapshot: 1200,
      lineTotal: 2000,
      createdAt: now,
    ));

    // 4. Sale 3: Out of date range (30 days ago)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_old',
      branchId: branchId,
      shortRef: 'S103',
      cashierId: 'c1',
      subtotal: 50000,
      discountType: 'none',
      total: 50000,
      paymentMethod: 'cash',
      date: now.subtract(const Duration(days: 30)),
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 30)),
    ));

    // 5. Sale 4: Soft-deleted sale
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_deleted',
      branchId: branchId,
      shortRef: 'S104',
      cashierId: 'c1',
      subtotal: 10000,
      discountType: 'none',
      total: 10000,
      paymentMethod: 'cash',
      date: now,
      deletedAt: Value(now),
      createdAt: now,
      updatedAt: now,
    ));

    // Execute query for past 7 days to now
    final report = await dataSource.getSalesReport(
      startDate: now.subtract(const Duration(days: 7)),
      endDate: now,
    );

    expect(report.totalRevenue, 6000);
    expect(report.totalCost, 3600);
    expect(report.totalProfit, 2400);
    expect(report.totalTransactions, 2);
    expect(report.paymentMethodBreakdown['cash'], 4000);
    expect(report.paymentMethodBreakdown['card'], 2000);
  });

  test('reports calculates top selling products accurately and limits to top 5', () async {
    final now = DateTime.now();

    // 1. Seed Categories & Product
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'cat_top',
      branchId: branchId,
      name: 'Suits',
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'prod_suit',
      branchId: branchId,
      name: 'Classic Suit',
      categoryId: 'cat_top',
      createdAt: now,
      updatedAt: now,
    ));

    // 2. Seed 6 variants (A, B, C, D, E, F)
    final letters = ['A', 'B', 'C', 'D', 'E', 'F'];
    for (final l in letters) {
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'var_$l',
        branchId: branchId,
        productId: 'prod_suit',
        sku: 'SUIT-$l',
        color: 'Color-$l',
        size: '50',
        costPrice: 5000,
        sellPrice: 10000,
        quantity: const Value(100),
        createdAt: now,
        updatedAt: now,
      ));
    }

    // 3. Seed Sale with items having different sold quantities:
    // A: 20 pcs
    // B: 15 pcs
    // C: 10 pcs
    // D: 8 pcs
    // E: 5 pcs
    // F: 2 pcs
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 'sale_top',
      branchId: branchId,
      shortRef: 'ST01',
      cashierId: 'c1',
      subtotal: 600000,
      discountType: 'none',
      total: 600000,
      paymentMethod: 'cash',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));

    final quantities = {'A': 20, 'B': 15, 'C': 10, 'D': 8, 'E': 5, 'F': 2};
    for (final entry in quantities.entries) {
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'si_${entry.key}',
        branchId: branchId,
        saleId: 'sale_top',
        variantId: 'var_${entry.key}',
        productName: 'Classic Suit',
        color: 'Color-${entry.key}',
        size: '50',
        qty: entry.value,
        priceSnapshot: 10000,
        costSnapshot: 5000,
        lineTotal: entry.value * 10000,
        createdAt: now,
      ));
    }

    final report = await dataSource.getSalesReport(
      startDate: now.subtract(const Duration(days: 1)),
      endDate: now,
    );

    // Assert only top 5 are returned (F with 2 pcs should be excluded)
    expect(report.topSellingProducts.length, 5);

    // Rank 1: var_A (20 pcs, 200,000 piasters)
    expect(report.topSellingProducts[0].variantId, 'var_A');
    expect(report.topSellingProducts[0].quantitySold, 20);
    expect(report.topSellingProducts[0].totalRevenue, 200000);
    expect(report.topSellingProducts[0].sku, 'SUIT-A');

    // Rank 2: var_B (15 pcs)
    expect(report.topSellingProducts[1].variantId, 'var_B');
    expect(report.topSellingProducts[1].quantitySold, 15);

    // Rank 3: var_C (10 pcs)
    expect(report.topSellingProducts[2].variantId, 'var_C');
    expect(report.topSellingProducts[2].quantitySold, 10);

    // Rank 4: var_D (8 pcs)
    expect(report.topSellingProducts[3].variantId, 'var_D');
    expect(report.topSellingProducts[3].quantitySold, 8);

    // Rank 5: var_E (5 pcs)
    expect(report.topSellingProducts[4].variantId, 'var_E');
    expect(report.topSellingProducts[4].quantitySold, 5);
  });
}

