import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/delete_employee_usecase.dart';
import '../../domain/usecases/get_employees_usecase.dart';
import '../../domain/usecases/update_employee_status_usecase.dart';
import 'employee_state.dart';

@injectable
class EmployeeCubit extends Cubit<EmployeeState> {
  final GetEmployeesUseCase _getEmployeesUseCase;
  final UpdateEmployeeStatusUseCase _updateEmployeeStatusUseCase;
  final DeleteEmployeeUseCase _deleteEmployeeUseCase;
  StreamSubscription? _subscription;

  EmployeeCubit(
    this._getEmployeesUseCase,
    this._updateEmployeeStatusUseCase,
    this._deleteEmployeeUseCase,
  ) : super(EmployeeInitial()) {
    getEmployees();
  }

  void getEmployees() {
    emit(EmployeeLoading());
    _subscription?.cancel();
    _subscription = _getEmployeesUseCase().listen(
      (employees) => emit(EmployeeLoaded(employees)),
      onError: (e) => emit(EmployeeError(e.toString())),
    );
  }

  Future<void> updateStatus(String id, bool isActive) async {
    final result = await _updateEmployeeStatusUseCase(id, isActive);
    result.fold(
      (failure) => emit(EmployeeError(failure.message)),
      (_) => null, // List updates automatically via stream
    );
  }

  Future<void> deleteEmployee(String id) async {
    final result = await _deleteEmployeeUseCase(id);
    result.fold(
      (failure) => emit(EmployeeError(failure.message)),
      (_) => null, // List updates automatically via stream
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
