import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/attendance_entity.dart';

abstract class AttendanceRepository {
  Future<Either<Failure, void>> checkIn(String employeeId);
  Future<Either<Failure, void>> checkOut(String employeeId);
  Future<Either<Failure, AttendanceEntity?>> getTodayAttendance(String employeeId);
}
