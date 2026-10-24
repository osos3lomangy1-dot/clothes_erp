import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/employee_entity.dart';
import '../repositories/employee_repository.dart';

@lazySingleton
class AddEmployeeUseCase {
  final EmployeeRepository _repository;

  AddEmployeeUseCase(this._repository);

  Future<Either<Failure, Unit>> call(EmployeeEntity employee) {
    return _repository.addEmployee(employee);
  }
}
