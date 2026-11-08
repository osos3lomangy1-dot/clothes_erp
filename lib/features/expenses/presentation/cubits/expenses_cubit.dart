import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/repositories/expense_repository.dart';
import 'expenses_state.dart';

@injectable
class ExpensesCubit extends Cubit<ExpensesState> {
  final ExpenseRepository _repository;

  ExpensesCubit(this._repository) : super(const ExpensesState());

  Future<void> loadExpenses({
    DateTime? from,
    DateTime? to,
    String? category,
  }) async {
    emit(
      state.copyWith(
        status: ExpensesStatus.loading,
        fromDate: from ?? state.fromDate,
        toDate: to ?? state.toDate,
        selectedCategory: category,
        clearCategory: category == null,
      ),
    );

    final effectiveFrom = from ?? state.fromDate;
    final effectiveTo = to ?? state.toDate;

    final result = await _repository.getExpenses(
      from: effectiveFrom,
      to: effectiveTo,
      category: category,
    );

    result.fold(
      (failure) => emit(
        state.copyWith(
          status: ExpensesStatus.error,
          errorMessage: failure.message,
        ),
      ),
      (expenses) {
        final total = expenses.fold<int>(0, (sum, e) => sum + e.amount);

        // Dynamically collect all categories
        final recordedCats = expenses
            .map((e) => e.category.trim())
            .where((c) => c.isNotEmpty);
        final allCategories = <String>{
          ...ExpensesState.defaultCategories,
          ...state.categories,
          ...recordedCats,
        }.toList();

        emit(
          state.copyWith(
            status: ExpensesStatus.loaded,
            expenses: expenses,
            categories: allCategories,
            totalAmount: total,
          ),
        );
      },
    );
  }

  void addCustomCategory(String newCat) {
    final trimmed = newCat.trim();
    if (trimmed.isEmpty) return;
    if (!state.categories.contains(trimmed)) {
      emit(state.copyWith(categories: [...state.categories, trimmed]));
    }
  }

  Future<bool> addExpense({
    required String category,
    required int amount,
    String? note,
    required DateTime expenseDate,
    required String userId,
  }) async {
    final result = await _repository.addExpense(
      category: category,
      amount: amount,
      note: note,
      expenseDate: expenseDate,
      userId: userId,
    );

    return result.fold(
      (failure) {
        emit(
          state.copyWith(
            status: ExpensesStatus.error,
            errorMessage: failure.message,
          ),
        );
        return false;
      },
      (_) {
        addCustomCategory(category);
        loadExpenses();
        return true;
      },
    );
  }

  Future<void> deleteExpense(String id) async {
    final result = await _repository.deleteExpense(id);
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: ExpensesStatus.error,
          errorMessage: failure.message,
        ),
      ),
      (_) => loadExpenses(),
    );
  }
}
