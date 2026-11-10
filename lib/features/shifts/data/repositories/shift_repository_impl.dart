import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/shift_entity.dart';
import '../../domain/entities/shift_summary_entity.dart';
import '../../domain/repositories/shift_repository.dart';
import '../datasources/shift_local_data_source.dart';

@LazySingleton(as: ShiftRepository)
class ShiftRepositoryImpl implements ShiftRepository {
  final ShiftLocalDataSource _localDataSource;

  ShiftRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, bool>> isShiftsEnabled() async {
    try {
      final enabled = await _localDataSource.isShiftsEnabled();
      return Right(enabled);
    } catch (e) {
      return Left(CacheFailure('فشل قراءة إعدادات الوردية: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> setShiftsEnabled(bool enabled) async {
    try {
      await _localDataSource.setShiftsEnabled(enabled);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('فشل تحديث إعدادات الوردية: $e'));
    }
  }

  @override
  Future<Either<Failure, ShiftEntity?>> getActiveShift() async {
    try {
      final shift = await _localDataSource.getActiveShift();
      return Right(shift);
    } catch (e) {
      return Left(CacheFailure('فشل جلب الوردية الحالية: $e'));
    }
  }

  @override
  Future<Either<Failure, ShiftSummaryEntity>> getShiftSummary(String shiftId) async {
    try {
      final summary = await _localDataSource.getShiftSummary(shiftId);
      return Right(summary);
    } catch (e) {
      return Left(CacheFailure('فشل جلب ملخص الوردية: $e'));
    }
  }

  @override
  Future<Either<Failure, ShiftEntity>> openShift({
    required int openingBalance,
    required String cashierId,
    String? cashierName,
  }) async {
    try {
      final shift = await _localDataSource.openShift(
        openingBalance: openingBalance,
        cashierId: cashierId,
        cashierName: cashierName,
      );
      return Right(shift);
    } catch (e) {
      return Left(CacheFailure(e.toString().replaceAll('Exception: ', '')));
    }
  }

  @override
  Future<Either<Failure, ShiftEntity>> closeShift({
    required int countedBalance,
    String? shiftId,
    required String userId,
  }) async {
    try {
      final shift = await _localDataSource.closeShift(
        countedBalance: countedBalance,
        shiftId: shiftId,
        userId: userId,
      );
      return Right(shift);
    } catch (e) {
      return Left(CacheFailure(e.toString().replaceAll('Exception: ', '')));
    }
  }

  @override
  Future<Either<Failure, List<ShiftEntity>>> getShiftHistory({int limit = 20}) async {
    try {
      final list = await _localDataSource.getShiftHistory(limit: limit);
      return Right(list);
    } catch (e) {
      return Left(CacheFailure('فشل جلب سجل الورديات: $e'));
    }
  }
}

