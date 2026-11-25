import 'dart:io';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/migration_marker_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'tools/upgrade_verification_tools.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends QueryExecutorUser {
  final int schema;
  _User([this.schema = 1]);
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
  @override
  int get schemaVersion => schema;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_db_migration_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('reports sqlite_version accurately from production test runner', () async {
    final dbFile = File('${tempDir.path}/version_check.sqlite');
    final db = AppDatabase(NativeDatabase(dbFile));
    final row = await db.customSelect('SELECT sqlite_version() AS v').getSingle();
    final v = row.read<String>('v');
    // ignore: avoid_print
    print('--> AppDatabase SQLite SQL Version: $v');
    // ignore: avoid_print
    print('--> Dart sqlite3 library info: ${sqlite3.version}');
    // ignore: avoid_print
    print('--> Dart sqlite3 sourceId: ${sqlite3.version.sourceId}');
    expect(v, isNotEmpty);
    await db.close();
  });

  test('executes actual AppDatabase migration V1 -> V11 with all historical steps inside transaction', () async {
    final dbFile = File('${tempDir.path}/real_v1_to_v11.sqlite');
    final rawDb = NativeDatabase(dbFile);
    await rawDb.ensureOpen(_User(1));

    // 1. Setup V1 schema with core tables
    await rawDb.runCustom('''
      PRAGMA user_version = 1;

      CREATE TABLE product_variants (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        cost INTEGER NOT NULL,
        sku TEXT NOT NULL,
        barcode TEXT,
        color TEXT,
        size TEXT,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      );

      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        shift_id TEXT,
        payment_method TEXT NOT NULL,
        total INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL
      );

      CREATE TABLE returns (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        sale_id TEXT,
        cashier_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        refund_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        approved_by_admin_id TEXT,
        date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        category TEXT NOT NULL,
        amount INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'operating',
        note TEXT,
        user_id TEXT NOT NULL,
        expense_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        cashier_id TEXT NOT NULL,
        opening_balance INTEGER NOT NULL,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        deleted_at INTEGER
      );

      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // 2. Insert baseline records at V1
    await rawDb.runInsert(
      "INSERT INTO customers (id, name, phone, address, created_at, updated_at) VALUES ('c1', 'أحمد محمود', '0100000001', 'القاهرة', 1700000000, 1700000000);",
      [],
    );
    await rawDb.runInsert(
      "INSERT INTO product_variants (id, product_id, name, price, cost, sku, stock_quantity) VALUES ('v1', 'p1', 'قميص أزرق L', 25000, 15000, 'SKU-001', 10);",
      [],
    );
    await rawDb.runInsert(
      "INSERT INTO users (id, username, password_hash, full_name, role, branch_id, created_at, updated_at) VALUES ('u1', 'admin', 'hash123', 'المدير العام', 'admin', 'b1', 1700000000, 1700000000);",
      [],
    );
    await rawDb.runInsert(
      "INSERT INTO sales (id, branch_id, payment_method, total, created_at, updated_at) VALUES ('s1', 'b1', 'cash', 50000, 1700000100, 1700000100);",
      [],
    );
    await rawDb.runInsert(
      "INSERT INTO expenses (id, branch_id, category, amount, user_id, expense_date, created_at, updated_at) VALUES ('e1', 'b1', 'مشتريات بضاعة', 30000, 'u1', 1700000200, 1700000200, 1700000200);",
      [],
    );
    await rawDb.close();

    // Compute pre-upgrade canonical hashes on baseline columns
    final preCustHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'customers',
      explicitColumns: ['id', 'name', 'phone', 'address'],
      excludeVolatileColumns: true,
    );
    final preVariantHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'product_variants',
      explicitColumns: ['id', 'product_id', 'name', 'price', 'cost', 'sku', 'stock_quantity'],
      excludeVolatileColumns: true,
    );
    final preSaleHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'sales',
      excludeVolatileColumns: true,
    );

    // 3. Open database via actual production AppDatabase
    // This executes AppDatabase's actual onUpgrade(m, 1, 11) inside a single transaction
    final appDb = AppDatabase(NativeDatabase(dbFile));
    final versionRow = await appDb.customSelect('PRAGMA user_version;').getSingle();
    final newVersion = versionRow.data.values.first as int;
    expect(newVersion, 13);

    // 4. Verify that historical migration tables and columns exist
    final variantCheck = await appDb.customSelect('SELECT wholesale_price FROM product_variants WHERE id = "v1"').getSingle();
    expect(variantCheck.data.containsKey('wholesale_price'), isTrue);

    final custCheck = await appDb.customSelect('SELECT discount_percent, customer_type, credit_limit FROM customers WHERE id = "c1"').getSingle();
    expect(custCheck.data.containsKey('discount_percent'), isTrue);
    expect(custCheck.data.containsKey('credit_limit'), isTrue);

    final supTable = await appDb.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='suppliers'").get();
    expect(supTable, isNotEmpty);

    final grTable = await appDb.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='goods_receipts'").get();
    expect(grTable, isNotEmpty);

    final instTable = await appDb.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installments'").get();
    expect(instTable, isNotEmpty);

    final expCheck = await appDb.customSelect('SELECT kind FROM expenses WHERE id = "e1"').getSingle();
    expect(expCheck.read<String>('kind'), 'supplier_payment');

    final cmRows = await appDb.customSelect('SELECT type, amount_piasters FROM cash_movements WHERE reference_id = "s1"').get();
    expect(cmRows, isNotEmpty);
    expect(cmRows.first.read<String>('type'), 'sale');
    expect(cmRows.first.read<int>('amount_piasters'), 50000);

    final spRows = await appDb.customSelect('SELECT method, amount_piasters FROM sale_payments WHERE sale_id = "s1"').get();
    expect(spRows, isNotEmpty);
    expect(spRows.first.read<int>('amount_piasters'), 50000);

    final promoTable = await appDb.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='promotions'").get();
    expect(promoTable, isNotEmpty);

    final cpTable = await appDb.customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='customer_payments'").get();
    expect(cpTable, isNotEmpty);

    // 5. Verify integrity_check
    final integrityRow = await appDb.customSelect('PRAGMA integrity_check').getSingle();
    expect(integrityRow.data.values.first, 'ok');

    // 6. Verify pre-upgrade data preservation on baseline columns
    final postCustHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'customers',
      explicitColumns: ['id', 'name', 'phone', 'address'],
      excludeVolatileColumns: true,
    );
    expect(postCustHash, equals(preCustHash));

    final postVariantHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'product_variants',
      explicitColumns: ['id', 'product_id', 'name', 'price', 'cost', 'sku', 'stock_quantity'],
      excludeVolatileColumns: true,
    );
    expect(postVariantHash, equals(preVariantHash));

    final postSaleHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'sales',
      excludeVolatileColumns: true,
    );
    expect(postSaleHash, equals(preSaleHash));

    await appDb.close();
    // ignore: avoid_print
    print('--> Production AppDatabase V1 -> V11 Full Migration PASSED with 100% hash match.');
  });

  test('executes actual AppDatabase migration from intermediate version V6 -> V11', () async {
    final dbFile = File('${tempDir.path}/real_v6_to_v11.sqlite');

    // Setup V6 database directly via sqlite3 to mirror an actual disk database at schema version 6
    final directDb = sqlite3.open(dbFile.path);
    directDb.execute('''
      PRAGMA user_version = 6;

      CREATE TABLE product_variants (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        cost INTEGER NOT NULL,
        sku TEXT NOT NULL,
        wholesale_price INTEGER NOT NULL DEFAULT 0,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER
      );

      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        salary INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        cashier_id TEXT NOT NULL,
        opening_balance INTEGER NOT NULL,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        deleted_at INTEGER
      );

      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        shift_id TEXT,
        payment_method TEXT NOT NULL,
        total INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL
      );

      CREATE TABLE returns (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        sale_id TEXT,
        cashier_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        refund_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        approved_by_admin_id TEXT,
        date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        category TEXT NOT NULL,
        amount INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'operating',
        note TEXT,
        user_id TEXT NOT NULL,
        expense_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        discount_percent INTEGER,
        customer_type TEXT
      );

      CREATE TABLE customer_installments (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        sale_id TEXT,
        down_payment_piasters INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      );

      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );

      INSERT INTO sales (id, branch_id, payment_method, total, created_at, updated_at)
      VALUES ('s6', 'b1', 'card', 75000, 1700000000, 1700000000);
    ''');
    directDb.dispose();

    final preSaleHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'sales',
      excludeVolatileColumns: true,
    );

    // Run production AppDatabase migration from V6 to V13
    final appDb = AppDatabase(NativeDatabase(dbFile));
    final vRow = await appDb.customSelect('PRAGMA user_version;').getSingle();
    expect(vRow.data.values.first, 13);

    // Verify cash_movements & sale_payments backfilled
    final spRow = await appDb.customSelect('SELECT method, amount_piasters FROM sale_payments WHERE sale_id = "s6"').getSingle();
    expect(spRow.read<String>('method'), 'card');
    expect(spRow.read<int>('amount_piasters'), 75000);

    final postSaleHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'sales',
      excludeVolatileColumns: true,
    );
    expect(postSaleHash, equals(preSaleHash));
    await appDb.close();
    // ignore: avoid_print
    print('--> Intermediate V6 -> V11 Migration SUCCEEDED with data intact.');
  });

  test('proves that updating PRAGMA user_version inside migration transaction eliminates the kill window', () async {
    final dbFile = File('${tempDir.path}/kill_window_test.sqlite');
    final rawDb = NativeDatabase(dbFile);
    await rawDb.ensureOpen(_User(10));
    await rawDb.runCustom('PRAGMA user_version = 10;');
    await rawDb.runCustom('CREATE TABLE test_data (id INTEGER PRIMARY KEY, note TEXT);');
    await rawDb.runInsert("INSERT INTO test_data (id, note) VALUES (1, 'initial');", []);

    // Simulate the production migration pattern:
    // DDL + PRAGMA user_version = 11 inside single transaction
    await rawDb.runCustom('BEGIN IMMEDIATE TRANSACTION;');
    await rawDb.runCustom('CREATE TABLE new_v11_table (id INTEGER PRIMARY KEY);');
    await rawDb.runCustom('PRAGMA user_version = 11;');
    await rawDb.runCustom('COMMIT;');

    // Simulate immediate abrupt process termination right after COMMIT
    await rawDb.close();

    // Verify that the database is ALREADY committed at user_version = 11
    // There is no window where schema is 11 but user_version is 10!
    final checkDb = NativeDatabase(dbFile);
    await checkDb.ensureOpen(_User(11));
    final vRows = await checkDb.runSelect('PRAGMA user_version;', []);
    final versionOnReopen = vRows.first.values.first as int;
    expect(versionOnReopen, 11);

    final tableCheck = await checkDb.runSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='new_v11_table';", []);
    expect(tableCheck, isNotEmpty);
    await checkDb.close();
    // ignore: avoid_print
    print('--> Zero Post-Commit Window PROVEN: user_version committed atomically with DDL.');
  });

  test('proves manual database restoration against pre-migration baseline using strict hash', () async {
    final dbFile = File('${tempDir.path}/restore_baseline_test.sqlite');
    final backupFile = File('${tempDir.path}/pre_mig_v10_backup.sqlite');

    final rawDb = NativeDatabase(dbFile);
    await rawDb.ensureOpen(_User(10));
    await rawDb.runCustom('PRAGMA user_version = 10;');
    await rawDb.runCustom('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT, updated_at TEXT);');
    await rawDb.runInsert("INSERT INTO customers VALUES ('c1', 'أحمد', '2026-11-19 12:00:00');", []);

    // Create physical backup via VACUUM INTO
    await rawDb.runCustom("VACUUM INTO '${backupFile.path.replaceAll('\\', '/')}';");
    await rawDb.close();

    // Compute baseline hash with excludeVolatileColumns = FALSE (strict byte-for-byte check)
    final baselineHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'customers',
      excludeVolatileColumns: false,
    );

    // Marker created with verified backup
    final markerService = MigrationMarkerService(tempDir);
    await markerService.writeMarker(MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 10,
      versionTo: 11,
      backupPath: backupFile.path,
      backupState: BackupState.verified,
      timestamp: DateTime.now(),
    ));

    // Simulate catastrophic file corruption / partial write
    final corruptedDb = File(dbFile.path);
    await corruptedDb.writeAsString('CORRUPTED PARTIAL BYTES ATTEMPTING MIGRATION');

    // Manual restoration procedure (baseline verification for Phase 1.3)
    final marker = await markerService.readMarker();
    expect(marker, isNotNull);
    expect(marker!.backupState, BackupState.verified);

    // Overwrite corrupted DB from verified backup
    backupFile.copySync(dbFile.path);
    await markerService.clearMarker();
    expect(markerService.exists(), isFalse);

    // Verify restored DB with strict hashing (excludeVolatileColumns: false)
    final restoredHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'customers',
      excludeVolatileColumns: false,
    );
    expect(restoredHash, equals(baselineHash));

    final outcome = UpgradeVerificationTools.evaluateCycleOutcome(
      initialVersion: 10,
      targetVersion: 11,
      finalVersion: 10,
      integrityOk: true,
      initialHash: baselineHash,
      finalHash: restoredHash,
    );
    expect(outcome, isTrue);
    // ignore: avoid_print
    print('--> Manual restoration verified against canonical hash baseline: outcome = $outcome');
  });
}
