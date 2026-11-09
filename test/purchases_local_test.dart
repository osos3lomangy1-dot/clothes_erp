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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    ds = PurchasesLocalDataSourceImpl(db, branchProvider);
  });

  tearDown(() async {
    await db.close();
  });

  group('Suppliers CRUD Tests', () {
    test('addSupplier creates supplier with 0 balance', () async {
      final supplier = await ds.addSupplier(
        name: 'مصنع النور للملابس',
        phone: '01012345678',
        companyName: 'النور تكس',
        address: 'المحلة الكبرى',
      );

      expect(supplier.name, 'مصنع النور للملابس');
      expect(supplier.companyName, 'النور تكس');
      expect(supplier.balance, 0);

      final list = await ds.getSuppliers();
      expect(list.length, 1);
      expect(list.first.id, supplier.id);
    });

    test('updateSupplier modifies details', () async {
      final supplier = await ds.addSupplier(
        name: 'القديم',
        phone: '01000000000',
      );

      final updated = await ds.updateSupplier(
        id: supplier.id,
        name: 'الجديد بعد التعديل',
        phone: '01111111111',
        companyName: 'شركة النسيج الحديث',
      );

      expect(updated.name, 'الجديد بعد التعديل');
      expect(updated.phone, '01111111111');
      expect(updated.companyName, 'شركة النسيج الحديث');
    });

    test('deleteSupplier soft-deletes and excludes from list', () async {
      final supplier = await ds.addSupplier(name: 'مورد للحذف');
      expect((await ds.getSuppliers()).length, 1);

      await ds.deleteSupplier(supplier.id);

      final list = await ds.getSuppliers();
      expect(list.isEmpty, isTrue);
    });
  });

  group('Purchases & Stock & Debt Integration Tests', () {
    test('createPurchaseInvoice increases stock, updates costPrice, updates supplier balance, and records advance payment', () async {
      final branchId = await branchProvider.getBranchId();
      final now = DateTime.now();

      // 1. Seed Product & Variant
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              branchId: branchId,
              name: 'قمصان',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-1',
              branchId: branchId,
              categoryId: 'cat-1',
              name: 'قميص أكسفورد كاجوال',
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
              quantity: const Value(5), // Initial stock: 5 pieces
              costPrice: 10000, // 100 EGP
              sellPrice: 18000, // 180 EGP
              createdAt: now,
              updatedAt: now,
            ),
          );

      // 2. Add Supplier
      final supplier = await ds.addSupplier(
        name: 'مصنع الأهرام للغزل',
        companyName: 'الأهرام تكس',
      );

      // 3. Create Purchase: Buy 10 pieces at 120 EGP (12,000 piasters) = Total 120,000 piasters (1,200 EGP)
      // Pay 40,000 piasters (400 EGP) advance. Remaining debt = 80,000 piasters (800 EGP).
      final purchase = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-2026-001',
        purchaseDate: now,
        paidAmount: 40000,
        notes: 'دفعة أولى 400 والباقي آجل',
        items: [
          const PurchaseItemDraft(
            variantId: 'var-1',
            qty: 10,
            costPrice: 12000,
          ),
        ],
        userId: 'admin',
      );

      // Verify Purchase Entity
      expect(purchase.totalAmount, 120000);
      expect(purchase.paidAmount, 40000);
      expect(purchase.remainingAmount, 80000);
      expect(purchase.paymentStatus, 'partial');
      expect(purchase.status, 'received');
      expect(purchase.items.length, 1);
      expect(purchase.items.first.qty, 10);

      // Verify Stock Increased: 5 + 10 = 15 pieces
      final variantAfter = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(variantAfter.quantity, 15);
      expect(variantAfter.costPrice, 12000); // Updated to new cost price

      // Verify Inventory Log recorded
      final logs = await (db.select(db.inventoryLogs)..where((l) => l.refId.equals(purchase.id))).get();
      expect(logs.length, 1);
      expect(logs.first.type, 'in');
      expect(logs.first.qtyDelta, 10);
      expect(logs.first.refType, 'purchase');

      // Verify Supplier Debt updated: 800 EGP owed
      final supplierAfter = await ds.getSupplierById(supplier.id);
      expect(supplierAfter!.balance, 80000);

      // Verify advance payment recorded
      final payments = await ds.getSupplierPayments(purchaseId: purchase.id);
      expect(payments.length, 1);
      expect(payments.first.amount, 40000);

      // Verify Expense recorded
      final expenses = await (db.select(db.expenses)..where((e) => e.category.equals('مشتريات بضاعة'))).get();
      expect(expenses.length, 1);
      expect(expenses.first.amount, 40000);
    });

    test('addSupplierPayment reduces supplier debt and updates purchase payment status to paid', () async {
      final branchId = await branchProvider.getBranchId();
      final now = DateTime.now();

      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-2',
              branchId: branchId,
              name: 'بنطلونات',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-2',
              branchId: branchId,
              categoryId: 'cat-2',
              name: 'بنطلون جينز',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'var-2',
              branchId: branchId,
              productId: 'prod-2',
              sku: 'JNZ-32',
              color: 'كحلي',
              size: '32',
              quantity: const Value(0),
              costPrice: 20000,
              sellPrice: 35000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final supplier = await ds.addSupplier(name: 'مصنع الجينز الأصلي');

      // Buy 5 jeans at 200 EGP = 1,000 EGP (100,000 piasters). 0 paid (100% on credit)
      final purchase = await ds.createPurchaseInvoice(
        supplierId: supplier.id,
        invoiceNumber: 'INV-JNZ-50',
        purchaseDate: now,
        paidAmount: 0,
        items: [
          const PurchaseItemDraft(
            variantId: 'var-2',
            qty: 5,
            costPrice: 20000,
          ),
        ],
        userId: 'admin',
      );

      expect(purchase.paymentStatus, 'unpaid');
      expect((await ds.getSupplierById(supplier.id))!.balance, 100000);

      // Payment 1: Pay 600 EGP (60,000 piasters)
      final payment1 = await ds.addSupplierPayment(
        supplierId: supplier.id,
        purchaseId: purchase.id,
        amount: 60000,
        paymentDate: now,
        paymentMethod: 'كاش',
        notes: 'دفعة أولى 600 جنيه',
        userId: 'admin',
      );

      expect(payment1.amount, 60000);

      // Balance should be 400 EGP (40,000 piasters)
      final supplierAfterPay1 = await ds.getSupplierById(supplier.id);
      expect(supplierAfterPay1!.balance, 40000);

      // Purchase status should be partial
      final purchaseAfterPay1 = await ds.getPurchaseById(purchase.id);
      expect(purchaseAfterPay1!.paidAmount, 60000);
      expect(purchaseAfterPay1.paymentStatus, 'partial');

      // Payment 2: Pay remaining 400 EGP (40,000 piasters)
      await ds.addSupplierPayment(
        supplierId: supplier.id,
        purchaseId: purchase.id,
        amount: 40000,
        paymentDate: now,
        paymentMethod: 'تحويل بنكي',
        notes: 'تصفية الفاتورة بالكامل',
        userId: 'admin',
      );

      // Balance should be 0 (all clear!)
      final supplierAfterPay2 = await ds.getSupplierById(supplier.id);
      expect(supplierAfterPay2!.balance, 0);

      // Purchase status should be fully 'paid'
      final purchaseAfterPay2 = await ds.getPurchaseById(purchase.id);
      expect(purchaseAfterPay2!.paidAmount, 100000);
      expect(purchaseAfterPay2.remainingAmount, 0);
      expect(purchaseAfterPay2.paymentStatus, 'paid');
    });
  });
}

