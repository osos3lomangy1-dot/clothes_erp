import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart';

void main() {
  late AppDatabase db;
  late DashboardLocalDataSource dataSource;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dataSource = DashboardLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('dashboard calculates today sales, transactions, and low stock correctly', () async {
    final now = DateTime.now();

    // 1. Seed Categories & Products
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'cat1',
      branchId: branchId,
      name: 'Shirts',
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'prod1',
      branchId: branchId,
      name: 'T-Shirt',
      categoryId: 'cat1',
      minStock: const Value(5),
      createdAt: now,
      updatedAt: now,
    ));

    // 2. Seed Variants: v1 (low stock: qty 2 <= minStock 5), v2 (normal: qty 10)
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: 'v1',
      branchId: branchId,
      productId: 'prod1',
      sku: 'TSH-RED-M',
      color: 'Red',
      size: 'M',
      quantity: const Value(2),
      costPrice: 500,
      sellPrice: 1000,
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: 'v2',
      branchId: branchId,
      productId: 'prod1',
      sku: 'TSH-BLU-L',
      color: 'Blue',
      size: 'L',
      quantity: const Value(10),
      costPrice: 500,
      sellPrice: 1000,
      createdAt: now,
      updatedAt: now,
    ));

    // 3. Seed Sales:
    // Today sale 1 (valid)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 'sale1',
      branchId: branchId,
      shortRef: 'S001',
      cashierId: 'c1',
      subtotal: 3000,
      discountType: 'none',
      total: 3000,
      paymentMethod: 'cash',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));

    // Today sale 2 (valid)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 'sale2',
      branchId: branchId,
      shortRef: 'S002',
      cashierId: 'c1',
      subtotal: 2000,
      discountType: 'none',
      total: 2000,
      paymentMethod: 'card',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));

    // Yesterday sale (should be excluded)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 'sale_old',
      branchId: branchId,
      shortRef: 'S003',
      cashierId: 'c1',
      subtotal: 9999,
      discountType: 'none',
      total: 9999,
      paymentMethod: 'cash',
      date: now.subtract(const Duration(days: 2)),
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    ));

    // Soft-deleted sale today (should be excluded)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 'sale_deleted',
      branchId: branchId,
      shortRef: 'S004',
      cashierId: 'c1',
      subtotal: 5000,
      discountType: 'none',
      total: 5000,
      paymentMethod: 'cash',
      date: now,
      deletedAt: Value(now),
      createdAt: now,
      updatedAt: now,
    ));

    // 4. Fetch Stats
    final stats = await dataSource.getDashboardStats();

    expect(stats.todaySales, 5000); // 3000 + 2000
    expect(stats.todayTransactions, 2);
    expect(stats.lowStockCount, 1);
    expect(stats.lowStockVariants.first.id, 'v1');
  });
}

