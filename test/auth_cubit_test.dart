import 'dart:async';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/auth/domain/entities/user_entity.dart';
import 'package:clothes_erp/features/auth/domain/repositories/auth_repository.dart';
import 'package:clothes_erp/features/auth/domain/usecases/get_auth_status_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/login_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/logout_usecase.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  final StreamController<UserEntity?> _authStreamController =
      StreamController<UserEntity?>.broadcast();
  Either<Failure, UserEntity>? loginResult;
  bool shouldThrowOnLogin = false;

  @override
  Stream<UserEntity?> get authStateChanges => _authStreamController.stream;

  @override
  Future<Either<Failure, UserEntity>> login(String email, String password) async {
    if (shouldThrowOnLogin) {
      throw Exception('Network completely unreachable or unexpected error');
    }
    return loginResult ?? const Left(ServerFailure('Invalid credentials'));
  }

  @override
  Future<void> logout() async {
    _authStreamController.add(null);
  }

  void dispose() {
    _authStreamController.close();
  }
}

void main() {
  group('AuthCubit Robustness and Error Handling Tests', () {
    late AppDatabase db;
    late FakeAuthRepository fakeRepo;
    late LoginUseCase loginUseCase;
    late LogoutUseCase logoutUseCase;
    late GetAuthStatusUseCase getAuthStatusUseCase;
    late AuthCubit authCubit;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      fakeRepo = FakeAuthRepository();
      loginUseCase = LoginUseCase(fakeRepo);
      logoutUseCase = LogoutUseCase(fakeRepo);
      getAuthStatusUseCase = GetAuthStatusUseCase(fakeRepo);
      authCubit = AuthCubit(loginUseCase, logoutUseCase, getAuthStatusUseCase, db);
    });

    tearDown(() async {
      await authCubit.close();
      fakeRepo.dispose();
      await db.close();
    });

    test('Emits AuthError when user exists in remote auth but NOT in local Drift DB', () async {
      final remoteUser = UserEntity(
        id: 'user_unknown_in_db',
        name: 'كاشير مجهول',
        email: 'unknown@store.com',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      );

      fakeRepo.loginResult = Right(remoteUser);

      final expectedStates = <AuthState>[];
      final subscription = authCubit.stream.listen(expectedStates.add);

      await authCubit.login('unknown@store.com', 'password123');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(authCubit.state, isA<AuthError>());
      final errorState = authCubit.state as AuthError;
      expect(
        errorState.message,
        'لم يتم العثور على بيانات المستخدم على هذا الجهاز. يرجى التواصل مع الإدارة.',
      );

      await subscription.cancel();
    });

    test('Emits AuthAuthenticated when user exists in remote auth AND in local Drift DB', () async {
      final now = DateTime.now();
      await db.into(db.users).insert(
        UsersCompanion.insert(
          id: 'emp-local-1',
          branchId: 'branch-1',
          username: 'local_cashier',
          displayName: 'كاشير محلي',
          role: 'cashier',
          passwordHash: 'hash',
          passwordSalt: 'salt',
          isActive: const drift.Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final remoteUser = UserEntity(
        id: 'emp-local-1',
        name: 'كاشير محلي',
        email: 'local_cashier',
        role: 'cashier',
        isActive: true,
        createdAt: now,
      );

      fakeRepo.loginResult = Right(remoteUser);

      await authCubit.login('local_cashier', 'password123');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(authCubit.state, isA<AuthAuthenticated>());
      final authState = authCubit.state as AuthAuthenticated;
      expect(authState.user.id, 'emp-local-1');
    });

    test('Default admin bypasses missing local DB check and authenticates successfully', () async {
      final adminUser = UserEntity(
        id: 'admin_default',
        name: 'Admin',
        email: 'admin',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );

      fakeRepo.loginResult = Right(adminUser);

      await authCubit.login('admin', 'admin');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(authCubit.state, isA<AuthAuthenticated>());
    });

    test('Catches unexpected exceptions during login without crashing, emitting AuthError', () async {
      fakeRepo.shouldThrowOnLogin = true;

      // Should not throw an unhandled exception or crash
      await expectLater(
        authCubit.login('test@user.com', 'secret'),
        completes,
      );

      expect(authCubit.state, isA<AuthError>());
      final errorState = authCubit.state as AuthError;
      expect(
        errorState.message,
        'لم يتم العثور على بيانات المستخدم على هذا الجهاز. يرجى التواصل مع الإدارة.',
      );
    });
  });
}

