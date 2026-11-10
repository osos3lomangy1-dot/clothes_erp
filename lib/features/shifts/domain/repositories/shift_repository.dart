import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/shift_entity.dart';
import '../entities/shift_summary_entity.dart';

abstract class ShiftRepository {
  Future<Either<Failure, bool>> isShiftsEnabled();
  Future<Either<Failure, void>> setShiftsEnabled(bool enabled);
  Future<Either<Failure, ShiftEntity?>> getActiveShift();
  Future<Either<Failure, ShiftSummaryEntity>> getShiftSummary(String shiftId);
  Future<Either<Failure, ShiftEntity>> openShift({
    required int openingBalance,
    required String cashierId,
    String? cashierName,
  });
  Future<Either<Failure, ShiftEntity>> closeShift({
    required int countedBalance,
    String? shiftId,
    required String userId,
  });
  Future<Either<Failure, List<ShiftEntity>>> getShiftHistory({int limit = 20});
}

