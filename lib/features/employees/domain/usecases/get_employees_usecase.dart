import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/employee_entity.dart';
import '../repositories/employee_repository.dart';

@lazySingleton
class GetEmployeesUseCase {
  final EmployeeRepository _repository;

  GetEmployeesUseCase(this._repository);

  Future<Either<Failure, List<EmployeeEntity>>> call({String? search}) {
    return _repository.getEmployees(search: search);
  }
}
