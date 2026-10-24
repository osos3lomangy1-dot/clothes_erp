import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheUser(UserModel user);
  Future<UserModel?> getCachedUser();
  Future<void> clearCache();
}

@LazySingleton(as: AuthLocalDataSource)
class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final FlutterSecureStorage _storage;
  static const String _userKey = 'cached_user';

  AuthLocalDataSourceImpl(this._storage);

  @override
  Future<void> cacheUser(UserModel user) async {
    try {
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } catch (e) {
      throw CacheException(e.toString());
    }
  }

  @override
  Future<UserModel?> getCachedUser() async {
    try {
      final jsonString = await _storage.read(key: _userKey);
      if (jsonString != null) {
        return UserModel.fromJson(jsonDecode(jsonString));
      }
      return null;
    } catch (e) {
      throw CacheException(e.toString());
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      await _storage.delete(key: _userKey);
    } catch (e) {
      throw CacheException(e.toString());
    }
  }
}
