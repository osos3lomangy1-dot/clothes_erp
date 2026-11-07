import 'package:equatable/equatable.dart';
import '../../domain/entities/expense_entity.dart';

enum ExpensesStatus { initial, loading, loaded, error }

class ExpensesState extends Equatable {
  final ExpensesStatus status;
  final List<ExpenseEntity> expenses;
  final int totalAmount; // in piasters
  final String? errorMessage;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? selectedCategory;

  const ExpensesState({
    this.status = ExpensesStatus.initial,
    this.expenses = const [],
    this.totalAmount = 0,
    this.errorMessage,
    this.fromDate,
    this.toDate,
    this.selectedCategory,
  });

  ExpensesState copyWith({
    ExpensesStatus? status,
    List<ExpenseEntity>? expenses,
    int? totalAmount,
    String? errorMessage,
    DateTime? fromDate,
    DateTime? toDate,
    String? selectedCategory,
    bool clearCategory = false,
  }) {
    return ExpensesState(
      status: status ?? this.status,
      expenses: expenses ?? this.expenses,
      totalAmount: totalAmount ?? this.totalAmount,
      errorMessage: errorMessage ?? this.errorMessage,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      selectedCategory: clearCategory ? null : (selectedCategory ?? this.selectedCategory),
    );
  }

  @override
  List<Object?> get props => [
        status,
        expenses,
        totalAmount,
        errorMessage,
        fromDate,
        toDate,
        selectedCategory,
      ];
}

