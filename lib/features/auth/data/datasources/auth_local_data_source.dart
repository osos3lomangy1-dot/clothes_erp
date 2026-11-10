import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/utils/logging.dart';
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
  UserModel? _memoryCache;

  AuthLocalDataSourceImpl(this._storage);

  @override
  Future<void> cacheUser(UserModel user) async {
    _memoryCache = user;
    try {
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    } catch (e) {
      Logging.warn('SecureStorage write failed (memory cache active): $e');
    }
  }

  @override
  Future<UserModel?> getCachedUser() async {
    if (_memoryCache != null) return _memoryCache;
    try {
      final jsonString = await _storage.read(key: _userKey);
      if (jsonString != null) {
        _memoryCache = UserModel.fromJson(jsonDecode(jsonString));
        return _memoryCache;
      }
      return null;
    } catch (e) {
      Logging.warn('SecureStorage read failed: $e');
      return _memoryCache;
    }
  }

  @override
  Future<void> clearCache() async {
    _memoryCache = null;
    try {
      await _storage.delete(key: _userKey);
    } catch (e) {
      Logging.warn('SecureStorage delete failed: $e');
    }
  }
}
