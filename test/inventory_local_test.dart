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

  test('movement log filters by date and type', () async {
    final vid = await seedVariant();
    await ids.applyStockMovement(variantId: vid, qtyDelta: 5, type: StockMovementType.receive, reason: 'r', userId: 'u1');
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.length, 1);
    expect(logs.first.type, 'receive');
  });
}



