import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/employee_repository.dart';

@lazySingleton
class UpdateEmployeeStatusUseCase {
  final EmployeeRepository _repository;

  UpdateEmployeeStatusUseCase(this._repository);

  Future<Either<Failure, Unit>> call(String id, bool isActive) {
    return _repository.updateEmployeeStatus(id, isActive);
  }
}
