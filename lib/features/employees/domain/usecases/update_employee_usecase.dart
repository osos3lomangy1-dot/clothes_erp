import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/employee_entity.dart';
import '../repositories/employee_repository.dart';

@lazySingleton
class UpdateEmployeeUseCase {
  final EmployeeRepository _repository;

  UpdateEmployeeUseCase(this._repository);

  Future<Either<Failure, EmployeeEntity>> call(EmployeeEntity employee) {
    return _repository.updateEmployee(employee);
  }
}

