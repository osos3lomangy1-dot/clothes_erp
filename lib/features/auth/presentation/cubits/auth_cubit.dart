import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/utils/logging.dart';
import '../../domain/usecases/get_auth_status_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import 'auth_state.dart';

@injectable
class AuthCubit extends Cubit<AuthState> {
  final LoginUseCase _loginUseCase;
  final LogoutUseCase _logoutUseCase;
  final GetAuthStatusUseCase _getAuthStatusUseCase;
  StreamSubscription? _authSubscription;

  AuthCubit(
    this._loginUseCase,
    this._logoutUseCase,
    this._getAuthStatusUseCase,
  ) : super(AuthInitial()) {
    _monitorAuthState();
  }

  void _monitorAuthState() {
    _authSubscription = _getAuthStatusUseCase().listen(
      (user) {
        if (user != null) {
          emit(AuthAuthenticated(user));
        } else if (state is! AuthAuthenticated) {
          emit(AuthUnauthenticated());
        }
      },
      onError: (e) {
        Logging.error('⚠️ [Cubit] Stream error: $e');
        if (state is! AuthAuthenticated) {
          emit(AuthUnauthenticated());
        }
      },
    );
  }

  Future<void> login(String email, String password) async {
    emit(AuthLoading());
    final result = await _loginUseCase(email, password);
    result.fold(
      (failure) => emit(AuthError(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> logout() async {
    try {
      await _logoutUseCase();
    } catch (e) {
      Logging.error('Logout failed: $e');
    }
    emit(AuthUnauthenticated());
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
