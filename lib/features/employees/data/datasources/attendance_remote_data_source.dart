import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/attendance_entity.dart';

abstract class AttendanceRemoteDataSource {
  Future<void> checkIn(String employeeId);
  Future<void> checkOut(String employeeId);
  Future<AttendanceEntity?> getTodayAttendance(String employeeId);
}

@LazySingleton(as: AttendanceRemoteDataSource)
class AttendanceRemoteDataSourceImpl implements AttendanceRemoteDataSource {
  final FirebaseFirestore _firestore;

  AttendanceRemoteDataSourceImpl(this._firestore);

  @override
  Future<void> checkIn(String employeeId) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final docId = '${employeeId}_$dateStr';
      await _firestore.collection('attendance').doc(docId).set({
        'employeeId': employeeId,
        'date': Timestamp.fromDate(now),
        'checkIn': Timestamp.fromDate(now),
        'checkOut': null,
        'status': 'present',
      });
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> checkOut(String employeeId) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final docId = '${employeeId}_$dateStr';
      await _firestore.collection('attendance').doc(docId).update({
        'checkOut': Timestamp.fromDate(now),
        'status': 'present',
      });
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<AttendanceEntity?> getTodayAttendance(String employeeId) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final docId = '${employeeId}_$dateStr';
      final doc = await _firestore.collection('attendance').doc(docId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      return AttendanceEntity(
        id: doc.id,
        employeeId: data['employeeId'] ?? '',
        date: (data['date'] as Timestamp?)?.toDate() ?? now,
        checkIn: (data['checkIn'] as Timestamp?)?.toDate(),
        checkOut: (data['checkOut'] as Timestamp?)?.toDate(),
        status: data['status'] ?? 'absent',
      );
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
