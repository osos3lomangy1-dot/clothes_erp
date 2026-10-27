import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/utils/date_utils.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  const uuid = Uuid();
  const branch = 'branch-1';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('insert and soft-delete one row per table', () async {
    final now = DateTime.now();
    final userId = uuid.v4();
    final catId = uuid.v4();
    final prodId = uuid.v4();
    final varId = uuid.v4();
    final saleId = uuid.v4();
    final saleItemId = uuid.v4();
    final returnId = uuid.v4();
    final returnItemId = uuid.v4();
    final logId = uuid.v4();
    final shiftId = uuid.v4();
    final expId = uuid.v4();
    final custId = uuid.v4();
    final stocktakeId = uuid.v4();
    final stocktakeItemId = uuid.v4();
    final dailyStatId = '2026-01-01';
    final auditId = uuid.v4();
    final syncId = uuid.v4();

    await db.into(db.users).insert(UsersCompanion.insert(
      id: userId, branchId: branch, username: 'admin', displayName: 'Admin',
      role: 'admin', passwordHash: 'hash', passwordSalt: 'salt',
      createdAt: now, updatedAt: now,
    ));
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: catId, branchId: branch, name: 'Cat', createdAt: now, updatedAt: now,
    ));
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId, branchId: branch, name: 'Prod', categoryId: catId,
      createdAt: now, updatedAt: now,
    ));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: varId, branchId: branch, productId: prodId, sku: 'SKU1',
      color: 'Red', size: 'M', costPrice: 100, sellPrice: 200,
      createdAt: now, updatedAt: now,
    ));
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: saleId, branchId: branch, shortRef: 'S001', cashierId: userId,
      subtotal: 200, discountType: 'none', total: 200, paymentMethod: 'cash',
      date: now, createdAt: now, updatedAt: now,
    ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      id: saleItemId, branchId: branch, saleId: saleId, variantId: varId,
      productName: 'Prod', color: 'Red', size: 'M', qty: 1,
      priceSnapshot: 200, costSnapshot: 100, lineTotal: 200, createdAt: now,
    ));
    await db.into(db.returns).insert(ReturnsCompanion.insert(
      id: returnId, branchId: branch, cashierId: userId, reason: 'defect',
      refundAmount: 200, paymentMethod: 'cash', date: now,
      createdAt: now, updatedAt: now,
    ));
    await db.into(db.returnItems).insert(ReturnItemsCompanion.insert(
      id: returnItemId, branchId: branch, returnId: returnId, variantId: varId,
      qty: 1, refundUnitPrice: 200, createdAt: now,
    ));
    await db.into(db.inventoryLogs).insert(InventoryLogsCompanion.insert(
      id: logId, branchId: branch, variantId: varId, type: 'out',
      qtyDelta: -1, refType: 'sale', userId: userId, createdAt: now,
    ));
    await db.into(db.shifts).insert(ShiftsCompanion.insert(
      id: shiftId, branchId: branch, cashierId: userId, openingBalance: 0,
      openedAt: now, createdAt: now, updatedAt: now,
    ));
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
      id: expId, branchId: branch, category: 'rent', amount: 1000,
      userId: userId, expenseDate: now, createdAt: now, updatedAt: now,
    ));
    await db.into(db.customers).insert(CustomersCompanion.insert(
      id: custId, branchId: branch, name: 'Cust', phone: '123',
      createdAt: now, updatedAt: now,
    ));
    await db.into(db.stocktakes).insert(StocktakesCompanion.insert(
      id: stocktakeId, branchId: branch, cashierId: userId, date: now,
      createdAt: now, updatedAt: now,
    ));
    await db.into(db.stocktakeItems).insert(StocktakeItemsCompanion.insert(
      id: stocktakeItemId, branchId: branch, stocktakeId: stocktakeId,
      variantId: varId, expectedQty: 10, countedQty: 9, difference: -1,
      createdAt: now,
    ));
    await db.into(db.dailyStats).insert(DailyStatsCompanion.insert(
      id: dailyStatId, branchId: branch, date: now, createdAt: now, updatedAt: now,
    ));
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
      id: auditId, branchId: branch, userId: userId, action: 'create',
      entity: 'sale', entityId: saleId, createdAt: now,
    ));
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
      id: syncId, branchId: branch, entity: 'sale', entityId: saleId,
      operation: 'insert', payload: '{}', createdAt: now, updatedAt: now,
    ));
    await db.into(db.appMeta).insert(AppMetaCompanion.insert(
      key: 'branchId', value: branch, updatedAt: now,
    ));

    await (db.update(db.products)..where((t) => t.id.equals(prodId)))
        .write(ProductsCompanion(deletedAt: Value(now)));
    await (db.update(db.sales)..where((t) => t.id.equals(saleId)))
        .write(SalesCompanion(deletedAt: Value(now)));

    final products = await db.select(db.products).get();
    expect(products.length, 1);
    expect(products.first.deletedAt, isNotNull);
  });

  test('duplicate non-deleted barcode fails, succeeds if soft-deleted', () async {
    final now = DateTime.now();
    final varId1 = uuid.v4();
    final varId2 = uuid.v4();
    final prodId = uuid.v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId, branchId: branch, name: 'P', categoryId: 'c1', createdAt: now, updatedAt: now,
    ));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: varId1, branchId: branch, productId: prodId, sku: 'SKU1',
      color: 'Red', size: 'M', costPrice: 100, sellPrice: 200, barcode: const Value('BC1'),
      createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: varId2, branchId: branch, productId: prodId, sku: 'SKU2',
        color: 'Blue', size: 'L', costPrice: 100, sellPrice: 200, barcode: const Value('BC1'),
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
    await (db.update(db.productVariants)..where((t) => t.id.equals(varId1)))
        .write(ProductVariantsCompanion(deletedAt: Value(now)));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: varId2, branchId: branch, productId: prodId, sku: 'SKU2',
      color: 'Blue', size: 'L', costPrice: 100, sellPrice: 200, barcode: const Value('BC1'),
      createdAt: now, updatedAt: now,
    ));
  });

  test('duplicate customer phone fails', () async {
    final now = DateTime.now();
    await db.into(db.customers).insert(CustomersCompanion.insert(
      id: uuid.v4(), branchId: branch, name: 'C1', phone: '123',
      createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.customers).insert(CustomersCompanion.insert(
        id: uuid.v4(), branchId: branch, name: 'C2', phone: '123',
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('duplicate daily_stats id fails', () async {
    final now = DateTime.now();
    await db.into(db.dailyStats).insert(DailyStatsCompanion.insert(
      id: '2026-01-01', branchId: branch, date: now, createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.dailyStats).insert(DailyStatsCompanion.insert(
        id: '2026-01-01', branchId: branch, date: now, createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('duplicate username fails', () async {
    final now = DateTime.now();
    await db.into(db.users).insert(UsersCompanion.insert(
      id: uuid.v4(), branchId: branch, username: 'admin', displayName: 'A',
      role: 'admin', passwordHash: 'h', passwordSalt: 's',
      createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.users).insert(UsersCompanion.insert(
        id: uuid.v4(), branchId: branch, username: 'admin', displayName: 'B',
        role: 'cashier', passwordHash: 'h2', passwordSalt: 's2',
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('dayKey formats dates correctly', () {
    expect(AppDateUtils.dayKey(DateTime(2026, 3, 15, 10, 30)), '2026-03-15');
    expect(AppDateUtils.dayKey(DateTime(2026, 3, 15, 23, 59)), '2026-03-15');
    expect(AppDateUtils.dayKey(DateTime(2026, 3, 16, 0, 1)), '2026-03-16');
    expect(AppDateUtils.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('sale_items qty = 0 fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: uuid.v4(), branchId: branch, saleId: 's1', variantId: 'v1',
        productName: 'P', color: 'R', size: 'M', qty: 0,
        priceSnapshot: 100, costSnapshot: 50, lineTotal: 0, createdAt: now,
      )),
      throwsA(anything),
    );
  });

  test('sale_items price_snapshot < 0 fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: uuid.v4(), branchId: branch, saleId: 's1', variantId: 'v1',
        productName: 'P', color: 'R', size: 'M', qty: 1,
        priceSnapshot: -1, costSnapshot: 50, lineTotal: 100, createdAt: now,
      )),
      throwsA(anything),
    );
  });

  test('return_items qty = 0 fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.returnItems).insert(ReturnItemsCompanion.insert(
        id: uuid.v4(), branchId: branch, returnId: 'r1', variantId: 'v1',
        qty: 0, refundUnitPrice: 100, createdAt: now,
      )),
      throwsA(anything),
    );
  });

  test('sales total < 0 fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.sales).insert(SalesCompanion.insert(
        id: uuid.v4(), branchId: branch, shortRef: 'S2', cashierId: 'u1',
        subtotal: 100, discountType: 'none', total: -1, paymentMethod: 'cash',
        date: now, createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('expenses amount = 0 fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: uuid.v4(), branchId: branch, category: 'rent', amount: 0,
        userId: 'u1', expenseDate: now, createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('shifts opening_balance < 0 fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: uuid.v4(), branchId: branch, cashierId: 'u1', openingBalance: -1,
        openedAt: now, createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('product_variants negative quantity fails', () async {
    final now = DateTime.now();
    final prodId = uuid.v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId, branchId: branch, name: 'P', categoryId: 'c1', createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: uuid.v4(), branchId: branch, productId: prodId, sku: 'SKU1',
        color: 'Red', size: 'M', quantity: const Value(-1), costPrice: 100, sellPrice: 200,
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('product_variants negative sellPrice fails', () async {
    final now = DateTime.now();
    final prodId = uuid.v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId, branchId: branch, name: 'P', categoryId: 'c1', createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: uuid.v4(), branchId: branch, productId: prodId, sku: 'SKU1',
        color: 'Red', size: 'M', costPrice: 100, sellPrice: -1,
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('product_variants negative costPrice fails', () async {
    final now = DateTime.now();
    final prodId = uuid.v4();
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: prodId, branchId: branch, name: 'P', categoryId: 'c1', createdAt: now, updatedAt: now,
    ));
    expectLater(
      db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: uuid.v4(), branchId: branch, productId: prodId, sku: 'SKU1',
        color: 'Red', size: 'M', costPrice: -1, sellPrice: 200,
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });

  test('returns empty reason fails', () async {
    final now = DateTime.now();
    expectLater(
      db.into(db.returns).insert(ReturnsCompanion.insert(
        id: uuid.v4(), branchId: branch, cashierId: 'u1', reason: '',
        refundAmount: 0, paymentMethod: 'cash', date: now,
        createdAt: now, updatedAt: now,
      )),
      throwsA(anything),
    );
  });
}

