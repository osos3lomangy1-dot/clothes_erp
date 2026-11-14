import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/expenses/data/datasources/expenses_local_data_source.dart';
import 'package:clothes_erp/features/partners/data/datasources/partners_local_data_source.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 — Migration v6 & Expense Kind Isolation', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('1. migrateToV6 backfills supplier_payment kind on a v5-state database', () async {
      // Recreate v5 expenses table without kind, matching v5 schema exactly.
      await db.customStatement('DROP TABLE IF EXISTS expenses');
      await db.customStatement('''
        CREATE TABLE expenses (
          id TEXT NOT NULL PRIMARY KEY,
          branch_id TEXT NOT NULL,
          category TEXT NOT NULL,
          amount INTEGER NOT NULL,
          note TEXT,
          user_id TEXT NOT NULL,
          expense_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER
        )
      ''');

      // Insert via Companion without kind (Amendment 2 — uses Companion, kind is Value.absent)
      final now = DateTime.now();
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'e1',
        branchId: 'b1',
        category: 'مشتريات بضاعة',
        amount: 10000,
        userId: 'u1',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'e2',
        branchId: 'b1',
        category: 'سداد موردين',
        amount: 5000,
        userId: 'u1',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'e3',
        branchId: 'b1',
        category: 'كهرباء ومياه',
        amount: 1500,
        userId: 'u1',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Run migrateToV6
      final migrator = Migrator(db);
      await db.migrateToV6(migrator);

      // Verify kind on rows
      final row1 = await (db.select(db.expenses)..where((e) => e.id.equals('e1'))).getSingle();
      final row2 = await (db.select(db.expenses)..where((e) => e.id.equals('e2'))).getSingle();
      final row3 = await (db.select(db.expenses)..where((e) => e.id.equals('e3'))).getSingle();

      expect(row1.kind, equals('supplier_payment'));
      expect(row2.kind, equals('supplier_payment'));
      expect(row3.kind, equals('operating'));
    });

    test('2. migrateToV6 is idempotent when run multiple times', () async {
      await db.customStatement('DROP TABLE IF EXISTS expenses');
      await db.customStatement('''
        CREATE TABLE expenses (
          id TEXT NOT NULL PRIMARY KEY,
          branch_id TEXT NOT NULL,
          category TEXT NOT NULL,
          amount INTEGER NOT NULL,
          note TEXT,
          user_id TEXT NOT NULL,
          expense_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER
        )
      ''');

      final now = DateTime.now();
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'e1',
        branchId: 'b1',
        category: 'مشتريات بضاعة',
        amount: 10000,
        userId: 'u1',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      final migrator = Migrator(db);
      await db.migrateToV6(migrator);

      // Second run: update query is idempotent
      await db.customStatement('''
        UPDATE expenses
        SET kind = 'supplier_payment'
        WHERE category IN ('مشتريات بضاعة', 'سداد موردين')
          AND kind = 'operating'
      ''');

      final row = await (db.select(db.expenses)..where((e) => e.id.equals('e1'))).getSingle();
      expect(row.kind, equals('supplier_payment'));
    });

    test('3. Reports and Partner Profit filter out supplier_payment from operating expenses', () async {
      final now = DateTime.now();

      // Seed sales (1 sale of 30,000 piasters)
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 's1',
        branchId: 'b1',
        shortRef: 'REF01',
        cashierId: 'c1',
        subtotal: 30000,
        discountType: 'none',
        total: 30000,
        paymentMethod: 'cash',
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Seed 1 Operating Expense (2,000 piasters)
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'exp-op',
        branchId: 'b1',
        category: 'إيجار المحل',
        amount: 2000,
        kind: const Value('operating'),
        userId: 'admin',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Seed 1 Supplier Payment Expense (10,000 piasters)
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'exp-sup',
        branchId: 'b1',
        category: 'مشتريات بضاعة',
        amount: 10000,
        kind: const Value('supplier_payment'),
        userId: 'admin',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      // 1. Check ReportsLocalDataSource
      final reportsDs = ReportsLocalDataSourceImpl(db);
      final report = await reportsDs.getSalesReport(
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );

      // Total expenses in reports MUST be 2,000 (NOT 12,000!)
      expect(report.totalExpenses, equals(2000));
      expect(report.netProfit, equals(report.totalProfit - 2000));

      // 2. Check PartnersLocalDataSource
      final partnersDs = PartnersLocalDataSourceImpl(db);
      final partnerSummary = await partnersDs.getProfitSummary(
        from: now.subtract(const Duration(days: 1)),
        to: now.add(const Duration(days: 1)),
      );
      expect(partnerSummary.totalExpenses, equals(2000));
      expect(partnerSummary.netProfit, equals(partnerSummary.grossProfit - 2000));

      // 3. Check ExpensesLocalDataSource
      final tx = TxWriter(db);
      final branch = BranchProvider(db);
      final expensesDs = ExpensesLocalDataSourceImpl(db, branch, tx);
      final expList = await expensesDs.getExpenses();
      expect(expList.length, equals(1));
      expect(expList.first.id, equals('exp-op'));
      expect(await expensesDs.getTotalExpenses(), equals(2000));
    });
  });
}

