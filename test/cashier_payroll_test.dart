import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/employees/data/datasources/employee_local_data_source.dart';
import 'package:clothes_erp/features/employees/data/repositories/employee_repository_impl.dart';
import 'package:clothes_erp/features/employees/domain/entities/employee_entity.dart';
import 'package:clothes_erp/features/employees/domain/entities/employee_payroll_summary.dart';
import 'package:clothes_erp/features/employees/presentation/cubits/cashier_payroll_cubit.dart';
import 'package:clothes_erp/features/employees/presentation/cubits/cashier_payroll_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late EmployeeLocalDataSource ds;
  late EmployeeRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    ds = EmployeeLocalDataSourceImpl(db, bp, tx);
    repo = EmployeeRepositoryImpl(ds);
  });

  tearDown(() async {
    await db.close();
  });

  group('EmployeePayrollSummary Entity Calculations', () {
    final baseEmp = EmployeeEntity(
      id: 'emp-1',
      displayName: 'أحمد الكاشير',
      username: 'ahmed_cashier',
      role: 'cashier',
      salary: 500000, // 5,000 EGP
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );

    test('calculates netDue correctly with salary, bonus, and advances', () {
      final summary = EmployeePayrollSummary(
        employee: baseEmp,
        basicSalary: 500000, // 5,000 EGP
        salaryPaidThisMonth: 300000, // 3,000 EGP
        bonusThisMonth: 50000, // 500 EGP
        advancesThisMonth: 20000, // 200 EGP
        monthDate: DateTime(2026, 11, 1),
      );

      // Remaining basic salary = 5,000 - 3,000 = 2,000 EGP (200,000)
      // Net due = 2,000 + 500 (bonus) - 200 (advance) = 2,300 EGP (230,000)
      expect(summary.remainingSalary, 200000);
      expect(summary.netDue, 230000);
      expect(summary.salaryStatus, PayrollSalaryStatus.partiallyPaid);
      expect(summary.salaryStatusArabic, 'مستلم جزئياً');
      expect(summary.monthArabicName, 'نوفمبر 2026');
    });

    test('status is notSet when basicSalary is zero', () {
      final summary = EmployeePayrollSummary(
        employee: baseEmp.copyWith(salary: 0),
        basicSalary: 0,
        salaryPaidThisMonth: 0,
        bonusThisMonth: 0,
        advancesThisMonth: 0,
        monthDate: DateTime(2026, 11, 1),
      );

      expect(summary.salaryStatus, PayrollSalaryStatus.notSet);
      expect(summary.salaryStatusArabic, 'غير محدد');
    });

    test('status is notPaid when salaryPaidThisMonth is zero', () {
      final summary = EmployeePayrollSummary(
        employee: baseEmp,
        basicSalary: 500000,
        salaryPaidThisMonth: 0,
        bonusThisMonth: 0,
        advancesThisMonth: 0,
        monthDate: DateTime(2026, 11, 1),
      );

      expect(summary.salaryStatus, PayrollSalaryStatus.notPaid);
      expect(summary.salaryStatusArabic, 'لم يُصرف بعد');
      expect(summary.remainingSalary, 500000);
      expect(summary.netDue, 500000);
    });

    test('status is fullyPaid when salaryPaidThisMonth equals or exceeds basicSalary', () {
      final summary = EmployeePayrollSummary(
        employee: baseEmp,
        basicSalary: 500000,
        salaryPaidThisMonth: 500000,
        bonusThisMonth: 40000, // 400 EGP
        advancesThisMonth: 0,
        monthDate: DateTime(2026, 11, 1),
      );

      expect(summary.salaryStatus, PayrollSalaryStatus.fullyPaid);
      expect(summary.salaryStatusArabic, 'تم الصرف بالكامل');
      expect(summary.remainingSalary, 0);
      expect(summary.netDue, 40000); // only the bonus is remaining!
    });
  });

  group('EmployeeLocalDataSource Payroll & Bonus Operations', () {
    test('getPayrollSummary aggregates salary, bonus, and advances accurately', () async {
      // 1. Create cashier
      final createdEmp = await ds.addEmployee(
        EmployeeEntity(
          id: 'cashier-101',
          displayName: 'سارة محمد',
          username: 'sara_pos',
          role: 'cashier',
          salary: 600000, // 6,000 EGP
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final testMonth = DateTime(2026, 11, 15);

      // 2. Record transactions
      // a) Partial salary
      await ds.recordPayrollTransaction(
        employeeId: createdEmp.id,
        type: 'salary',
        amount: 250000, // 2,500 EGP
        note: 'دفعة أولى من راتب نوفمبر',
        date: testMonth,
        currentUserId: 'admin-1',
      );

      // b) Bonus
      await ds.recordPayrollTransaction(
        employeeId: createdEmp.id,
        type: 'bonus',
        amount: 75000, // 750 EGP
        note: 'مكافأة تحقيق تارجت مبيعات',
        date: testMonth,
        currentUserId: 'admin-1',
      );

      // c) Advance
      await ds.recordPayrollTransaction(
        employeeId: createdEmp.id,
        type: 'advance',
        amount: 30000, // 300 EGP
        note: 'سلفة مصروفات شخصية',
        date: testMonth,
        currentUserId: 'admin-1',
      );

      // 3. Fetch summary
      final summary = await ds.getPayrollSummary(createdEmp.id, monthDate: testMonth);

      expect(summary.employee.id, createdEmp.id);
      expect(summary.employee.displayName, 'سارة محمد');
      expect(summary.basicSalary, 600000);
      expect(summary.salaryPaidThisMonth, 250000);
      expect(summary.bonusThisMonth, 75000);
      expect(summary.advancesThisMonth, 30000);
      expect(summary.salaryStatus, PayrollSalaryStatus.partiallyPaid);

      // Remaining salary = 6,000 - 2,500 = 3,500 EGP (350,000)
      // Net due = 350,000 + 75,000 - 30,000 = 395,000
      expect(summary.remainingSalary, 350000);
      expect(summary.netDue, 395000);
      expect(summary.transactions.length, 3);
    });

    test('getPayrollSummary respects month boundaries and active shift', () async {
      final emp = await ds.addEmployee(
        EmployeeEntity(
          id: 'cashier-102',
          displayName: 'كريم محمود',
          username: 'karim_pos',
          role: 'cashier',
          salary: 400000,
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final novDate = DateTime(2026, 11, 10);
      final octDate = DateTime(2026, 10, 20);

      // Transaction in October
      await ds.recordPayrollTransaction(
        employeeId: emp.id,
        type: 'salary',
        amount: 400000,
        note: 'راتب شهر أكتوبر',
        date: octDate,
        currentUserId: 'admin-1',
      );

      // Transaction in November (Bonus only)
      await ds.recordPayrollTransaction(
        employeeId: emp.id,
        type: 'bonus',
        amount: 30000,
        note: 'بونص نوفمبر',
        date: novDate,
        currentUserId: 'admin-1',
      );

      // Active Shift in November
      final branch = await bp.getBranchId();
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              id: 'shift-1',
              branchId: branch,
              cashierId: emp.id,
              openingBalance: 100000, // 1000 EGP
              openedAt: novDate,
              createdAt: novDate,
              updatedAt: novDate,
            ),
          );

      // Query for November
      final novSummary = await ds.getPayrollSummary(emp.id, monthDate: novDate);
      expect(novSummary.salaryPaidThisMonth, 0); // October salary not counted in Nov
      expect(novSummary.bonusThisMonth, 30000);
      expect(novSummary.salaryStatus, PayrollSalaryStatus.notPaid);
      expect(novSummary.hasActiveShift, true);
      expect(novSummary.shiftOpeningBalance, 100000);

      // Query for October
      final octSummary = await ds.getPayrollSummary(emp.id, monthDate: octDate);
      expect(octSummary.salaryPaidThisMonth, 400000);
      expect(octSummary.bonusThisMonth, 0);
      expect(octSummary.salaryStatus, PayrollSalaryStatus.fullyPaid);
    });
  });

  group('CashierPayrollCubit', () {
    test('loads summary and updates on recording transaction', () async {
      final emp = await ds.addEmployee(
        EmployeeEntity(
          id: 'cashier-103',
          displayName: 'ياسر كاشير',
          username: 'yasser_pos',
          role: 'cashier',
          salary: 550000,
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final cubit = CashierPayrollCubit(repo);

      // Initial state
      expect(cubit.state, isA<CashierPayrollInitial>());

      // Load summary
      final now = DateTime(2026, 11, 1);
      await cubit.loadSummary(emp.id, monthDate: now);

      expect(cubit.state, isA<CashierPayrollLoaded>());
      var loaded = cubit.state as CashierPayrollLoaded;
      expect(loaded.summary.basicSalary, 550000);
      expect(loaded.summary.salaryPaidThisMonth, 0);
      expect(loaded.summary.bonusThisMonth, 0);
      expect(loaded.summary.salaryStatus, PayrollSalaryStatus.notPaid);

      // Record a bonus
      final ok = await cubit.recordTransaction(
        employeeId: emp.id,
        type: 'bonus',
        amount: 60000, // 600 EGP
        note: 'بونص استثنائي',
        date: now,
        currentUserId: 'admin-1',
      );

      expect(ok, true);
      expect(cubit.state, isA<CashierPayrollLoaded>());
      loaded = cubit.state as CashierPayrollLoaded;
      expect(loaded.summary.bonusThisMonth, 60000);
      expect(loaded.summary.transactions.length, 1);
    });
  });
}

