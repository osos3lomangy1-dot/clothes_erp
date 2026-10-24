import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
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
      return snapshot.docs.map((doc) => EmployeeModel.fromFirestore(doc.data(),doc.id)).toList();
    });
  }

  @override
  Future<void> addEmployee(EmployeeModel employee) async {
    // Note: In a real app, creating a user usually requires Firebase Auth.
    // Here we are just creating the Firestore document for the employee list.
    await _firestore.collection('users').doc(employee.id.isEmpty ? null : employee.id).set({
      'name': employee.name,
      'email': employee.email,
      'role': employee.role,
      'isActive': employee.isActive,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateEmployeeStatus(String id, bool isActive) async {
    await _firestore.collection('users').doc(id).update({
      'isActive': isActive,
    });
  }

  @override
  Future<void> deleteEmployee(String id) async {
    await _firestore.collection('users').doc(id).delete();
  }
}
