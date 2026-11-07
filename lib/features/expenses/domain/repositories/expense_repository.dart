import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/expense_entity.dart';

abstract class ExpenseRepository {
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({DateTime? from, DateTime? to, String? category});
  Future<Either<Failure, ExpenseEntity>> addExpense({
    required String category,
    required int amount,
    String? note,
    required DateTime expenseDate,
    required String userId,
  });
  Future<Either<Failure, void>> deleteExpense(String id, {String userId = 'system'});
  Future<Either<Failure, int>> getTotalExpenses({DateTime? from, DateTime? to});
}

