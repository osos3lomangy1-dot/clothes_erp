import 'package:equatable/equatable.dart';

class AttendanceEntity extends Equatable {
  final String id;
  final String employeeId;
  final DateTime date;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String status;

  const AttendanceEntity({
    required this.id,
    required this.employeeId,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.status = 'absent',
  });

  @override
  List<Object?> get props => [id, employeeId, date, checkIn, checkOut, status];
}
