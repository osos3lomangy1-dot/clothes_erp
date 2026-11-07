import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/expenses/data/datasources/expenses_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late ExpensesLocalDataSource ds;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    ds = ExpensesLocalDataSourceImpl(db, bp, tx);
  });

  tearDown(() async {
    tx.beforeAuditWrite = null;
    await db.close();
  });

  test('add expense and list expenses', () async {
    final now = DateTime.now();
    final expense = await ds.addExpense(
      category: 'إيجار المحل',
      amount: 500000, // 5000 EGP in piasters
      note: 'إيجار شهر نوفمبر',
      expenseDate: now,
      userId: 'user1',
    );

    expect(expense.category, 'إيجار المحل');
    expect(expense.amount, 500000);
    expect(expense.formattedAmount, '5000.00 ج.م');

    final list = await ds.getExpenses();
    expect(list.length, 1);
    expect(list.first.id, expense.id);

    final total = await ds.getTotalExpenses();
    expect(total, 500000);
  });

  test('filter expenses by category and date', () async {
    final d1 = DateTime(2026, 11, 1);
    final d2 = DateTime(2026, 11, 5);

    await ds.addExpense(
      category: 'كهرباء ومياه',
      amount: 25000,
      expenseDate: d1,
      userId: 'user1',
    );
    await ds.addExpense(
      category: 'مرتبات وبدلات',
      amount: 150000,
      expenseDate: d2,
      userId: 'user1',
    );

    final filteredCat = await ds.getExpenses(category: 'كهرباء ومياه');
    expect(filteredCat.length, 1);
    expect(filteredCat.first.amount, 25000);

    final filteredDate = await ds.getExpenses(
      from: DateTime(2026, 11, 3),
      to: DateTime(2026, 11, 10),
    );
    expect(filteredDate.length, 1);
    expect(filteredDate.first.category, 'مرتبات وبدلات');
  });

  test('soft delete expense excludes from total and list', () async {
    final expense = await ds.addExpense(
      category: 'نثريات وشاي وسكر',
      amount: 10000,
      expenseDate: DateTime.now(),
      userId: 'user1',
    );

    var total = await ds.getTotalExpenses();
    expect(total, 10000);

    await ds.deleteExpense(expense.id);

    final list = await ds.getExpenses();
    expect(list.isEmpty, true);

    total = await ds.getTotalExpenses();
    expect(total, 0);
  });
}

