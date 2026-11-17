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

  test('dashboard correctly aggregates last 7 days sales including zero-sale days', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12, 0);

    // Sale on today: 4000
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_today',
      branchId: branchId,
      shortRef: 'S701',
      cashierId: 'c1',
      subtotal: 4000,
      discountType: 'none',
      total: 4000,
      paymentMethod: 'cash',
      date: today,
      createdAt: today,
      updatedAt: today,
    ));

    // Sale 2 days ago: 6000
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_2days',
      branchId: branchId,
      shortRef: 'S702',
      cashierId: 'c1',
      subtotal: 6000,
      discountType: 'none',
      total: 6000,
      paymentMethod: 'card',
      date: twoDaysAgo,
      createdAt: twoDaysAgo,
      updatedAt: twoDaysAgo,
    ));

    // Sale 5 days ago: 1500
    final fiveDaysAgo = today.subtract(const Duration(days: 5));
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_5days',
      branchId: branchId,
      shortRef: 'S703',
      cashierId: 'c1',
      subtotal: 1500,
      discountType: 'none',
      total: 1500,
      paymentMethod: 'cash',
      date: fiveDaysAgo,
      createdAt: fiveDaysAgo,
      updatedAt: fiveDaysAgo,
    ));

    // Sale 10 days ago (outside 7 days window)
    final tenDaysAgo = today.subtract(const Duration(days: 10));
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_10days',
      branchId: branchId,
      shortRef: 'S704',
      cashierId: 'c1',
      subtotal: 25000,
      discountType: 'none',
      total: 25000,
      paymentMethod: 'cash',
      date: tenDaysAgo,
      createdAt: tenDaysAgo,
      updatedAt: tenDaysAgo,
    ));

    final stats = await dataSource.getDashboardStats();

    expect(stats.last7DaysSales.length, 7);
    // The last point is today
    expect(stats.last7DaysSales.last.totalAmount, 4000);
    expect(stats.last7DaysSales.last.transactionsCount, 1);

    // 2 days ago is index 4 (7 - 1 - 2 = 4)
    expect(stats.last7DaysSales[4].totalAmount, 6000);
    expect(stats.last7DaysSales[4].transactionsCount, 1);

    // 5 days ago is index 1 (7 - 1 - 5 = 1)
    expect(stats.last7DaysSales[1].totalAmount, 1500);
    expect(stats.last7DaysSales[1].transactionsCount, 1);

    // Yesterday (index 5) has 0 sales
    expect(stats.last7DaysSales[5].totalAmount, 0);
    expect(stats.last7DaysSales[5].transactionsCount, 0);
  });

  test('dashboard correctly aggregates today hourly sales distribution and identifies peak hour', () async {
    final now = DateTime.now();
    final at10Am = DateTime(now.year, now.month, now.day, 10, 15);
    final at10AmSecond = DateTime(now.year, now.month, now.day, 10, 45);
    final at4Pm = DateTime(now.year, now.month, now.day, 16, 30);

    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_h1',
      branchId: branchId,
      shortRef: 'SH01',
      cashierId: 'c1',
      subtotal: 3000,
      discountType: 'none',
      total: 3000,
      paymentMethod: 'cash',
      date: at10Am,
      createdAt: at10Am,
      updatedAt: at10Am,
    ));

    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_h2',
      branchId: branchId,
      shortRef: 'SH02',
      cashierId: 'c1',
      subtotal: 4500,
      discountType: 'none',
      total: 4500,
      paymentMethod: 'cash',
      date: at10AmSecond,
      createdAt: at10AmSecond,
      updatedAt: at10AmSecond,
    ));

    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's_h3',
      branchId: branchId,
      shortRef: 'SH03',
      cashierId: 'c1',
      subtotal: 2000,
      discountType: 'none',
      total: 2000,
      paymentMethod: 'card',
      date: at4Pm,
      createdAt: at4Pm,
      updatedAt: at4Pm,
    ));

    final stats = await dataSource.getDashboardStats();

    expect(stats.todayHourlySales.length, 24);
    // Hour 10 should have 3000 + 4500 = 7500 and 2 transactions
    final hour10 = stats.todayHourlySales.firstWhere((h) => h.hour == 10);
    expect(hour10.totalAmount, 7500);
    expect(hour10.transactionsCount, 2);

    // Hour 16 (4 PM) should have 2000 and 1 transaction
    final hour16 = stats.todayHourlySales.firstWhere((h) => h.hour == 16);
    expect(hour16.totalAmount, 2000);
    expect(hour16.transactionsCount, 1);

    // Hour 8 should have 0
    final hour8 = stats.todayHourlySales.firstWhere((h) => h.hour == 8);
    expect(hour8.totalAmount, 0);
    expect(hour8.transactionsCount, 0);
  });

  test('dashboard accurately aggregates executive KPIs (profit, live drawer cash, supplier debts, overdue installments, returns, top products)', () async {
    final now = DateTime.now();

    // 1. Seed Category, Product & Variant
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'cat_exec',
      branchId: branchId,
      name: 'Pants',
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'prod_exec',
      branchId: branchId,
      name: 'Jeans',
      categoryId: 'cat_exec',
      minStock: const Value(2),
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: 'v_exec_1',
      branchId: branchId,
      productId: 'prod_exec',
      sku: 'JNS-BLK-32',
      color: 'Black',
      size: '32',
      quantity: const Value(20),
      costPrice: 20000, // 200 EGP cost
      sellPrice: 35000, // 350 EGP sell
      createdAt: now,
      updatedAt: now,
    ));

    // 2. Seed Sale with 2 units sold: Total = 700 EGP (70,000 piasters), Cost = 400 EGP (40,000 piasters)
    const saleId = 'sale_exec_1';
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: saleId,
      branchId: branchId,
      shortRef: 'SEXEC1',
      cashierId: 'cashier_ahmed',
      subtotal: 70000,
      discountType: 'none',
      total: 70000,
      paymentMethod: 'cash',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      id: 'si_exec_1',
      branchId: branchId,
      saleId: saleId,
      variantId: 'v_exec_1',
      productName: 'Jeans',
      color: 'Black',
      size: '32',
      qty: 2,
      priceSnapshot: 35000,
      costSnapshot: 20000,
      lineTotal: 70000,
      createdAt: now,
    ));

    // 3. Seed Operating Expense: 100 EGP (10,000 piasters)
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
      id: 'exp_exec_1',
      branchId: branchId,
      userId: 'cashier_ahmed',
      note: const Value('كهرباء وضيافة'),
      amount: 10000,
      category: 'bills',
      expenseDate: now,
      createdAt: now,
      updatedAt: now,
    ));

    // 4. Seed Today Return: 50 EGP (5,000 piasters)
    await db.into(db.returns).insert(ReturnsCompanion.insert(
      id: 'ret_exec_1',
      branchId: branchId,
      saleId: const Value(saleId),
      cashierId: 'cashier_ahmed',
      refundAmount: 5000,
      paymentMethod: 'cash',
      reason: 'مقاس غير مناسب',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));

    // 5. Seed Active Shift with 100 EGP opening
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
      id: 'shift_exec_1',
      branchId: branchId,
      cashierId: 'cashier_ahmed',
      openingBalance: 10000, // 100 EGP
      openedAt: now.subtract(const Duration(hours: 2)),
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now.subtract(const Duration(hours: 2)),
    ));

    // 6. Seed Supplier with balance: 500 EGP (50,000 piasters)
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(
      id: 'sup_exec_1',
      branchId: branchId,
      name: 'مصنع الأهرام للملابس',
      balance: const Value(50000),
      createdAt: now,
      updatedAt: now,
    ));

    // 7. Seed Customer Overdue Installment: 300 EGP (30,000 piasters) remaining with endDate in the past
    await db.into(db.customerInstallments).insert(CustomerInstallmentsCompanion.insert(
      id: 'ci_exec_1',
      branchId: branchId,
      customerId: 'cust_1',
      saleId: saleId,
      totalPiasters: 60000,
      downPaymentPiasters: const Value(10000),
      principalPiasters: 50000,
      interestBp: 0,
      monthlyAmountPiasters: 10000,
      remainingPiasters: 30000,
      durationMonths: 5,
      startDate: now.subtract(const Duration(days: 60)),
      endDate: now.subtract(const Duration(days: 10)), // In the past!
      status: const Value('active'),
      createdBy: 'admin',
      createdAt: now.subtract(const Duration(days: 60)),
      updatedAt: now,
    ));

    final stats = await dataSource.getDashboardStats();

    // Verify Sales, Cost, Expenses & Estimated Net Profit
    expect(stats.todaySales, 70000);
    expect(stats.todayCost, 40000);
    expect(stats.todayExpenses, 10000);
    // Net profit = 70,000 (Revenue) - 40,000 (Cost) - 10,000 (Expenses) = 20,000 piasters (200 EGP)
    expect(stats.todayEstimatedNetProfit, 20000);

    // Verify Returns
    expect(stats.todayReturnsCount, 1);
    expect(stats.todayReturnsTotal, 5000);

    // Verify Shift & Live Drawer Cash
    expect(stats.hasActiveShift, isTrue);
    expect(stats.activeShiftOpeningBalance, 10000);
    expect(stats.liveDrawerCash, greaterThan(0));

    // Verify Supplier Debts & Overdue Installments
    expect(stats.totalSupplierDebts, 50000);
    expect(stats.overdueInstallmentsCount, 1);
    expect(stats.overdueInstallmentsAmount, 30000);

    // Verify Top Products & Payment Breakdown
    expect(stats.todayPaymentBreakdown['cash'], 70000);
    expect(stats.todayTopProducts.length, 1);
    expect(stats.todayTopProducts.first.productName, 'Jeans');
    expect(stats.todayTopProducts.first.quantitySold, 2);
  });
}

