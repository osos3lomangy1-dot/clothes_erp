import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expenses_local_data_source.dart';

@LazySingleton(as: ExpenseRepository)
class ExpenseRepositoryImpl implements ExpenseRepository {
  final ExpensesLocalDataSource localDataSource;

  ExpenseRepositoryImpl(this.localDataSource);

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({
    DateTime? from,
    DateTime? to,
    String? category,
  }) async {
    try {
      final list = await localDataSource.getExpenses(
        from: from,
        to: to,
        category: category,
      );
      return Right(list);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> addExpense({
    required String category,
    required int amount,
    String? note,
    required DateTime expenseDate,
    required String userId,
  }) async {
    try {
      final entity = await localDataSource.addExpense(
        category: category,
        amount: amount,
        note: note,
        expenseDate: expenseDate,
        userId: userId,
      );
      return Right(entity);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteExpense(
    String id, {
    String userId = 'system',
  }) async {
    try {
      await localDataSource.deleteExpense(id, userId: userId);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> getTotalExpenses({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final total = await localDataSource.getTotalExpenses(from: from, to: to);
      return Right(total);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
