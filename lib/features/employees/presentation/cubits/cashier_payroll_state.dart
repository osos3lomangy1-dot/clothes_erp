import 'package:equatable/equatable.dart';
import '../../domain/entities/employee_payroll_summary.dart';

abstract class CashierPayrollState extends Equatable {
  const CashierPayrollState();

  @override
  List<Object?> get props => [];
}

class CashierPayrollInitial extends CashierPayrollState {}

class CashierPayrollLoading extends CashierPayrollState {}

class CashierPayrollLoaded extends CashierPayrollState {
  final EmployeePayrollSummary summary;
  final bool isOperating;
  final String? operationMessage;

  const CashierPayrollLoaded({
    required this.summary,
    this.isOperating = false,
    this.operationMessage,
  });

  CashierPayrollLoaded copyWith({
    EmployeePayrollSummary? summary,
    bool? isOperating,
    String? operationMessage,
  }) {
    return CashierPayrollLoaded(
      summary: summary ?? this.summary,
      isOperating: isOperating ?? this.isOperating,
      operationMessage: operationMessage,
    );
  }

  @override
  List<Object?> get props => [summary, isOperating, operationMessage];
}

class CashierPayrollError extends CashierPayrollState {
  final String message;

  const CashierPayrollError(this.message);

  @override
  List<Object?> get props => [message];
}

