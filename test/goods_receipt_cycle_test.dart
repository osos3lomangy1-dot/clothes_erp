import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/purchases/data/datasources/purchases_local_data_source.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter tx;
  late InventoryLocalDataSource inventoryDs;
  late PurchasesLocalDataSource purchasesDs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    tx = TxWriter(db);
    inventoryDs = InventoryLocalDataSource(db, branchProvider, tx);
    purchasesDs = PurchasesLocalDataSourceImpl(db, branchProvider);

    // Seed basic product and variant
    final now = DateTime.now();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            branchId: 'branch-1',
            name: 'ملابس رجالي',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-1',
            branchId: 'branch-1',
            categoryId: 'cat-1',
            name: 'قميص أكسفورد كاجوال',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var-1',
            branchId: 'branch-1',
            productId: 'prod-1',
            sku: 'OXF-BLU-L',
            color: 'أزرق',
            size: 'L',
            quantity: const Value(10),
            sellPrice: 35000,
            costPrice: 20000,
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Goods Receipt & Stock Movement Cycle Tests', () {
    test('Cashier creates Blind Goods Receipt: increases stock immediately and marks receipt as pending', () async {
      // Starting stock is 10
      final vBefore = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(vBefore.quantity, 10);

      // Cashier receives 15 pieces blindly
      final receipt = await inventoryDs.createGoodsReceipt(
        items: [
          const GoodsReceiptDraftItem(variantId: 'var-1', quantity: 15),
        ],
        cashierId: 'cashier_ahmed',
        notes: 'استلام شحنة الصباح من المندوب',
      );

      expect(receipt.status, 'pending');
      expect(receipt.totalItems, 15);
      expect(receipt.cashierId, 'cashier_ahmed');

      // Verify stock increased immediately to 25
      final vAfter = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(vAfter.quantity, 25);

      // Verify inventory log row written via applyStockMovement
      final logs = await (db.select(db.inventoryLogs)..where((l) => l.refId.equals(receipt.id))).get();
      expect(logs.length, 1);
      expect(logs.first.type, 'receive');
      expect(logs.first.qtyDelta, 15);
      expect(logs.first.refType, 'goods_receipt');

      // Verify query pending receipts
      final pendingList = await inventoryDs.getGoodsReceipts(status: 'pending');
      expect(pendingList.length, 1);
      expect(pendingList.first.id, receipt.id);
    });

    test('Manager converts Goods Receipt to Purchase Invoice: updates cost & debt, status becomes invoiced, and DOES NOT duplicate stock', () async {
      // 1. Cashier receives 20 pieces
      final receipt = await inventoryDs.createGoodsReceipt(
        items: [
          const GoodsReceiptDraftItem(variantId: 'var-1', quantity: 20),
        ],
        cashierId: 'cashier_user',
      );

      // Initial stock (10) + received (20) = 30
      final vAfterReceipt = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(vAfterReceipt.quantity, 30);

      // 2. Manager adds supplier
      final supplier = await purchasesDs.addSupplier(
        name: 'مصنع الشرق للغزل',
        phone: '01012345678',
      );

      // 3. Manager turns receipt into purchase invoice with agreed cost (e.g. 210 EGP = 21000 piasters)
      final invoice = await purchasesDs.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-GR-9901',
        purchaseDate: DateTime.now(),
        paidAmount: 100000, // Paid 1000 EGP advance
        items: [
          const PurchaseItemDraft(
            variantId: 'var-1',
            qty: 20,
            costPrice: 21000,
          ),
        ],
        userId: 'admin_general',
        goodsReceiptId: receipt.id,
      );

      expect(invoice.id.isNotEmpty, true);
      expect(invoice.totalAmount, 420000); // 20 * 21000 = 420,000 piasters (4200 EGP)

      // 4. CRITICAL: Stock MUST NOT be duplicated! Must stay exactly 30!
      final vAfterInvoice = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(vAfterInvoice.quantity, 30, reason: 'Stock must remain 30 and not be increased a second time');
      expect(vAfterInvoice.costPrice, 21000, reason: 'Cost price must be updated with the manager price');

      // 5. Verify GoodsReceipt status is now invoiced
      final updatedReceipt = await inventoryDs.getGoodsReceiptById(receipt.id);
      expect(updatedReceipt?.status, 'invoiced');

      // 6. Verify pending receipts list is now empty
      final remainingPending = await inventoryDs.getGoodsReceipts(status: 'pending');
      expect(remainingPending.isEmpty, true);

      // 7. Verify supplier balance correctly includes the remaining debt
      // Total 4200 EGP - Paid 1000 EGP = 3200 EGP = 320,000 piasters
      final sAfter = await purchasesDs.getSuppliers();
      expect(sAfter.first.balance, 320000);
    });

    test('Direct Purchase without Goods Receipt: increases stock normally as before', () async {
      final supplier = await purchasesDs.addSupplier(name: 'مورد مباشر');

      final vBefore = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(vBefore.quantity, 10);

      await purchasesDs.createPurchaseInvoice(
        supplierId: supplier.id,
        purchaseDate: DateTime.now(),
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(variantId: 'var-1', qty: 5, costPrice: 20000),
        ],
        userId: 'admin',
      );

      final vAfter = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(vAfter.quantity, 15, reason: 'Direct purchase increases stock by 5');
    });
  });
}
