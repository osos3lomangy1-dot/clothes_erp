import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/repositories/employee_repository.dart';
import 'cashier_payroll_state.dart';

@injectable
class CashierPayrollCubit extends Cubit<CashierPayrollState> {
  final EmployeeRepository _repository;
  String? _currentEmployeeId;
  DateTime _currentMonthDate = DateTime.now();

  CashierPayrollCubit(this._repository) : super(CashierPayrollInitial());

  Future<void> loadSummary(String employeeId, {DateTime? monthDate}) async {
    _currentEmployeeId = employeeId;
    if (monthDate != null) {
      _currentMonthDate = monthDate;
    }

    emit(CashierPayrollLoading());
    final result = await _repository.getPayrollSummary(
      employeeId,
      monthDate: _currentMonthDate,
    );

    result.fold(
      (failure) => emit(CashierPayrollError(failure.message)),
      (summary) => emit(CashierPayrollLoaded(summary: summary)),
    );
  }

  Future<void> changeMonth(int monthDelta) async {
    if (_currentEmployeeId == null) return;
    _currentMonthDate = DateTime(
      _currentMonthDate.year,
      _currentMonthDate.month + monthDelta,
      1,
    );
    await loadSummary(_currentEmployeeId!, monthDate: _currentMonthDate);
  }

  Future<bool> recordTransaction({
    required String employeeId,
    required String type, // 'salary', 'bonus', 'advance'
    required int amount,
    String? note,
    required DateTime date,
    required String currentUserId,
  }) async {
    final currentState = state;
    if (currentState is CashierPayrollLoaded) {
      emit(currentState.copyWith(isOperating: true));
    }

    final result = await _repository.recordPayrollTransaction(
      employeeId: employeeId,
      type: type,
      amount: amount,
      note: note,
      date: date,
      currentUserId: currentUserId,
    );

    return result.fold(
      (failure) {
        if (currentState is CashierPayrollLoaded) {
          emit(currentState.copyWith(isOperating: false));
        } else {
          emit(CashierPayrollError(failure.message));
        }
        return false;
      },
      (tx) async {
        await loadSummary(employeeId, monthDate: _currentMonthDate);
        return true;
      },
    );
  }
}

