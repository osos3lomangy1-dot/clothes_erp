import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/usecases/add_employee_usecase.dart';
import '../../domain/usecases/delete_employee_usecase.dart';
import '../../domain/usecases/get_employees_usecase.dart';
import '../../domain/usecases/update_employee_status_usecase.dart';
import '../../domain/usecases/update_employee_usecase.dart';
import 'employee_state.dart';

@injectable
class EmployeeCubit extends Cubit<EmployeeState> {
  final GetEmployeesUseCase _getEmployeesUseCase;
  final AddEmployeeUseCase _addEmployeeUseCase;
  final UpdateEmployeeUseCase _updateEmployeeUseCase;
  final UpdateEmployeeStatusUseCase _updateEmployeeStatusUseCase;
  final DeleteEmployeeUseCase _deleteEmployeeUseCase;
  String _currentSearch = '';

  EmployeeCubit(
    this._getEmployeesUseCase,
    this._addEmployeeUseCase,
    this._updateEmployeeUseCase,
    this._updateEmployeeStatusUseCase,
    this._deleteEmployeeUseCase,
  ) : super(EmployeeInitial());

  Future<void> loadEmployees({String? search}) async {
    _currentSearch = search ?? _currentSearch;
    emit(EmployeeLoading());
    final result = await _getEmployeesUseCase(search: _currentSearch);
    result.fold(
      (failure) => emit(EmployeeError(failure.message)),
      (employees) => emit(EmployeeLoaded(employees, searchQuery: _currentSearch)),
    );
  }

  void search(String query) {
    _currentSearch = query;
    loadEmployees(search: query);
  }

  Future<bool> addEmployee(EmployeeEntity employee, {String? password}) async {
    final result = await _addEmployeeUseCase(employee, password: password);
    return result.fold(
      (failure) {
        emit(EmployeeError(failure.message));
        return false;
      },
      (_) {
        loadEmployees();
        return true;
      },
    );
  }

  Future<bool> updateEmployee(EmployeeEntity employee) async {
    final result = await _updateEmployeeUseCase(employee);
    return result.fold(
      (failure) {
        emit(EmployeeError(failure.message));
        return false;
      },
      (_) {
        loadEmployees();
        return true;
      },
    );
  }

  Future<void> updateStatus(String id, bool isActive) async {
    final result = await _updateEmployeeStatusUseCase(id, isActive);
    result.fold(
      (failure) => emit(EmployeeError(failure.message)),
      (_) => loadEmployees(),
    );
  }

  Future<void> deleteEmployee(String id) async {
    final result = await _deleteEmployeeUseCase(id);
    result.fold(
      (failure) => emit(EmployeeError(failure.message)),
      (_) => loadEmployees(),
    );
  }
}
