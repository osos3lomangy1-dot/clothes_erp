import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/attendance_entity.dart';
import '../../domain/repositories/attendance_repository.dart';

enum AttendanceStatus { initial, loading, success, error }

class AttendanceState extends Equatable {
  final AttendanceStatus status;
  final AttendanceEntity? todayAttendance;
  final String? errorMessage;

  const AttendanceState({
    this.status = AttendanceStatus.initial,
    this.todayAttendance,
    this.errorMessage,
  });

  AttendanceState copyWith({
    AttendanceStatus? status,
    AttendanceEntity? todayAttendance,
    String? errorMessage,
  }) {
    return AttendanceState(
      status: status ?? this.status,
      todayAttendance: todayAttendance ?? this.todayAttendance,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, todayAttendance, errorMessage];
}

@injectable
class AttendanceCubit extends Cubit<AttendanceState> {
  final AttendanceRepository _repository;

  AttendanceCubit(this._repository) : super(const AttendanceState());

  Future<void> loadAttendance(String employeeId) async {
    emit(state.copyWith(status: AttendanceStatus.loading));
    final result = await _repository.getTodayAttendance(employeeId);
    result.fold(
      (failure) => emit(state.copyWith(status: AttendanceStatus.error, errorMessage: failure.message)),
      (attendance) => emit(state.copyWith(status: AttendanceStatus.success, todayAttendance: attendance)),
    );
  }

  Future<void> checkIn(String employeeId) async {
    emit(state.copyWith(status: AttendanceStatus.loading));
    final result = await _repository.checkIn(employeeId);
    result.fold(
      (failure) => emit(state.copyWith(status: AttendanceStatus.error, errorMessage: failure.message)),
      (_) => loadAttendance(employeeId),
    );
  }

  Future<void> checkOut(String employeeId) async {
    emit(state.copyWith(status: AttendanceStatus.loading));
    final result = await _repository.checkOut(employeeId);
    result.fold(
      (failure) => emit(state.copyWith(status: AttendanceStatus.error, errorMessage: failure.message)),
      (_) => loadAttendance(employeeId),
    );
  }
}
