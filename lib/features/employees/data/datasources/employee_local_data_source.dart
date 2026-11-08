import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../domain/entities/employee_entity.dart';
import '../models/employee_model.dart';

abstract class EmployeeLocalDataSource {
  Future<List<EmployeeEntity>> getEmployees({String? search});
  Future<EmployeeEntity?> getEmployeeById(String id);
  Future<EmployeeEntity> addEmployee(EmployeeEntity employee, {String? password});
  Future<EmployeeEntity> updateEmployee(EmployeeEntity employee);
  Future<void> updateEmployeeStatus(String id, bool isActive);
  Future<void> deleteEmployee(String id);
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
}

