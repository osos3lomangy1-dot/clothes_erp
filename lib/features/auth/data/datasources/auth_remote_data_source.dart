import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/config/app_config.dart';
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
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  AuthRemoteDataSourceImpl();

  @override
  Future<UserModel> login(String email, String password) async {
    if (!kEnableFirebase) {
      Logging.info('🛡️ [Safe Mode] Remote login bypassed');
      return UserModel(
        id: 'safe-mode-admin',
        email: email,
        name: 'Safe Mode Admin',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );
    }

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
  Future<void> logout() async {
    if (!kEnableFirebase) return;
    return _firebaseAuth.signOut();
  }

  @override
  Stream<UserModel?> get authStateChanges {
    if (!kEnableFirebase) {
      return Stream.value(null);
    }
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
