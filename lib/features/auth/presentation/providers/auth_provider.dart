import 'package:flutter/material.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  UserEntity? _user;
  bool _isLoading = false;

  AuthProvider(this._authRepository) {
    _checkAuth();
  }

  UserEntity? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  void _checkAuth() {
    _authRepository.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<String?> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authRepository.login(email, password);
    
    return result.fold(
      (failure) {
        _isLoading = false;
        notifyListeners();
        return failure.message;
      },
      (user) {
        _user = user;
        _isLoading = false;
        notifyListeners();
        return null;
      },
    );
  }

  Future<void> logout() async {
    await _authRepository.logout();
    _user = null;
    notifyListeners();
  }
}
