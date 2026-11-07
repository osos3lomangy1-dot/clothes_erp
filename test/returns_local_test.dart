import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/returns/data/datasources/returns_local_data_source.dart';
import 'package:clothes_erp/features/returns/domain/entities/return_item_entity.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late InventoryLocalDataSource inv;
  late ReturnsLocalDataSourceImpl returnsDs;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    inv = InventoryLocalDataSource(db, bp, tx);
    returnsDs = ReturnsLocalDataSourceImpl(db, bp, tx, inv);
  });

  tearDown(() async {
    returnsDs.onBeforeApplyStock = null;
    await db.close();
  });

  Future<String> seedProductAndVariant({int initialQty = 10, int price = 1000}) async {
    final now = DateTime.now();
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'cat1',
      branchId: branchId,
      name: 'Shirts',
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'p1',
      branchId: branchId,
      name: 'T-Shirt',
      categoryId: 'cat1',
      createdAt: now,
      updatedAt: now,
    ));

    final vid = 'v1';
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: vid,
      branchId: branchId,
      productId: 'p1',
      sku: 'TSH-01',
      color: 'White',
      size: 'L',
      quantity: Value(initialQty),
      costPrice: 500,
      sellPrice: price,
      createdAt: now,
      updatedAt: now,
    ));

    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's1',
      branchId: branchId,
      shortRef: 'S101',
      cashierId: 'cashier1',
      subtotal: price * 2,
      discountType: 'none',
      total: price * 2,
      paymentMethod: 'cash',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));

    return vid;
  }

  test('successful return: increases stock, creates return record, creates inventory_logs', () async {
    final vid = await seedProductAndVariant(initialQty: 10, price: 1000);

    final returnItem = ReturnItemEntity(
      variantId: vid,
      productName: 'T-Shirt',
      color: 'White',
      size: 'L',
      maxQty: 2,
      qty: 2,
      refundUnitPrice: 1000,
    );

    await returnsDs.processReturn(
      saleId: 's1',
      items: [returnItem],
      reason: 'Defective zipper',
      userId: 'cashier1',
    );

    // 1. Stock must increase from 10 to 12
    final variant = await (db.select(db.productVariants)..where((v) => v.id.equals(vid))).getSingle();
    expect(variant.quantity, 12);

    // 2. Returns table must have 1 record
    final returns = await db.select(db.returns).get();
    expect(returns.length, 1);
    expect(returns.first.refundAmount, 2000);
    expect(returns.first.reason, 'Defective zipper');
    expect(returns.first.cashierId, 'cashier1');

    // 3. Return items table must have 1 record
    final returnItems = await db.select(db.returnItems).get();
    expect(returnItems.length, 1);
    expect(returnItems.first.qty, 2);
    expect(returnItems.first.refundUnitPrice, 1000);

    // 4. Inventory logs must record stock movement with type return_
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.length, 1);
    expect(logs.first.variantId, vid);
    expect(logs.first.qtyDelta, 2);
    expect(logs.first.type, 'return_');
    expect(logs.first.reason, 'Defective zipper');
  });

  test('atomicity: inject failure during applyStockMovement, assert no return record is created and stock remains unchanged', () async {
    final vid = await seedProductAndVariant(initialQty: 10, price: 1000);

    final returnItem = ReturnItemEntity(
      variantId: vid,
      productName: 'T-Shirt',
      color: 'White',
      size: 'L',
      maxQty: 2,
      qty: 2,
      refundUnitPrice: 1000,
    );

    // Inject failure before stock movement
    returnsDs.onBeforeApplyStock = () async => throw Exception('Stock movement injection failure');

    await expectLater(
      returnsDs.processReturn(
        saleId: 's1',
        items: [returnItem],
        reason: 'Customer return',
        userId: 'cashier1',
      ),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Stock movement injection failure'))),
    );

    // Assert complete rollback: no return records, no return items, no logs, stock untouched
    final returns = await db.select(db.returns).get();
    expect(returns.isEmpty, true);

    final returnItems = await db.select(db.returnItems).get();
    expect(returnItems.isEmpty, true);

    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.isEmpty, true);

    final variant = await (db.select(db.productVariants)..where((v) => v.id.equals(vid))).getSingle();
    expect(variant.quantity, 10);
  });

  test('negative return: empty reason rejected', () async {
    final vid = await seedProductAndVariant(initialQty: 10, price: 1000);

    final returnItem = ReturnItemEntity(
      variantId: vid,
      productName: 'T-Shirt',
      qty: 1,
      refundUnitPrice: 1000,
    );

    await expectLater(
      returnsDs.processReturn(
        saleId: 's1',
        items: [returnItem],
        reason: '   ',
        userId: 'cashier1',
      ),
      throwsA(anything),
    );
  });
}

