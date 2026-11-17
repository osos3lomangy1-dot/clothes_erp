import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/features/purchases/data/datasources/purchases_local_data_source.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late PurchasesLocalDataSource ds;
  late String branchId;
  final now = DateTime.parse('2026-11-17T12:00:00');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    ds = PurchasesLocalDataSourceImpl(db, branchProvider);
    branchId = await branchProvider.getBranchId();

    // Seed Category, Product, and Variant
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            branchId: branchId,
            name: 'رجالي',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-1',
            branchId: branchId,
            categoryId: 'cat-1',
            name: 'قميص أكسفورد',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var-1',
            branchId: branchId,
            productId: 'prod-1',
            sku: 'OXF-BLU-L',
            color: 'أزرق',
            size: 'L',
            quantity: const Value(0),
            costPrice: 20000, // 200 EGP
            sellPrice: 35000, // 350 EGP
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Purchase Returns to Suppliers (مرتجعات المشتريات للموردين)', () {
    test('1. Credit Return: reduces stock, records inventory log, and reduces supplier debt', () async {
      // Step A: Add Supplier
      final supplier = await ds.addSupplier(name: 'مصنع الأقمشة المتطورة');
      expect(supplier.balance, 0);

      // Step B: Create Purchase Invoice for 10 shirts @ 200 EGP = 2,000 EGP (200,000 piasters)
      // Advance paid: 500 EGP (50,000 piasters). Remaining: 1,500 EGP (150,000 piasters).
      final invoice = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-101',
        purchaseDate: now,
        paidAmount: 50000,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-1',
            qty: 10,
            costPrice: 20000,
          ),
        ],
        userId: 'admin',
      );

      // Verify stock became 10 and supplier balance became 1500 EGP
      final varAfterPurchase = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(varAfterPurchase.quantity, 10);

      final supAfterPurchase = await ds.getSupplierById(supplier.id);
      expect(supAfterPurchase!.balance, 150000); // 150,000 piasters = 1,500 EGP

      // Step C: Return 3 shirts @ 200 EGP = 600 EGP (60,000 piasters) with refundType: 'credit'
      final ret = await ds.createPurchaseReturn(
        supplierId: supplier.id,
        purchaseId: invoice.id,
        items: [
          const PurchaseReturnItemDraft(
            variantId: 'var-1',
            productName: 'قميص أكسفورد',
            variantInfo: 'أزرق - L',
            sku: 'OXF-BLU-L',
            qty: 3,
            costPrice: 20000,
          ),
        ],
        refundType: 'credit',
        reason: 'عيوب تصنيع في الخياطة',
        userId: 'admin',
      );

      expect(ret.totalAmount, 60000);
      expect(ret.isCreditRefund, isTrue);
      expect(ret.isCashRefund, isFalse);
      expect(ret.items.length, 1);
      expect(ret.items.first.qty, 3);
      expect(ret.items.first.totalCost, 60000);

      // Verify stock was reduced from 10 to 7
      final varAfterReturn = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(varAfterReturn.quantity, 7);

      // Verify InventoryLogs has an exit record
      final logs = await (db.select(db.inventoryLogs)
            ..where((l) => l.variantId.equals('var-1') & l.refType.equals('purchase_return')))
          .get();
      expect(logs.length, 1);
      expect(logs.first.type, 'out');
      expect(logs.first.qtyDelta, -3);
      expect(logs.first.refId, ret.id);

      // Verify Supplier Balance was reduced by 600 EGP (1,500 - 600 = 900 EGP = 90,000 piasters)
      final supAfterReturn = await ds.getSupplierById(supplier.id);
      expect(supAfterReturn!.balance, 90000);
    });

    test('2. Cash Return: reduces stock, records inventory log, and records incoming cash movement in drawer', () async {
      // Step A: Add Supplier
      final supplier = await ds.addSupplier(name: 'مورد النخبة للملابس');

      // Step B: Open Shift for cashier
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              id: 'shift-active-1',
              branchId: branchId,
              cashierId: 'cashier-1',
              openingBalance: 100000, // 1000 EGP
              openedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Step C: Purchase 5 shirts @ 200 EGP = 1,000 EGP (100,000 piasters) fully paid
      final invoice = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-202',
        purchaseDate: now,
        paidAmount: 100000,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-1',
            qty: 5,
            costPrice: 20000,
          ),
        ],
        userId: 'admin',
      );

      final supAfterPurchase = await ds.getSupplierById(supplier.id);
      expect(supAfterPurchase!.balance, 0); // fully paid

      // Step D: Return 2 shirts @ 200 EGP = 400 EGP (40,000 piasters) with refundType: 'cash'
      final ret = await ds.createPurchaseReturn(
        supplierId: supplier.id,
        purchaseId: invoice.id,
        items: [
          const PurchaseReturnItemDraft(
            variantId: 'var-1',
            productName: 'قميص أكسفورد',
            variantInfo: 'أزرق - L',
            sku: 'OXF-BLU-L',
            qty: 2,
            costPrice: 20000,
          ),
        ],
        refundType: 'cash',
        reason: 'استرداد نقدي فوري',
        userId: 'admin',
      );

      // Stock should be 5 - 2 = 3
      final varAfterReturn = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(varAfterReturn.quantity, 3);

      // Verify CashMovements has an incoming purchase_reversal linked to the active shift
      final cashMovements = await (db.select(db.cashMovements)
            ..where((m) => m.referenceId.equals(ret.id)))
          .get();

      expect(cashMovements.length, 1);
      final cm = cashMovements.first;
      expect(cm.type, 'purchase_reversal');
      expect(cm.direction, 'in');
      expect(cm.amountPiasters, 40000); // 400 EGP
      expect(cm.shiftId, 'shift-active-1'); // assigned to current active shift!

      // Supplier balance stays 0 because the refund was settled in cash (not credit note)
      final supAfterReturn = await ds.getSupplierById(supplier.id);
      expect(supAfterReturn!.balance, 0);
    });

    test('3. Over-return prevention: throws descriptive error if warehouse stock is less than return qty', () async {
      final supplier = await ds.addSupplier(name: 'مورد الشروق');

      // Variant currently has quantity = 0
      expect(
        () => ds.createPurchaseReturn(
          supplierId: supplier.id,
          items: [
            const PurchaseReturnItemDraft(
              variantId: 'var-1',
              productName: 'قميص أكسفورد',
              variantInfo: 'أزرق - L',
              sku: 'OXF-BLU-L',
              qty: 5,
              costPrice: 20000,
            ),
          ],
          refundType: 'credit',
          userId: 'admin',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('الكمية المتوفرة في المخزن'),
          ),
        ),
      );
    });

    test('4. Empty items validation: throws error', () async {
      final supplier = await ds.addSupplier(name: 'مورد عام');
      expect(
        () => ds.createPurchaseReturn(
          supplierId: supplier.id,
          items: [],
          refundType: 'credit',
          userId: 'admin',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('5. getPurchaseReturns retrieves returns history correctly', () async {
      final supplier = await ds.addSupplier(name: 'مورد النور');

      // Purchase 4 items
      await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-303',
        purchaseDate: now,
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-1',
            qty: 4,
            costPrice: 20000,
          ),
        ],
        userId: 'admin',
      );

      await ds.createPurchaseReturn(
        supplierId: supplier.id,
        items: [
          const PurchaseReturnItemDraft(
            variantId: 'var-1',
            productName: 'قميص أكسفورد',
            variantInfo: 'أزرق - L',
            sku: 'OXF-BLU-L',
            qty: 1,
            costPrice: 20000,
          ),
        ],
        refundType: 'credit',
        reason: 'مقاس خاطئ',
        userId: 'admin',
      );

      final returns = await ds.getPurchaseReturns(supplierId: supplier.id);
      expect(returns.length, 1);
      expect(returns.first.totalAmount, 20000);
      expect(returns.first.items.length, 1);
      expect(returns.first.items.first.productName, 'قميص أكسفورد');
      expect(returns.first.formattedTotalAmount, '200.00 ج.م');
    });
  });
}

