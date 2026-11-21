import 'package:injectable/injectable.dart';
import '../../../../core/utils/logging.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login(String email, String password);
  Future<void> logout();
  Stream<UserModel?> get authStateChanges;
}

@LazySingleton(as: AuthRemoteDataSource)
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl();

  @override
  Future<UserModel> login(String email, String password) async {
    Logging.info('[Safe Mode] Remote login bypassed');
    return UserModel(
      id: 'safe-mode-admin',
      email: email,
      name: 'Safe Mode Admin',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Stream<UserModel?> get authStateChanges => Stream.value(null);
}
