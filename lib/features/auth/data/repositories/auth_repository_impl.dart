import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logging.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';

@LazySingleton(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;

  AuthRepositoryImpl(this._remoteDataSource, this._localDataSource);

  @override
  Future<Either<Failure, UserEntity>> login(String email, String password) async {
    try {
      final userModel = await _remoteDataSource.login(email, password);
      await _localDataSource.cacheUser(userModel);
      return Right(userModel);
    } catch (e) {
      Logging.error('Login failed: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _remoteDataSource.logout();
    } catch (e) {
      Logging.error('Logout failed: $e');
    }
    try {
      await _localDataSource.clearCache();
    } catch (e) {
      Logging.error('Logout cache clear failed: $e');
    }
  }

  @override
  Stream<UserEntity?> get authStateChanges {
    return _remoteDataSource.authStateChanges.asyncMap((user) async {
      if (user != null) {
        try {
          await _localDataSource.cacheUser(user);
        } on CacheException catch (e) {
          Logging.error('Failed to cache user: $e');
        }
        return user;
      } else {
        try {
          final cachedUser = await _localDataSource.getCachedUser();
          return cachedUser;
        } on CacheException catch (e) {
          Logging.error('Failed to read cached user: $e');
          return null;
        }
      }
    });
  }
}
