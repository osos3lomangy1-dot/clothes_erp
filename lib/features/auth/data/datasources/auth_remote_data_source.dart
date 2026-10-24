import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/logging.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login(String email, String password);

  Future<void> logout();
  Stream<UserModel?> get authStateChanges;
}

@LazySingleton(as: AuthRemoteDataSource)
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  AuthRemoteDataSourceImpl(this._firebaseAuth, this._firestore);

  @override
  Future<UserModel> login(String email, String password) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      Logging.info('User logged in: ${userCredential.user}');
      final doc = await _firestore.collection('users').doc(userCredential.user!.uid).get();
      if (!doc.exists) {
        throw ServerException('User data not found in Firestore');
      }
      return UserModel.fromFirestore(doc.data()!, doc.id);
    } on FirebaseAuthException catch (e) {
      throw ServerException(e.message ?? 'Authentication failed');
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> logout() => _firebaseAuth.signOut();

  @override
  Stream<UserModel?> get authStateChanges {
    return _firebaseAuth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (!doc.exists) return null;
        return UserModel.fromFirestore(doc.data()!, doc.id);
      } catch (e) {
        Logging.error('Auth state fetch failed: $e');
        return null;
      }
    });
  }
}
