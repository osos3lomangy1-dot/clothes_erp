import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/employee_entity.dart';

abstract class EmployeeRepository {
  Stream<List<EmployeeEntity>> getEmployees();
  Future<Either<Failure, Unit>> addEmployee(EmployeeEntity employee);
  Future<Either<Failure, Unit>> updateEmployeeStatus(String id, bool isActive);
  Future<Either<Failure, Unit>> deleteEmployee(String id);
}
