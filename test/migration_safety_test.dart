import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';

void main() {
  group('Database Migration Safety & Idempotence Tests', () {
    late File tempDbFile;

    setUp(() {
      tempDbFile = File(
        '${Directory.systemTemp.path}/migration_safety_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      if (tempDbFile.existsSync()) {
        tempDbFile.deleteSync();
      }
    });

    tearDown(() {
      if (tempDbFile.existsSync()) {
        tempDbFile.deleteSync();
      }
    });

    test('Simulate upgrading an OLD v1 database to v2, and verify onUpgrade is idempotent when called multiple times', () async {
      // -----------------------------------------------------------------------
      // STEP 1: Create an old database with schemaVersion = 1
      // (without wholesale_price, discount_percent, customer_type, salary)
      // -----------------------------------------------------------------------
      final setupDb = AppDatabase(NativeDatabase(tempDbFile));

      // Trigger table creation with schemaVersion = 2 initially
      await setupDb.customSelect('SELECT 1').get();

      // Drop the 4 new columns to exactly simulate the v1 schema
      await setupDb.customStatement('ALTER TABLE product_variants DROP COLUMN wholesale_price');
      await setupDb.customStatement('ALTER TABLE customers DROP COLUMN discount_percent');
      await setupDb.customStatement('ALTER TABLE customers DROP COLUMN customer_type');
      await setupDb.customStatement('ALTER TABLE users DROP COLUMN salary');

      // Set PRAGMA user_version back to 1 (Old schema version)
      await setupDb.customStatement('PRAGMA user_version = 1');

      // Verify that the columns do NOT exist in v1
      Future<Set<String>> getColNames(String table) async {
        final rows = await setupDb.customSelect('PRAGMA table_info("$table")').get();
        return rows.map((r) => (r.data['name'] as String).toLowerCase()).toSet();
      }

      final variantsColsV1 = await getColNames('product_variants');
      expect(variantsColsV1.contains('wholesale_price'), isFalse);

      final customersColsV1 = await getColNames('customers');
      expect(customersColsV1.contains('discount_percent'), isFalse);
      expect(customersColsV1.contains('customer_type'), isFalse);

      final usersColsV1 = await getColNames('users');
      expect(usersColsV1.contains('salary'), isFalse);

      await setupDb.close();

      // -----------------------------------------------------------------------
      // STEP 2: Open the database with AppDatabase (simulates app startup with schemaVersion = 2)
      // This will trigger Drift's onUpgrade from 1 to 2.
      // -----------------------------------------------------------------------
      final upgradedDb = AppDatabase(NativeDatabase(tempDbFile));

      // Running a query triggers Drift open + onUpgrade
      await upgradedDb.customSelect('SELECT 1').get();

      // Verify user_version was bumped to 2
      final versionResult = await upgradedDb.customSelect('PRAGMA user_version').getSingle();
      expect(versionResult.data['user_version'], equals(2));

      // -----------------------------------------------------------------------
      // STEP 3: Call onUpgrade a SECOND time (to simulate running when columns already exist,
      // e.g. after a previous failed upgrade or repeated migration execution)
      // -----------------------------------------------------------------------
      final migrator = upgradedDb.createMigrator();

      // Calling onUpgrade again MUST NOT throw a 'duplicate column' exception!
      await expectLater(
        upgradedDb.migration.onUpgrade(migrator, 1, 2),
        completes,
      );

      // Call it a THIRD time to be 100% sure it is fully idempotent
      await expectLater(
        upgradedDb.migration.onUpgrade(migrator, 1, 2),
        completes,
      );

      // -----------------------------------------------------------------------
      // STEP 4: Assert all 4 columns exist in the database
      // -----------------------------------------------------------------------
      final variantsRows = await upgradedDb.customSelect('PRAGMA table_info("product_variants")').get();
      final variantsColsV2 = variantsRows.map((r) => (r.data['name'] as String).toLowerCase()).toSet();
      expect(variantsColsV2.contains('wholesale_price'), isTrue);

      final customersRows = await upgradedDb.customSelect('PRAGMA table_info("customers")').get();
      final customersColsV2 = customersRows.map((r) => (r.data['name'] as String).toLowerCase()).toSet();
      expect(customersColsV2.contains('discount_percent'), isTrue);
      expect(customersColsV2.contains('customer_type'), isTrue);

      final usersRows = await upgradedDb.customSelect('PRAGMA table_info("users")').get();
      final usersColsV2 = usersRows.map((r) => (r.data['name'] as String).toLowerCase()).toSet();
      expect(usersColsV2.contains('salary'), isTrue);

      // -----------------------------------------------------------------------
      // STEP 5: Test inserting and querying rows using all 4 new columns
      // -----------------------------------------------------------------------
      final now = DateTime.now();

      // Test 1: product_variants.wholesale_price
      await upgradedDb.into(upgradedDb.categories).insert(
        CategoriesCompanion.insert(
          id: 'cat-mig-1',
          branchId: 'b-1',
          name: 'قمصان صيفية',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await upgradedDb.into(upgradedDb.products).insert(
        ProductsCompanion.insert(
          id: 'prod-mig-1',
          branchId: 'b-1',
          name: 'قميص صيفي كتان',
          categoryId: 'cat-mig-1',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await upgradedDb.into(upgradedDb.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: 'var-mig-1',
          branchId: 'b-1',
          productId: 'prod-mig-1',
          sku: 'LINEN-WHT-XL',
          color: 'أبيض',
          size: 'XL',
          quantity: const Value(25),
          costPrice: 4000,
          sellPrice: 9000,
          wholesalePrice: const Value(6500),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final fetchedVariant = await (upgradedDb.select(upgradedDb.productVariants)
            ..where((v) => v.id.equals('var-mig-1')))
          .getSingle();
      expect(fetchedVariant.wholesalePrice, equals(6500));

      // Test 2: customers.discount_percent & customer_type
      await upgradedDb.into(upgradedDb.customers).insert(
        CustomersCompanion.insert(
          id: 'cust-mig-1',
          branchId: 'b-1',
          name: 'شركة الأمل للتجارة',
          phone: '01122334455',
          discountPercent: const Value(20),
          customerType: const Value('wholesale'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final fetchedCustomer = await (upgradedDb.select(upgradedDb.customers)
            ..where((c) => c.id.equals('cust-mig-1')))
          .getSingle();
      expect(fetchedCustomer.discountPercent, equals(20));
      expect(fetchedCustomer.customerType, equals('wholesale'));

      // Test 3: users.salary
      await upgradedDb.into(upgradedDb.users).insert(
        UsersCompanion.insert(
          id: 'user-mig-1',
          branchId: 'b-1',
          username: 'karim_pos',
          displayName: 'كريم محمود',
          role: 'cashier',
          passwordHash: 'hash_pass123',
          passwordSalt: 'salt_xyz',
          salary: const Value(750000), // 7500 EGP
          createdAt: now,
          updatedAt: now,
        ),
      );

      final fetchedUser = await (upgradedDb.select(upgradedDb.users)
            ..where((u) => u.id.equals('user-mig-1')))
          .getSingle();
      expect(fetchedUser.salary, equals(750000));
      expect(fetchedUser.displayName, equals('كريم محمود'));

      await upgradedDb.close();
    });

    test('In-memory database onUpgrade is safe when called multiple times on the same connection', () async {
      final db = AppDatabase(NativeDatabase.memory());

      // Open database
      await db.customSelect('SELECT 1').get();

      final migrator = db.createMigrator();

      // Calling onUpgrade again directly when columns already exist MUST complete cleanly
      await expectLater(
        db.migration.onUpgrade(migrator, 1, 2),
        completes,
      );

      // Call it once more
      await expectLater(
        db.migration.onUpgrade(migrator, 1, 2),
        completes,
      );

      await db.close();
    });
  });
}
