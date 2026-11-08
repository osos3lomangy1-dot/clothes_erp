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

    test('schemaVersion must be 2', () {
      expect(db.schemaVersion, equals(2));
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
  });
}

