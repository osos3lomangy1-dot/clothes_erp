import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';

void main() {
  group('Schema Verification & Migration Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion must be 3', () {
      expect(db.schemaVersion, equals(3));
    });

    test('Insert and query customers table with discountPercent & customerType', () async {
      final now = DateTime.now();

      await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: 'cust-test-1',
          branchId: 'branch-main',
          name: 'عميل جملة تجريبي',
          phone: '01012345678',
          discountPercent: const drift.Value(15),
          customerType: const drift.Value('wholesale'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final customer = await (db.select(db.customers)..where((c) => c.id.equals('cust-test-1'))).getSingle();

      expect(customer.id, equals('cust-test-1'));
      expect(customer.name, equals('عميل جملة تجريبي'));
      expect(customer.phone, equals('01012345678'));
      expect(customer.discountPercent, equals(15));
      expect(customer.customerType, equals('wholesale'));
      expect(customer.loyaltyPoints, equals(0));
    });

    test('Insert and query product_variants with wholesalePrice', () async {
      final now = DateTime.now();

      // 1. Insert Category
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: 'cat-test-1',
          branchId: 'branch-main',
          name: 'قمصان',
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 2. Insert Product
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod-test-1',
          branchId: 'branch-main',
          name: 'قميص أكسفورد أزرق',
          categoryId: 'cat-test-1',
          minStock: const drift.Value(5),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 3. Insert Variant with wholesalePrice
      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: 'var-test-1',
          branchId: 'branch-main',
          productId: 'prod-test-1',
          sku: 'OX-BLU-L',
          color: 'أزرق',
          size: 'L',
          quantity: const drift.Value(12),
          costPrice: 5000, // 50.00 EGP
          sellPrice: 10000, // 100.00 EGP
          wholesalePrice: const drift.Value(7500), // 75.00 EGP
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 4. Query back
      final variant = await (db.select(db.productVariants)..where((v) => v.id.equals('var-test-1'))).getSingle();

      expect(variant.id, equals('var-test-1'));
      expect(variant.sku, equals('OX-BLU-L'));
      expect(variant.costPrice, equals(5000));
      expect(variant.sellPrice, equals(10000));
      expect(variant.wholesalePrice, equals(7500));
    });

    test('Verify exact low-stock query from dashboard/inventory screen runs without error', () async {
      final now = DateTime.now();

      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: 'cat-low-1',
          branchId: 'branch-main',
          name: 'بنطلونات',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'prod-low-1',
          branchId: 'branch-main',
          name: 'جينز سليم',
          categoryId: 'cat-low-1',
          minStock: const drift.Value(10),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: 'var-low-1',
          branchId: 'branch-main',
          productId: 'prod-low-1',
          sku: 'JN-SLM-32',
          color: 'كحلي',
          size: '32',
          quantity: const drift.Value(3), // <= minStock 10
          costPrice: 8000,
          sellPrice: 15000,
          wholesalePrice: const drift.Value(12000),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // This query mirrors the one in the user screenshot:
      // SELECT product_variants.*, products.* FROM product_variants INNER JOIN products ... WHERE quantity <= min_stock
      final query = db.select(db.productVariants).join([
        drift.innerJoin(db.products, db.products.id.equalsExp(db.productVariants.productId)),
      ])..where(
          db.productVariants.deletedAt.isNull() &
          db.products.deletedAt.isNull() &
          db.productVariants.quantity.isSmallerOrEqual(db.products.minStock),
        );

      final rows = await query.get();
      expect(rows, hasLength(1));

      final firstRowVariant = rows.first.readTable(db.productVariants);
      final firstRowProduct = rows.first.readTable(db.products);

      expect(firstRowVariant.wholesalePrice, equals(12000));
      expect(firstRowProduct.name, equals('جينز سليم'));
    });

    test('Insert and query users table with salary field', () async {
      final now = DateTime.now();

      await db.into(db.users).insert(
        UsersCompanion.insert(
          id: 'emp-101',
          branchId: 'branch-main',
          username: 'ahmed_cashier',
          displayName: 'أحمد الكاشير',
          role: 'cashier',
          passwordHash: 'dummy_hash',
          passwordSalt: 'dummy_salt',
          salary: const drift.Value(600000), // 6000 EGP in piasters
          createdAt: now,
          updatedAt: now,
        ),
      );

      final emp = await (db.select(db.users)..where((u) => u.id.equals('emp-101'))).getSingle();
      expect(emp.salary, equals(600000));
      expect(emp.displayName, equals('أحمد الكاشير'));
    });

    test('Verify expenses table CRUD operates properly with custom categories', () async {
      final now = DateTime.now();

      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: 'exp-101',
          branchId: 'branch-main',
          category: 'بوفيه وضيافة مميزة',
          amount: 25000, // 250.00 EGP
          note: const drift.Value('شاي وسكر وقهوة للمحل'),
          userId: 'user-admin',
          expenseDate: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final exp = await (db.select(db.expenses)..where((e) => e.id.equals('exp-101'))).getSingle();
      expect(exp.amount, equals(25000));
      expect(exp.category, equals('بوفيه وضيافة مميزة'));
      expect(exp.note, equals('شاي وسكر وقهوة للمحل'));
    });

    test('Insert and query suppliers table in schema v3', () async {
      final now = DateTime.now();

      await db.into(db.suppliers).insert(
        SuppliersCompanion.insert(
          id: 'sup-1',
          branchId: 'branch-main',
          name: 'مصنع الأمل للملابس',
          phone: const drift.Value('01123456789'),
          companyName: const drift.Value('شركة الأمل للتريكو'),
          balance: const drift.Value(500000), // 5000.00 EGP
          createdAt: now,
          updatedAt: now,
        ),
      );

      final sup = await (db.select(db.suppliers)..where((s) => s.id.equals('sup-1'))).getSingle();
      expect(sup.name, equals('مصنع الأمل للملابس'));
      expect(sup.balance, equals(500000));
      expect(sup.companyName, equals('شركة الأمل للتريكو'));
    });

    test('Insert and query purchases and purchase_items in schema v3', () async {
      final now = DateTime.now();

      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: 'po-101',
          branchId: 'branch-main',
          supplierId: 'sup-1',
          invoiceNumber: const drift.Value('INV-2026-99'),
          purchaseDate: now,
          totalAmount: 1000000, // 10000.00 EGP
          paidAmount: const drift.Value(400000), // 4000.00 EGP
          status: const drift.Value('pending'),
          paymentStatus: const drift.Value('partial'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.purchaseItems).insert(
        PurchaseItemsCompanion.insert(
          id: 'poi-1',
          purchaseId: 'po-101',
          variantId: 'var-1',
          qty: 50,
          costPrice: 20000,
          totalCost: 1000000,
          createdAt: now,
        ),
      );

      final po = await (db.select(db.purchases)..where((p) => p.id.equals('po-101'))).getSingle();
      expect(po.totalAmount, equals(1000000));
      expect(po.paidAmount, equals(400000));
      expect(po.paymentStatus, equals('partial'));

      final items = await (db.select(db.purchaseItems)..where((i) => i.purchaseId.equals('po-101'))).get();
      expect(items.length, equals(1));
      expect(items.first.qty, equals(50));
    });

    test('Insert and query supplier_payments in schema v3', () async {
      final now = DateTime.now();

      await db.into(db.supplierPayments).insert(
        SupplierPaymentsCompanion.insert(
          id: 'pay-1',
          branchId: 'branch-main',
          supplierId: 'sup-1',
          purchaseId: const drift.Value('po-101'),
          amount: 600000, // 6000.00 EGP
          paymentDate: now,
          paymentMethod: const drift.Value('cash'),
          createdBy: 'admin',
          createdAt: now,
        ),
      );

      final payment = await (db.select(db.supplierPayments)..where((p) => p.id.equals('pay-1'))).getSingle();
      expect(payment.amount, equals(600000));
      expect(payment.supplierId, equals('sup-1'));
      expect(payment.purchaseId, equals('po-101'));
    });

    test('Insert and query loyalty_transactions in schema v3', () async {
      final now = DateTime.now();

      await db.into(db.loyaltyTransactions).insert(
        LoyaltyTransactionsCompanion.insert(
          id: 'loy-1',
          branchId: 'branch-main',
          customerId: 'cust-1',
          saleId: const drift.Value('sale-101'),
          pointsDelta: 25,
          reason: 'earn_from_sale',
          createdAt: now,
        ),
      );

      final transaction = await (db.select(db.loyaltyTransactions)..where((l) => l.id.equals('loy-1'))).getSingle();
      expect(transaction.pointsDelta, equals(25));
      expect(transaction.reason, equals('earn_from_sale'));
    });

    test('Verify default loyalty settings are seeded in app_meta on upgrade to schema v3', () async {
      final migrator = db.createMigrator();
      await db.migration.onUpgrade(migrator, 2, 3);

      final earnRate = await (db.select(db.appMeta)..where((m) => m.key.equals('loyalty_earn_rate'))).getSingleOrNull();
      final redeemRate = await (db.select(db.appMeta)..where((m) => m.key.equals('loyalty_redeem_rate'))).getSingleOrNull();
      final maxPercent = await (db.select(db.appMeta)..where((m) => m.key.equals('loyalty_max_redeem_percent'))).getSingleOrNull();

      expect(earnRate?.value, equals('10'));
      expect(redeemRate?.value, equals('10'));
      expect(maxPercent?.value, equals('30'));
    });
  });
}

