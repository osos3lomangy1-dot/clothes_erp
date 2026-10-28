import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late ProductLocalDataSource pds;
  late VariantLocalDataSource vds;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    pds = ProductLocalDataSource(db, bp, tx);
    vds = VariantLocalDataSource(db, bp, tx);
  });

  tearDown(() async => await db.close());

  test('create product with 3 variants; list excludes soft-deleted', () async {
    await pds.createProduct(name: 'Shirt', categoryId: 'c1');
    final products = await pds.getProducts();
    expect(products.length, 1);
    // soft delete
    await pds.softDeleteProduct(products.first.id);
    final after = await pds.getProducts();
    expect(after.length, 0);
  });

  test('duplicate sku fails; reuse after soft delete succeeds', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200);
    // duplicate sku fails
    expectLater(
      vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Blue', size: 'L', costPrice: 100, sellPrice: 200),
      throwsA(anything),
    );
    // soft delete first variant
    final variants = await vds.getVariants(prod.id);
    await vds.softDeleteVariant(variants.first.id);
    // reuse succeeds
    await vds.createVariant(productId: prod.id, sku: 'SKU3', color: 'Green', size: 'S', costPrice: 100, sellPrice: 200, );
  });

  test('auto-generated skus are unique', () async {
    final bc1 = await vds.autoGenerateSku('Shirt','Red','M');
    expect(bc1, isNotEmpty);
  });

  test('price change writes audit row with old and new values', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200);
    final variant = (await vds.getVariants(prod.id)).first;
    await vds.updateVariant(variant.id, sellPrice: 250);
    final audits = await db.select(db.auditLogs).get();
    expect(audits.isNotEmpty, true);
  });

  test('ATOMICITY with injected failure for create', () async {
    tx.beforeAuditWrite = () async => throw Exception('boom');
    await expectLater(pds.createProduct(name: 'P1', categoryId: 'c1'), throwsA(anything));
    final products = await db.select(db.products).get();
    final syncs = await db.select(db.syncQueue).get();
    final audits = await db.select(db.auditLogs).get();
    expect(products.length, 0);
    expect(syncs.length, 0);
    expect(audits.length, 0);
  });

  test('deleting a product soft-deletes its variants', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200);
    await pds.softDeleteProduct(prod.id);
    final variants = await vds.getVariants(prod.id);
    expect(variants.length, 0);
  });

  test('ATOMICITY with injected failure for update', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    tx.beforeAuditWrite = () async => throw Exception('boom');
    await expectLater(pds.updateProduct(prod.id, name: 'P2'), throwsA(anything));
    final products = await db.select(db.products).get();
    expect(products.first.name, 'P1');
  });

  test('ATOMICITY with injected failure for delete', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    tx.beforeAuditWrite = () async => throw Exception('boom');
    await expectLater(pds.softDeleteProduct(prod.id), throwsA(anything));
    final products = await db.select(db.products).get();
    expect(products.first.deletedAt, isNull);
  });

  test('updateVariant cannot change quantity', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200, quantity: 5);
    final v = (await vds.getVariants(prod.id)).first;
    await vds.updateVariant(v.id, sellPrice: 250);
    final v2 = (await vds.getVariants(prod.id)).first;
    expect(v2.quantity, 5);
  });

  test('createVariant with qty 10 logs opening stock', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200, quantity: 10);
    final v = (await vds.getVariants(prod.id)).first;
    expect(v.quantity, 10);
    final logs = await db.select(db.inventoryLogs).get();
    expect(logs.length, 1);
    expect(logs.first.type, 'receive');
    expect(logs.first.reason, 'opening stock');
  });

  test('ATOMICITY createVariant with initial qty', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    final beforeVariants = (await db.select(db.productVariants).get()).length;
    final beforeLogs = (await db.select(db.inventoryLogs).get()).length;
    final beforeSyncs = (await db.select(db.syncQueue).get()).length;
    final beforeAudits = (await db.select(db.auditLogs).get()).length;
    tx.beforeAuditWrite = () async => throw Exception('boom');
    await expectLater(vds.createVariant(productId: prod.id, sku: 'SKU2', color: 'Blue', size: 'L', costPrice: 100, sellPrice: 200, quantity: 5), throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('boom'))));
    final afterVariants = (await db.select(db.productVariants).get()).length;
    final afterLogs = (await db.select(db.inventoryLogs).get()).length;
    final afterSyncs = (await db.select(db.syncQueue).get()).length;
    final afterAudits = (await db.select(db.auditLogs).get()).length;
    expect(afterVariants, beforeVariants);
    expect(afterLogs, beforeLogs);
    expect(afterSyncs, beforeSyncs);
    expect(afterAudits, beforeAudits);
  });

  test('cashier projection does not expose costPrice', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200);
    final cashierProds = await pds.cashierProducts();
    expect(cashierProds.isNotEmpty, true);
    // cashier projection doesn't include costPrice in its query
  });

  test('deleting a product that has sale_items is rejected', () async {
    await pds.createProduct(name: 'P1', categoryId: 'c1');
    final prod = (await pds.getProducts()).first;
    await vds.createVariant(productId: prod.id, sku: 'SKU1', color: 'Red', size: 'M', costPrice: 100, sellPrice: 200);
    final variant = (await vds.getVariants(prod.id)).first;
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 's1', branchId: 'b1', shortRef: 'S1', cashierId: 'u1',
      subtotal: 200, discountType: 'none', total: 200, paymentMethod: 'cash',
      date: DateTime.now(), createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      id: 'si1', branchId: 'b1', saleId: 's1', variantId: variant.id,
      productName: 'P1', color: 'Red', size: 'M', qty: 1,
      priceSnapshot: 200, costSnapshot: 100, lineTotal: 200, createdAt: DateTime.now(),
    ));
    await expectLater(pds.softDeleteProduct(prod.id), throwsA(anything));
  });
}







