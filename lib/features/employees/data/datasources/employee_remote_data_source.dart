import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/employee_model.dart';

abstract class EmployeeRemoteDataSource {
  Stream<List<EmployeeModel>> getEmployees();
  Future<void> addEmployee(EmployeeModel employee);
  Future<void> updateEmployeeStatus(String id, bool isActive);
  Future<void> deleteEmployee(String id);
}

@LazySingleton(as: EmployeeRemoteDataSource)
class EmployeeRemoteDataSourceImpl implements EmployeeRemoteDataSource {
  final FirebaseFirestore _firestore;

  EmployeeRemoteDataSourceImpl(this._firestore);

  @override
  Stream<List<EmployeeModel>> getEmployees() {
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EmployeeModel.fromFirestore(doc.data(), doc.id)).toList();
    });
  }

  @override
  Future<void> addEmployee(EmployeeModel employee) async {
    try {
      await _firestore.collection('users').doc(employee.id.isEmpty ? null : employee.id).set({
        'name': employee.name,
        'email': employee.email,
        'role': employee.role,
        'isActive': employee.isActive,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateEmployeeStatus(String id, bool isActive) async {
    try {
      await _firestore.collection('users').doc(id).update({
        'isActive': isActive,
      });
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteEmployee(String id) async {
    try {
      await _firestore.collection('users').doc(id).delete();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
