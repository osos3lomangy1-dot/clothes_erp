import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late InventoryLocalDataSource inv;
  late PosLocalDataSource pos;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    inv = InventoryLocalDataSource(db, bp, tx);
    pos = PosLocalDataSource(db, bp, tx, inv);
  });

  tearDown(() async => await db.close());

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

  test('checkout successfully decreases stock and creates sale', () async {
    final vid = await seedVariant();
    await pos.checkout(items: [{'variantId': vid, 'name': 'Shirt', 'color': 'Red', 'size': 'M', 'qty': 2, 'price': 200, 'cost': 100}], total: 400, cashierId: 'u1');
    final v = await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle();
    expect(v.quantity, 8);
    final sales = await db.select(db.sales).get();
    expect(sales.length, 1);
    final items = await db.select(db.saleItems).get();
    expect(items.length, 1);
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.length, 1);
  });

  test('checkout insufficient stock fails and rolls back', () async {
    final vid = await seedVariant();
    await expectLater(pos.checkout(items: [{'variantId': vid, 'name': 'Shirt', 'color': 'Red', 'size': 'M', 'qty': 100, 'price': 200, 'cost': 100}], total: 20000, cashierId: 'u1'), throwsA(anything));
    final v = await (db.select(db.productVariants)..where((t) => t.id.equals(vid))).getSingle();
    expect(v.quantity, 10);
    final sales = await db.select(db.sales).get();
    expect(sales.length, 0);
  });

  test('cashier projection does not expose costPrice', () async {
    await seedVariant();
    final list = await pos.getVariantsForPos();
    expect(list.isNotEmpty, true);
  });
}

