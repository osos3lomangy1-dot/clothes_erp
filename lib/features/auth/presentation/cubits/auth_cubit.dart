import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/logging.dart';
import '../../domain/usecases/get_auth_status_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import 'auth_state.dart';

@lazySingleton
class AuthCubit extends Cubit<AuthState> {
  final LoginUseCase _loginUseCase;
  final LogoutUseCase _logoutUseCase;
  final GetAuthStatusUseCase _getAuthStatusUseCase;
  final AppDatabase _db;
  StreamSubscription? _authSubscription;

  AuthCubit(
    this._loginUseCase,
    this._logoutUseCase,
    this._getAuthStatusUseCase,
    this._db,
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
    try {
      emit(AuthLoading());
      final result = await _loginUseCase(email, password);

      await result.fold(
        (failure) async {
          emit(AuthError(failure.message));
        },
        (user) async {
          try {
            final cleanInput = email.trim();
            // Check if user exists in local Drift users table
            final localUser = await (_db.select(_db.users)
                  ..where((u) =>
                      (u.id.equals(user.id) |
                       u.username.lower().equals(cleanInput.toLowerCase()) |
                       u.displayName.lower().equals(cleanInput.toLowerCase())) &
                      u.deletedAt.isNull()))
                .getSingleOrNull();

            final isDefaultUser = user.id == 'admin_default' ||
                user.id == 'cashier_default' ||
                user.email == 'admin' ||
                user.email == 'cashier' ||
                cleanInput.toLowerCase() == 'admin' ||
                cleanInput.toLowerCase() == 'cashier';

            // If the user exists remotely but NOT in the local Drift users table
            if (localUser == null && !isDefaultUser) {
              Logging.warn(
                'User ${user.id} authenticated remotely but missing from local Drift DB',
              );
              emit(
                const AuthError(
                  'لم يتم العثور على بيانات المستخدم على هذا الجهاز. يرجى التواصل مع الإدارة.',
                ),
              );
              return;
            }

            emit(AuthAuthenticated(user));
          } catch (dbError) {
            Logging.error('Local DB lookup error in AuthCubit: $dbError');
            emit(
              const AuthError(
                'لم يتم العثور على بيانات المستخدم على هذا الجهاز. يرجى التواصل مع الإدارة.',
              ),
            );
          }
        },
      );
    } catch (e, stackTrace) {
      Logging.error('Unexpected error in AuthCubit.login: $e\n$stackTrace');
      emit(
        const AuthError(
          'لم يتم العثور على بيانات المستخدم على هذا الجهاز. يرجى التواصل مع الإدارة.',
        ),
      );
    }
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
