import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/entities/employee_payroll_summary.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../models/employee_model.dart';

abstract class EmployeeLocalDataSource {
  Future<List<EmployeeEntity>> getEmployees({String? search});
  Future<EmployeeEntity?> getEmployeeById(String id);
  Future<EmployeeEntity> addEmployee(EmployeeEntity employee, {String? password});
  Future<EmployeeEntity> updateEmployee(EmployeeEntity employee);
  Future<void> updateEmployeeStatus(String id, bool isActive);
  Future<void> deleteEmployee(String id);
  Future<EmployeePayrollSummary> getPayrollSummary(String employeeId, {DateTime? monthDate});
  Future<ExpenseEntity> recordPayrollTransaction({
    required String employeeId,
    required String type, // 'salary', 'bonus', 'advance'
    required int amount,
    String? note,
    required DateTime date,
    required String currentUserId,
  });
}

@LazySingleton(as: EmployeeLocalDataSource)
class EmployeeLocalDataSourceImpl implements EmployeeLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  EmployeeLocalDataSourceImpl(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<List<EmployeeEntity>> getEmployees({String? search}) async {
    var query = _db.select(_db.users)..where((u) => u.deletedAt.isNull());

    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim().toLowerCase()}%';
      query = query
        ..where((u) =>
            u.displayName.lower().like(s) | u.username.lower().like(s));
    }

    query = query..orderBy([(u) => OrderingTerm.desc(u.createdAt)]);
    final rows = await query.get();
    return rows.map((r) => EmployeeModel.fromDrift(r)).toList();
  }

  @override
  Future<EmployeeEntity?> getEmployeeById(String id) async {
    final query = _db.select(_db.users)
      ..where((u) => u.id.equals(id) & u.deletedAt.isNull());
    final user = await query.getSingleOrNull();
    return user != null ? EmployeeModel.fromDrift(user) : null;
  }

  @override
  Future<EmployeeEntity> addEmployee(EmployeeEntity employee, {String? password}) async {
    final branch = await _branchId();
    final now = DateTime.now();
    final id = employee.id.isNotEmpty ? employee.id : _uuid.v4();

    final pass = (password != null && password.trim().isNotEmpty) ? password.trim() : '123456';
    final salt = _uuid.v4().substring(0, 8);
    final passHash = 'hash_$pass';

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.users).insert(
              UsersCompanion.insert(
                id: id,
                branchId: branch,
                username: employee.username.trim(),
                displayName: employee.displayName.trim(),
                role: employee.role,
                isActive: Value(employee.isActive),
                salary: Value(employee.salary),
                passwordHash: passHash,
                passwordSalt: salt,
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
      branchId: branch,
      entity: 'users',
      entityId: id,
      operation: 'insert',
      userId: 'system',
    );

    return employee.copyWith(
      id: id,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<EmployeeEntity> updateEmployee(EmployeeEntity employee) async {
    final branch = await _branchId();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.users)..where((u) => u.id.equals(employee.id))).write(
          UsersCompanion(
            displayName: Value(employee.displayName.trim()),
            username: Value(employee.username.trim()),
            role: Value(employee.role),
            isActive: Value(employee.isActive),
            salary: Value(employee.salary),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branch,
      entity: 'users',
      entityId: employee.id,
      operation: 'update',
      userId: 'system',
    );

    return employee.copyWith(updatedAt: now);
  }

  @override
  Future<void> updateEmployeeStatus(String id, bool isActive) async {
    final branch = await _branchId();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
          UsersCompanion(
            isActive: Value(isActive),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branch,
      entity: 'users',
      entityId: id,
      operation: 'update_status',
      userId: 'system',
    );
  }

  @override
  Future<void> deleteEmployee(String id) async {
    final branch = await _branchId();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.users)..where((u) => u.id.equals(id))).write(
          UsersCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branch,
      entity: 'users',
      entityId: id,
      operation: 'delete',
      userId: 'system',
    );
  }

  @override
  Future<EmployeePayrollSummary> getPayrollSummary(String employeeId, {DateTime? monthDate}) async {
    EmployeeEntity? employee = await getEmployeeById(employeeId);
    if (employee == null) {
      // Try finding by username or fallback
      final byUsername = await (_db.select(_db.users)
            ..where((u) => (u.username.equals(employeeId) | u.displayName.equals(employeeId)) & u.deletedAt.isNull()))
          .getSingleOrNull();
      if (byUsername != null) {
        employee = EmployeeModel.fromDrift(byUsername);
      }
    }

    if (employee == null) {
      throw Exception('لم يتم العثور على بيانات الموظف (المعرف: $employeeId)');
    }

    final targetMonth = monthDate ?? DateTime.now();
    final startOfMonth = DateTime(targetMonth.year, targetMonth.month, 1);
    final endOfMonth = DateTime(targetMonth.year, targetMonth.month + 1, 0, 23, 59, 59);

    // 1. Fetch expenses within this month
    final expRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.deletedAt.isNull() &
              e.expenseDate.isBiggerOrEqualValue(startOfMonth) &
              e.expenseDate.isSmallerOrEqualValue(endOfMonth))
          ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
        .get();

    final empIdLower = employee.id.toLowerCase();
    final empNameLower = employee.displayName.toLowerCase();
    final empUsernameLower = employee.username.toLowerCase();

    final matchedTransactions = <ExpenseEntity>[];
    int salaryPaid = 0;
    int bonusTotal = 0;
    int advancesTotal = 0;

    for (final row in expRows) {
      final noteLower = (row.note ?? '').toLowerCase();
      final catLower = row.category.toLowerCase();
      final uIdLower = row.userId.toLowerCase();

      final matchesUser = uIdLower == empIdLower ||
          uIdLower == empUsernameLower ||
          uIdLower == empNameLower ||
          noteLower.contains(empNameLower) ||
          noteLower.contains(empUsernameLower);

      if (!matchesUser) continue;

      final entity = ExpenseEntity(
        id: row.id,
        branchId: row.branchId,
        category: row.category,
        amount: row.amount,
        note: row.note,
        userId: row.userId,
        expenseDate: row.expenseDate,
        createdAt: row.createdAt,
      );
      matchedTransactions.add(entity);

      final isBonus = catLower.contains('بونص') ||
          catLower.contains('مكاف') ||
          catLower.contains('حافز') ||
          catLower.contains('عمول') ||
          noteLower.contains('بونص') ||
          noteLower.contains('مكافأة');

      final isAdvance = catLower.contains('سلف') ||
          catLower.contains('خصم') ||
          noteLower.contains('سلفة') ||
          noteLower.contains('خصم');

      final isSalary = catLower.contains('مرتب') ||
          catLower.contains('راتب') ||
          catLower.contains('رواتب') ||
          noteLower.contains('راتب') ||
          noteLower.contains('مرتب');

      if (isBonus) {
        bonusTotal += row.amount;
      } else if (isAdvance) {
        advancesTotal += row.amount;
      } else if (isSalary) {
        salaryPaid += row.amount;
      } else {
        // Default to salary payment if linked to employee
        salaryPaid += row.amount;
      }
    }

    // 2. Check active shift
    final activeShiftRow = await (_db.select(_db.shifts)
          ..where((s) => s.cashierId.equals(employee!.id) & s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();

    return EmployeePayrollSummary(
      employee: employee,
      basicSalary: employee.salary,
      salaryPaidThisMonth: salaryPaid,
      bonusThisMonth: bonusTotal,
      advancesThisMonth: advancesTotal,
      monthDate: targetMonth,
      transactions: matchedTransactions,
      hasActiveShift: activeShiftRow != null,
      shiftOpenedAt: activeShiftRow?.openedAt,
      shiftOpeningBalance: activeShiftRow?.openingBalance,
    );
  }

  @override
  Future<ExpenseEntity> recordPayrollTransaction({
    required String employeeId,
    required String type,
    required int amount,
    String? note,
    required DateTime date,
    required String currentUserId,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون المبلغ أكبر من الصفر');
    }

    final employee = await getEmployeeById(employeeId);
    if (employee == null) {
      throw Exception('الموظف غير موجود');
    }

    final branchId = await _branchId();
    final now = DateTime.now();
    final expenseId = _uuid.v4();

    String category;
    String defaultNote;
    switch (type.toLowerCase()) {
      case 'bonus':
      case 'بونص':
        category = 'بونص ومكافآت';
        defaultNote = 'بونص ومكافأة تشجيعية للموظف: ${employee.displayName}';
        break;
      case 'advance':
      case 'سلفة':
        category = 'سلف وخصومات';
        defaultNote = 'سلفة على الراتب للموظف: ${employee.displayName}';
        break;
      case 'salary':
      case 'راتب':
      default:
        category = 'مرتبات ويوميات';
        defaultNote = 'صرف راتب شهر ${date.month}/${date.year} للموظف: ${employee.displayName}';
        break;
    }

    final fullNote = (note != null && note.trim().isNotEmpty)
        ? '$defaultNote - ${note.trim()}'
        : defaultNote;

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.expenses).insert(
              ExpensesCompanion.insert(
                id: expenseId,
                branchId: branchId,
                category: category,
                amount: amount,
                note: Value(fullNote),
                userId: employee.id, // Store employee ID so it's strictly linked
                expenseDate: date,
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
      branchId: branchId,
      entity: 'expense',
      entityId: expenseId,
      operation: 'create',
      userId: currentUserId,
      newValue: '{"category":"$category","amount":$amount,"employeeId":"${employee.id}"}',
    );

    return ExpenseEntity(
      id: expenseId,
      branchId: branchId,
      category: category,
      amount: amount,
      note: fullNote,
      userId: employee.id,
      expenseDate: date,
      createdAt: now,
    );
  }
}

