import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/employee_entity.dart';
import '../entities/employee_payroll_summary.dart';
import '../../../expenses/domain/entities/expense_entity.dart';

abstract class EmployeeRepository {
  Future<Either<Failure, List<EmployeeEntity>>> getEmployees({String? search});
  Future<Either<Failure, EmployeeEntity?>> getEmployeeById(String id);
  Future<Either<Failure, EmployeeEntity>> addEmployee(EmployeeEntity employee, {String? password});
  Future<Either<Failure, EmployeeEntity>> updateEmployee(EmployeeEntity employee);
  Future<Either<Failure, Unit>> updateEmployeeStatus(String id, bool isActive);
  Future<Either<Failure, Unit>> deleteEmployee(String id);
  Future<Either<Failure, EmployeePayrollSummary>> getPayrollSummary(String employeeId, {DateTime? monthDate});
  Future<Either<Failure, ExpenseEntity>> recordPayrollTransaction({
    required String employeeId,
    required String type,
    required int amount,
    String? note,
    required DateTime date,
    required String currentUserId,
  });
}
