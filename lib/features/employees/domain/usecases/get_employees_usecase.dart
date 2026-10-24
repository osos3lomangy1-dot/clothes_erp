import 'package:injectable/injectable.dart';
import '../entities/employee_entity.dart';
import '../repositories/employee_repository.dart';

@lazySingleton
class GetEmployeesUseCase {
  final EmployeeRepository _repository;

  GetEmployeesUseCase(this._repository);

  Stream<List<EmployeeEntity>> call() {
    return _repository.getEmployees();
  }
}
