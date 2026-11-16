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
  const nowStr = '2026-11-16T12:00:00';
  final now = DateTime.parse(nowStr);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    ds = PurchasesLocalDataSourceImpl(db, branchProvider);
    branchId = await branchProvider.getBranchId();

    // Seed test Category, Product, and Variant
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-test',
            branchId: branchId,
            name: 'قسم تجريبي',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-test',
            branchId: branchId,
            categoryId: 'cat-test',
            name: 'منتج تجريبي',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var-test-1',
            branchId: branchId,
            productId: 'prod-test',
            sku: 'SKU-001',
            color: 'أبيض',
            size: 'XL',
            quantity: const Value(0),
            costPrice: 1000, // 10 EGP
            sellPrice: 2000,
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Supplier Payment Logic & FIFO Allocation Tests', () {
    test('1. general payment allocates to oldest open invoice (FIFO)', () async {
      final supplier = await ds.addSupplier(name: 'مورد 1');

      // Invoice 1: 1000 EGP (100,000 piasters), 0 advance
      final inv1 = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-1',
        purchaseDate: now.subtract(const Duration(days: 2)),
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 100,
            costPrice: 1000, // 100 * 1000 = 100,000
          ),
        ],
        userId: 'admin',
      );

      // Invoice 2: 500 EGP (50,000 piasters), 0 advance
      final inv2 = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-2',
        purchaseDate: now.subtract(const Duration(days: 1)),
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 50,
            costPrice: 1000, // 50 * 1000 = 50,000
          ),
        ],
        userId: 'admin',
      );

      // Total balance: 1500 EGP (150,000 piasters)
      final supInitial = await ds.getSupplierById(supplier.id);
      expect(supInitial!.balance, 150000);

      // General payment: 700 EGP (70,000 piasters)
      await ds.addSupplierPayment(
        supplierId: supplier.id,
        amount: 70000,
        paymentDate: now,
        paymentMethod: 'كاش',
        userId: 'admin',
      );

      // Balance = 1500 - 700 = 800 EGP (80,000 piasters)
      final supAfter = await ds.getSupplierById(supplier.id);
      expect(supAfter!.balance, 80000);

      // Oldest invoice (INV-1) should have paidAmount = 70,000 and status = partial
      final inv1After = await ds.getPurchaseById(inv1.id);
      expect(inv1After!.paidAmount, 70000);
      expect(inv1After.paymentStatus, 'partial');

      // Newer invoice (INV-2) should remain 0 paid and unpaid
      final inv2After = await ds.getPurchaseById(inv2.id);
      expect(inv2After!.paidAmount, 0);
      expect(inv2After.paymentStatus, 'unpaid');
    });

    test('2. general payment splits across multiple open invoices', () async {
      final supplier = await ds.addSupplier(name: 'مورد 2');

      // Invoice 1: 500 EGP (50,000 piasters), 0 advance
      final inv1 = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-A',
        purchaseDate: now.subtract(const Duration(days: 5)),
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 50,
            costPrice: 1000,
          ),
        ],
        userId: 'admin',
      );

      // Invoice 2: 800 EGP (80,000 piasters), 0 advance
      final inv2 = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-B',
        purchaseDate: now.subtract(const Duration(days: 2)),
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 80,
            costPrice: 1000,
          ),
        ],
        userId: 'admin',
      );

      // Total balance: 1300 EGP (130,000 piasters)
      expect((await ds.getSupplierById(supplier.id))!.balance, 130000);

      // General payment: 1000 EGP (100,000 piasters)
      await ds.addSupplierPayment(
        supplierId: supplier.id,
        amount: 100000,
        paymentDate: now,
        paymentMethod: 'تحويل بنكي',
        userId: 'admin',
      );

      // Invoice 1 should be fully paid (50,000 / 50,000)
      final inv1After = await ds.getPurchaseById(inv1.id);
      expect(inv1After!.paidAmount, 50000);
      expect(inv1After.paymentStatus, 'paid');

      // Invoice 2 should receive remaining 50,000 (50,000 / 80,000) -> partial
      final inv2After = await ds.getPurchaseById(inv2.id);
      expect(inv2After!.paidAmount, 50000);
      expect(inv2After.paymentStatus, 'partial');

      // Supplier balance should be 300 EGP (30,000 piasters)
      expect((await ds.getSupplierById(supplier.id))!.balance, 30000);
    });

    test('3. overpayment on specific invoice is rejected in validation / backend', () async {
      final supplier = await ds.addSupplier(name: 'مورد 3');

      // Invoice: 500 EGP (50,000 piasters), 0 advance
      final inv = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-SPECIFIC',
        purchaseDate: now,
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 50,
            costPrice: 1000,
          ),
        ],
        userId: 'admin',
      );

      // Trying to pay 700 EGP (70,000 piasters) on an invoice of 500 EGP should throw Exception
      expect(
        () async => ds.addSupplierPayment(
          supplierId: supplier.id,
          purchaseId: inv.id,
          amount: 70000,
          paymentDate: now,
          paymentMethod: 'كاش',
          userId: 'admin',
        ),
        throwsA(isA<Exception>()),
      );

      // Invoice should still be 0 paid
      final invAfter = await ds.getPurchaseById(inv.id);
      expect(invAfter!.paidAmount, 0);
      expect(invAfter.paymentStatus, 'unpaid');
    });

    test('4. advance > total is rejected in createPurchaseInvoice', () async {
      final supplier = await ds.addSupplier(name: 'مورد 4');

      // Total items = 1000 EGP (100,000 piasters), try advance = 1500 EGP (150,000 piasters)
      expect(
        () async => ds.createPurchaseInvoice(
          supplierId: supplier.id,
          invoiceNumber: 'INV-ADVANCE-EXCESS',
          purchaseDate: now,
          paidAmount: 150000,
          items: [
            const PurchaseItemDraft(
              variantId: 'var-test-1',
              qty: 100,
              costPrice: 1000,
            ),
          ],
          userId: 'admin',
        ),
        throwsA(isA<Exception>()),
      );

      // Supplier balance must remain 0
      expect((await ds.getSupplierById(supplier.id))!.balance, 0);
    });

    test('5. supplier balance = SUM(purchases) - SUM(payments) after mixed operations', () async {
      final supplier = await ds.addSupplier(name: 'مورد 5');

      // Purchase 1: 1000 EGP (100,000 piasters), advance 0 -> balance = 100,000
      await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-MIX-1',
        purchaseDate: now.subtract(const Duration(days: 3)),
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 100,
            costPrice: 1000,
          ),
        ],
        userId: 'admin',
      );
      expect((await ds.getSupplierById(supplier.id))!.balance, 100000);

      // Purchase 2: 500 EGP (50,000 piasters), advance 200 EGP (20,000 piasters) -> balance = 130,000
      await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-MIX-2',
        purchaseDate: now.subtract(const Duration(days: 2)),
        paidAmount: 20000,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-test-1',
            qty: 50,
            costPrice: 1000,
          ),
        ],
        userId: 'admin',
      );
      expect((await ds.getSupplierById(supplier.id))!.balance, 130000);

      // General payment: 800 EGP (80,000 piasters) -> balance = 50,000
      await ds.addSupplierPayment(
        supplierId: supplier.id,
        amount: 80000,
        paymentDate: now,
        paymentMethod: 'كاش',
        userId: 'admin',
      );

      // Final balance check
      final finalSupplier = await ds.getSupplierById(supplier.id);
      expect(finalSupplier!.balance, 50000); // 500 EGP

      // Direct DB source of truth verification:
      final purchasesRows = await (db.select(db.purchases)
            ..where((p) => p.supplierId.equals(supplier.id) & p.deletedAt.isNull()))
          .get();
      final totalPurchases = purchasesRows.fold<int>(0, (sum, p) => sum + p.totalAmount);

      final paymentsRows = await (db.select(db.supplierPayments)
            ..where((p) => p.supplierId.equals(supplier.id)))
          .get();
      final totalPayments = paymentsRows.fold<int>(0, (sum, p) => sum + p.amount);

      expect(totalPurchases, 150000); // 1000 + 500 EGP
      expect(totalPayments, 100000);  // 200 advance + 800 general
      expect(totalPurchases - totalPayments, 50000); // 500 EGP
      expect(finalSupplier.balance, totalPurchases - totalPayments);
    });
  });
}
