import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../domain/entities/expense_entity.dart';

abstract class ExpensesLocalDataSource {
  Future<List<ExpenseEntity>> getExpenses({DateTime? from, DateTime? to, String? category});
  Future<ExpenseEntity?> getExpenseById(String id);
  Future<ExpenseEntity> addExpense({
    required String category,
    required int amount,
    String? note,
    required DateTime expenseDate,
    required String userId,
  });
  Future<void> deleteExpense(String id, {String userId = 'system'});
  Future<int> getTotalExpenses({DateTime? from, DateTime? to});
}

@LazySingleton(as: ExpensesLocalDataSource)
class ExpensesLocalDataSourceImpl implements ExpensesLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  ExpensesLocalDataSourceImpl(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<List<ExpenseEntity>> getExpenses({DateTime? from, DateTime? to, String? category}) async {
    var query = _db.select(_db.expenses)..where((e) => e.deletedAt.isNull());

    if (from != null) {
      query = query..where((e) => e.expenseDate.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query = query..where((e) => e.expenseDate.isSmallerOrEqualValue(to));
    }
    if (category != null && category.trim().isNotEmpty) {
      query = query..where((e) => e.category.equals(category.trim()));
    }

    query = query..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]);
    final rows = await query.get();

    return rows.map((r) => ExpenseEntity(
      id: r.id,
      branchId: r.branchId,
      category: r.category,
      amount: r.amount,
      note: r.note,
      userId: r.userId,
      expenseDate: r.expenseDate,
      createdAt: r.createdAt,
    )).toList();
  }

  @override
  Future<ExpenseEntity?> getExpenseById(String id) async {
    final row = await (_db.select(_db.expenses)
          ..where((e) => e.id.equals(id) & e.deletedAt.isNull()))
        .getSingleOrNull();

    if (row == null) return null;
    return ExpenseEntity(
      id: row.id,
      branchId: row.branchId,
      category: row.category,
      amount: row.amount,
      note: row.note,
      userId: row.userId,
      expenseDate: row.expenseDate,
      createdAt: row.createdAt,
    );
  }

  @override
  Future<ExpenseEntity> addExpense({
    required String category,
    required int amount,
    String? note,
    required DateTime expenseDate,
    required String userId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ المصروف أكبر من الصفر');
    }
    if (category.trim().isEmpty) {
      throw ArgumentError('يرجى تحديد بند المصروف');
    }

    final id = _uuid.v4();
    final branchId = await _branchId();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            branchId: branchId,
            category: category.trim(),
            amount: amount,
            note: Value(note?.trim()),
            userId: userId,
            expenseDate: expenseDate,
            createdAt: now,
            updatedAt: now,
          ),
        );
      },
      branchId: branchId,
      entity: 'expense',
      entityId: id,
      operation: 'create',
      userId: userId,
      newValue: '{"category":"$category","amount":$amount}',
    );

    return ExpenseEntity(
      id: id,
      branchId: branchId,
      category: category.trim(),
      amount: amount,
      note: note?.trim(),
      userId: userId,
      expenseDate: expenseDate,
      createdAt: now,
    );
  }

  @override
  Future<void> deleteExpense(String id, {String userId = 'system'}) async {
    final branchId = await _branchId();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
          ExpensesCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'expense',
      entityId: id,
      operation: 'delete',
      userId: userId,
    );
  }

  @override
  Future<int> getTotalExpenses({DateTime? from, DateTime? to}) async {
    var query = _db.select(_db.expenses)..where((e) => e.deletedAt.isNull());
    if (from != null) {
      query = query..where((e) => e.expenseDate.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query = query..where((e) => e.expenseDate.isSmallerOrEqualValue(to));
    }
    final rows = await query.get();
    return rows.fold<int>(0, (sum, r) => sum + r.amount);
  }
}

