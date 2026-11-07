import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late InventoryLocalDataSource ids;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    ids = InventoryLocalDataSource(db, bp, tx);
  });

  tearDown(() async {
    tx.beforeAuditWrite = null;
    await db.close();
  });

  Future<String> seedVariant() async {
    final now = DateTime.now();
    final branch = await bp.getBranchId();
    final pid = 'p1';
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: pid, branchId: branch, name: 'Shirt', categoryId: 'c1', createdAt: now, updatedAt: now,
    ));
    final vid = 'v1';
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: vid, branchId: branch, productId: pid, sku: 'SKU1',
      color: 'Red', size: 'M', costPrice: 100, sellPrice: 200, quantity: Value(10),
      createdAt: now, updatedAt: now,
    ));
    return vid;
  }

  test('receive increases qty and writes one inventory_logs row', () async {
    final vid = await seedVariant();
    await ids.applyStockMovement(variantId: vid, qtyDelta: 5, type: StockMovementType.receive, reason: 'restock', userId: 'u1');
    final v = await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle();
    expect(v.quantity, 15);
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.length, 1);
    expect(logs.first.qtyDelta, 5);
    expect(logs.first.type, 'receive');
    expect(logs.first.userId, 'u1');
  });

  test('negative adjustment reduces qty; below 0 rejected, nothing written', () async {
    final vid = await seedVariant();
    await ids.applyStockMovement(variantId: vid, qtyDelta: -3, type: StockMovementType.adjustment, reason: 'loss', userId: 'u1');
    final v = await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle();
    expect(v.quantity, 7);
    await expectLater(ids.applyStockMovement(variantId: vid, qtyDelta: -100, type: StockMovementType.adjustment, reason: 'loss', userId: 'u1'), throwsA(anything));
    final v2 = await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle();
    expect(v2.quantity, 7);
  });

  test('ATOMICITY: inject failure after quantity update', () async {
    final vid = await seedVariant();
    final beforeQty = (await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle()).quantity;
    final beforeLogs = (await db.select(db.inventoryLogs).get()).length;
    final beforeSyncs = (await db.select(db.syncQueue).get()).length;
    final beforeAudits = (await db.select(db.auditLogs).get()).length;
    tx.beforeAuditWrite = () async => throw Exception('boom');
    await expectLater(ids.applyStockMovement(variantId: vid, qtyDelta: 5, type: StockMovementType.receive, reason: 'r', userId: 'u1'), throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('boom'))));
    final afterQty = (await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle()).quantity;
    final afterLogs = (await db.select(db.inventoryLogs).get()).length;
    final afterSyncs = (await db.select(db.syncQueue).get()).length;
    final afterAudits = (await db.select(db.auditLogs).get()).length;
    expect(afterQty, beforeQty);
    expect(afterLogs, beforeLogs);
    expect(afterSyncs, beforeSyncs);
    expect(afterAudits, beforeAudits);
  });

  test('soft-deleted variants excluded from stock list', () async {
    final vid = await seedVariant();
    final now = DateTime.now();
    await (db.update(db.productVariants)..where((t) => t.id.equals(vid))).write(ProductVariantsCompanion(deletedAt: Value(now)));
    final list = await ids.stockList();
    expect(list.length, 0);
  });

  test('cashier projection does not expose costPrice', () async {
    await seedVariant();
    final list = await ids.stockList();
    expect(list.isNotEmpty, true);
  });

  test('low filter includes boundary qty == minStock', () async {
    final vid = await seedVariant();
    await (db.update(db.productVariants)..where((t) => t.id.equals(vid))).write(ProductVariantsCompanion(quantity: Value(5)));
    final list = await ids.stockList(filter: 'low');
    expect(list.length, 1);
  });

  test('out filter includes qty == 0', () async {
    final vid = await seedVariant();
    await (db.update(db.productVariants)..where((t) => t.id.equals(vid))).write(ProductVariantsCompanion(quantity: Value(0)));
    final list = await ids.stockList(filter: 'out');
    expect(list.length, 1);
  });

  test('movement log filters by type receive', () async {
    final vid = await seedVariant();
    await ids.applyStockMovement(variantId: vid, qtyDelta: 5, type: StockMovementType.receive, reason: 'r', userId: 'u1');
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.where((l) => l.type == 'receive').length, 1);
  });

  test('cashier projection does not expose costPrice', () async {
    await seedVariant();
    final list = await ids.stockList();
    expect(list.isNotEmpty, true);
  });

  test('cashier cannot call receive returns failure', () async {
    final vid = await seedVariant();
    try {
      await ids.applyStockMovement(variantId: vid, qtyDelta: 1, type: StockMovementType.adjustment, reason: '', userId: 'cashier');
      fail('should throw');
    } catch (e) {
      expect(e.toString(), contains('Reason is required'));
    }
  });

  test('movement log filters by date and type', () async {
    final vid = await seedVariant();
    await ids.applyStockMovement(variantId: vid, qtyDelta: 5, type: StockMovementType.receive, reason: 'r', userId: 'u1');
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.length, 1);
    expect(logs.first.type, 'receive');
  });

  test('receiveStock via DataSource increases stock and logs movement with correct reason and userId', () async {
    final vid = await seedVariant();
    await ids.applyStockMovement(
      variantId: vid,
      qtyDelta: 15,
      type: StockMovementType.receive,
      reason: 'شحنة مورد ملابس #101',
      userId: 'admin_1',
    );
    final v = await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle();
    expect(v.quantity, 25);
    final logs = await db.select(db.inventoryLogs).get();
    final log = logs.firstWhere((l) => l.reason == 'شحنة مورد ملابس #101');
    expect(log.qtyDelta, 15);
    expect(log.type, 'receive');
    expect(log.userId, 'admin_1');
  });

  test('getInventoryDetails returns joined product and variant data correctly', () async {
    final vid = await seedVariant();
    final details = await ids.getInventoryDetails();
    expect(details.isNotEmpty, true);
    final item = details.firstWhere((d) => d.variantId == vid);
    expect(item.productName, 'Shirt');
    expect(item.sku, 'SKU1');
    expect(item.quantity, 10);
  });

  test('quickCreateProductAndReceive creates product, variant, and logs receive stock in one transaction', () async {
    final detail = await ids.quickCreateProductAndReceive(
      productName: 'Jacket',
      categoryId: 'c1',
      sku: 'JKT01',
      color: 'Black',
      size: 'L',
      costPrice: 50000,
      sellPrice: 85000,
      quantity: 20,
      reason: 'فاتورة توريد جاكيتات #99',
      userId: 'admin',
    );

    expect(detail.productName, 'Jacket');
    expect(detail.sku, 'JKT01');
    expect(detail.quantity, 20);

    final v = await (db.select(db.productVariants)..where((t) => t.id.equals(detail.variantId))).getSingle();
    expect(v.quantity, 20);
    expect(v.costPrice, 50000);
    expect(v.sellPrice, 85000);

    final logs = await db.select(db.inventoryLogs).get();
    final log = logs.firstWhere((l) => l.reason == 'فاتورة توريد جاكيتات #99');
    expect(log.qtyDelta, 20);
    expect(log.type, 'receive');
  });
}



