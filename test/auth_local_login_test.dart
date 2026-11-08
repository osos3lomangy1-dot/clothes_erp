import 'dart:io';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake AuthLocalDataSource using in-memory variable
class FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? cached;

  @override
  Future<void> cacheUser(UserModel user) async {
    cached = user;
  }

  @override
  Future<void> clearCache() async {
    cached = null;
  }

  @override
  Future<UserModel?> getCachedUser() async {
    return cached;
  }
}

// Fake AuthRemoteDataSource that always throws or returns mock
class FakeAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  Stream<UserModel?> get authStateChanges => Stream.value(null);

  @override
  Future<UserModel> login(String email, String password) async {
    throw Exception('Remote not reachable offline');
  }

  @override
  Future<void> logout() async {}
}

void main() {
  group('Local & Offline Authentication Tests', () {
    late AppDatabase db;
    late FakeAuthLocalDataSource localDataSource;
    late FakeAuthRemoteDataSource remoteDataSource;
    late AuthRepositoryImpl authRepo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      localDataSource = FakeAuthLocalDataSource();
      remoteDataSource = FakeAuthRemoteDataSource();
      authRepo = AuthRepositoryImpl(remoteDataSource, localDataSource, db);

      // Seed a test employee
      final now = DateTime.now();
      await db.into(db.users).insert(
        UsersCompanion.insert(
          id: 'emp-salem',
          branchId: 'branch-1',
          username: 'salem_cashier',
          displayName: 'سالم الكاشير',
          role: 'cashier',
          passwordHash: 'hash_123456',
          passwordSalt: 'salt123',
          isActive: const drift.Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Seed an inactive employee
      await db.into(db.users).insert(
        UsersCompanion.insert(
          id: 'emp-inactive',
          branchId: 'branch-1',
          username: 'inactive_user',
          displayName: 'موظف معطل',
          role: 'cashier',
          passwordHash: 'hash_123456',
          passwordSalt: 'salt123',
          isActive: const drift.Value(false),
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Login with created employee username and password succeeds offline', () async {
      final result = await authRepo.login('salem_cashier', '123456');

      expect(result.isRight(), true);
      result.fold(
        (failure) => fail('Should succeed: ${failure.message}'),
        (user) {
          expect(user.id, equals('emp-salem'));
          expect(user.name, equals('سالم الكاشير'));
          expect(user.email, equals('salem_cashier'));
          expect(user.role, equals('cashier'));
          expect(user.isActive, equals(true));
        },
      );

      // Verify cached user in storage
      final cached = await localDataSource.getCachedUser();
      expect(cached?.id, equals('emp-salem'));
    });

    test('Login is case-insensitive for username', () async {
      final result = await authRepo.login('SALEM_CASHIER', '123456');
      expect(result.isRight(), true);
    });

    test('Login with wrong password returns descriptive Arabic error', () async {
      final result = await authRepo.login('salem_cashier', 'wrong_pass');

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure.message, contains('كلمة المرور غير صحيحة')),
        (_) => fail('Should fail with wrong password'),
      );
    });

    test('Login with disabled/inactive account is blocked', () async {
      final result = await authRepo.login('inactive_user', '123456');

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure.message, contains('تم تعطيل هذا الحساب')),
        (_) => fail('Should be blocked'),
      );
    });

    test('Default admin can log in on fresh database', () async {
      final result = await authRepo.login('admin', 'admin123');

      expect(result.isRight(), true);
      result.fold(
        (failure) => fail('Admin should succeed: ${failure.message}'),
        (user) {
          expect(user.role, equals('admin'));
        },
      );
    });

    test('Logout clears cached user session', () async {
      await authRepo.login('salem_cashier', '123456');
      expect(await localDataSource.getCachedUser(), isNotNull);

      await authRepo.logout();
      expect(await localDataSource.getCachedUser(), isNull);
    });
  });

  group('Migration Idempotence Tests (Duplicate Column Protection)', () {
    test('Opening database with pre-existing wholesale_price column does NOT throw duplicate column exception', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_duplicate_col_${DateTime.now().millisecondsSinceEpoch}.db');
      if (tempFile.existsSync()) tempFile.deleteSync();

      try {
        // 1. Create a database
        var db = AppDatabase(NativeDatabase(tempFile));
        await db.customSelect('SELECT 1').get();
        await db.close();

        // 2. Open it again - onUpgrade and beforeOpen will run
        // With our fix, this MUST succeed without throwing duplicate column error!
        db = AppDatabase(NativeDatabase(tempFile));
        final info = await db.customSelect('PRAGMA table_info(product_variants)').get();
        final names = info.map((r) => r.data['name']).toSet();
        expect(names.contains('wholesale_price'), true);
        await db.close();
      } finally {
        if (tempFile.existsSync()) tempFile.deleteSync();
      }
    });
  });
}

