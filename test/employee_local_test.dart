import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/employees/data/datasources/employee_local_data_source.dart';
import 'package:clothes_erp/features/employees/domain/entities/employee_entity.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late EmployeeLocalDataSource ds;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    ds = EmployeeLocalDataSourceImpl(db, bp, tx);
  });

  tearDown(() async {
    tx.beforeAuditWrite = null;
    await db.close();
  });

  test('add employee -> verify record created and audit_logs & sync_queue written', () async {
    final emp = EmployeeEntity(
      id: '',
      displayName: 'محمود أحمد',
      username: 'mahmoud_cashier',
      role: 'cashier',
      salary: 500000, // 5000 EGP
      isActive: true,
      createdAt: DateTime.now(),
    );

    final created = await ds.addEmployee(emp, password: 'password123');

    expect(created.id.isNotEmpty, true);
    expect(created.displayName, 'محمود أحمد');
    expect(created.username, 'mahmoud_cashier');
    expect(created.salary, 500000);
    expect(created.salaryPounds, 5000.0);

    // Verify row in users table
    final rows = await db.select(db.users).get();
    expect(rows.length, 1);
    expect(rows.first.displayName, 'محمود أحمد');
    expect(rows.first.salary, 500000);
    expect(rows.first.role, 'cashier');

    // Verify audit_logs and sync_queue
    final audits = await db.select(db.auditLogs).get();
    expect(audits.length, 1);
    expect(audits.first.entity, 'users');
    expect(audits.first.action, 'insert');

    final syncs = await db.select(db.syncQueue).get();
    expect(syncs.length, 1);
    expect(syncs.first.entity, 'users');
    expect(syncs.first.operation, 'insert');
  });

  test('update employee -> verify changes updated in Drift', () async {
    final emp = EmployeeEntity(
      id: '',
      displayName: 'علي حسن',
      username: 'ali_pos',
      role: 'cashier',
      salary: 450000,
      isActive: true,
      createdAt: DateTime.now(),
    );

    final created = await ds.addEmployee(emp);

    final toUpdate = created.copyWith(
      displayName: 'علي حسن المعدل',
      role: 'manager',
      salary: 700000,
    );

    await ds.updateEmployee(toUpdate);

    final list = await ds.getEmployees();
    expect(list.length, 1);
    expect(list.first.displayName, 'علي حسن المعدل');
    expect(list.first.role, 'manager');
    expect(list.first.salary, 700000);

    final audits = await db.select(db.auditLogs).get();
    expect(audits.length, 2); // 1 insert + 1 update
    expect(audits.last.action, 'update');
  });

  test('soft delete employee -> verify excluded from list and deletedAt set', () async {
    final emp = EmployeeEntity(
      id: '',
      displayName: 'طارق سامي',
      username: 'tarek_admin',
      role: 'admin',
      salary: 900000,
      isActive: true,
      createdAt: DateTime.now(),
    );

    final created = await ds.addEmployee(emp);
    expect((await ds.getEmployees()).length, 1);

    await ds.deleteEmployee(created.id);

    final afterDelete = await ds.getEmployees();
    expect(afterDelete.isEmpty, true);

    // Verify soft-deleted row still exists in users table with deletedAt set
    final allUsers = await db.select(db.users).get();
    expect(allUsers.length, 1);
    expect(allUsers.first.deletedAt, isNotNull);

    final audits = await db.select(db.auditLogs).get();
    expect(audits.last.action, 'delete');
  });

  test('search employees by name or username', () async {
    await ds.addEmployee(EmployeeEntity(
      id: '',
      displayName: 'خالد إبراهيم',
      username: 'khaled_pos',
      role: 'cashier',
      createdAt: DateTime.now(),
    ));

    await ds.addEmployee(EmployeeEntity(
      id: '',
      displayName: 'سارة محمد',
      username: 'sara_manager',
      role: 'manager',
      createdAt: DateTime.now(),
    ));

    final searchName = await ds.getEmployees(search: 'خالد');
    expect(searchName.length, 1);
    expect(searchName.first.displayName, 'خالد إبراهيم');

    final searchUser = await ds.getEmployees(search: 'sara');
    expect(searchUser.length, 1);
    expect(searchUser.first.displayName, 'سارة محمد');
  });

  test('updateEmployeeStatus toggles isActive correctly', () async {
    final created = await ds.addEmployee(EmployeeEntity(
      id: '',
      displayName: 'ياسر كمال',
      username: 'yasser_pos',
      role: 'cashier',
      isActive: true,
      createdAt: DateTime.now(),
    ));

    await ds.updateEmployeeStatus(created.id, false);

    final user = await ds.getEmployeeById(created.id);
    expect(user?.isActive, false);
  });

  test('ATOMICITY: inject failure before audit write rolls back employee creation', () async {
    tx.beforeAuditWrite = () async => throw Exception('database-failure-simulation');

    final emp = EmployeeEntity(
      id: '',
      displayName: 'فشل تجريبي',
      username: 'fail_user',
      role: 'cashier',
      createdAt: DateTime.now(),
    );

    await expectLater(
      ds.addEmployee(emp),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('database-failure-simulation'))),
    );

    final users = await db.select(db.users).get();
    expect(users.isEmpty, true);

    final audits = await db.select(db.auditLogs).get();
    expect(audits.isEmpty, true);

    final syncs = await db.select(db.syncQueue).get();
    expect(syncs.isEmpty, true);
  });
}
