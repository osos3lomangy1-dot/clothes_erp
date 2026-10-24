import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/employee_repository.dart';

@lazySingleton
class DeleteEmployeeUseCase {
  final EmployeeRepository _repository;

  DeleteEmployeeUseCase(this._repository);

  Future<Either<Failure, Unit>> call(String id) {
    return _repository.deleteEmployee(id);
  }
}
