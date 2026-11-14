import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clothes_erp/core/features/feature_gate.dart';

class FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

void main() {
  late AppDatabase db;
  late FakeAuthLocalDataSource auth;
  late ManagerPinService pin;
  late FeatureGate gate;
  const adminId = 'admin-1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuthLocalDataSource()
      ..setUser(UserModel(
        id: adminId,
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ));
    final tx = TxWriter(db);
    final branch = BranchProvider(db);
    gate = FeatureGate(db, auth, tx, branch);
    pin = ManagerPinService(db, tx, branch, auth, gate);
  });

  tearDown(() async => db.close());

  Future<int> auditCount(String action) async {
    final rows = await (db.select(db.auditLogs)..where((t) => t.action.equals(action))).get();
    return rows.length;
  }

  test('admin can set PIN and correct PIN verifies (audited)', () async {
    await pin.setPin(pin: '1234', userId: adminId);
    expect(await pin.isPinSet(), true);
    final before = await auditCount('pin_verify_success');
    final res = await pin.verifyPin(pin: '1234', operation: 'create_contract', now: DateTime(2026, 1, 1, 10));
    expect(res.ok, true);
    expect(await auditCount('pin_verify_success'), before + 1);
  });

  test('admin can rotate PIN (audited)', () async {
    await pin.setPin(pin: '1111', userId: adminId);
    await pin.setPin(pin: '2222', userId: adminId);
    final rotates = await auditCount('pin_rotated');
    expect(rotates >= 1, true);
    final okNew = await pin.verifyPin(pin: '2222', operation: 'op', now: DateTime(2026, 1, 1, 10));
    expect(okNew.ok, true);
    final okOld = await pin.verifyPin(pin: '1111', operation: 'op', now: DateTime(2026, 1, 1, 10, 1));
    expect(okOld.ok, false);
  });

  test('wrong PIN rejects and writes audit log', () async {
    await pin.setPin(pin: '1234', userId: adminId);
    final before = await auditCount('pin_verify_failed');
    final res = await pin.verifyPin(pin: '9999', operation: 'record_payment', now: DateTime(2026, 1, 1, 10));
    expect(res.ok, false);
    expect(res.locked, false);
    expect(await auditCount('pin_verify_failed'), before + 1);
  });

  test('lockout after N failed attempts within window and logs attempts', () async {
    await pin.setPin(pin: '1234', userId: adminId);
    final now = DateTime(2026, 1, 1, 12, 0);
    PinVerificationResult? last;
    for (var i = 0; i < ManagerPinService.maxAttempts; i++) {
      last = await pin.verifyPin(pin: '0000', operation: 'cancel', now: now.add(Duration(seconds: i)));
    }
    expect(last!.locked, true);
    final lockedLogs = await auditCount('pin_verify_locked');
    expect(lockedLogs >= 1, true);
    // while locked, further attempts audited as locked
    final lockedTry = await pin.verifyPin(pin: '1234', operation: 'cancel', now: now.add(const Duration(minutes: 1)));
    expect(lockedTry.ok, false);
    expect(lockedTry.locked, true);
  });

  test('PIN required toggle defaults to ON', () async {
    expect(await pin.isPinRequired(), true);
  });

  test('cashier cannot set PIN (admin-only at domain level)', () async {
    // 1. Initial PIN set by admin
    final adminSet = await pin.setPin(pin: '1234', userId: adminId);
    expect(adminSet.isRight(), isTrue);
    final initialHashRow = await (db.select(db.appMeta)..where((t) => t.key.equals('installments.pin.hash'))).getSingle();
    final initialHash = initialHashRow.value;

    // 2. Switch user to cashier
    auth.setUser(UserModel(
      id: 'cashier-1',
      name: 'Cashier',
      email: 'c@c.c',
      role: 'cashier',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    ));

    // 3. Cashier attempts setPin / rotatePin -> must return Left(AuthFailure)
    final cashierSet = await pin.setPin(pin: '9999', userId: 'cashier-1');
    expect(cashierSet, isA<Left>());
    expect((cashierSet as Left).value, isA<AuthFailure>());
    cashierSet.fold(
      (failure) {
        expect(failure, isA<AuthFailure>());
        expect(failure.message, contains('غير مصرح'));
      },
      (_) => fail('Cashier must not be able to set or rotate PIN'),
    );

    // 4. Verify PIN in app_meta did not change
    final currentHashRow = await (db.select(db.appMeta)..where((t) => t.key.equals('installments.pin.hash'))).getSingle();
    expect(currentHashRow.value, equals(initialHash), reason: 'PIN hash in app_meta must remain unchanged after cashier attempt');

    // 5. Old PIN still verifies successfully
    final verifyOld = await pin.verifyPin(pin: '1234', operation: 'op', now: DateTime(2026, 1, 1, 10));
    expect(verifyOld.ok, isTrue);

    // 6. Cashier attempted PIN fails
    final verifyAttempted = await pin.verifyPin(pin: '9999', operation: 'op', now: DateTime(2026, 1, 1, 10, 1));
    expect(verifyAttempted.ok, isFalse);
  });

  test('PIN is stored hashed in app_meta, not plaintext', () async {
    const rawPin = '1234';
    await pin.setPin(pin: rawPin, userId: adminId);

    final hashRow = await (db.select(db.appMeta)..where((t) => t.key.equals('installments.pin.hash'))).getSingle();
    final saltRow = await (db.select(db.appMeta)..where((t) => t.key.equals('installments.pin.salt'))).getSingle();

    final storedHash = hashRow.value;
    final storedSalt = saltRow.value;

    expect(storedHash, isNot(equals(rawPin)), reason: 'PIN must not be stored in plaintext');
    expect(storedHash.length, 64, reason: 'SHA-256 hash must be exactly 64 hex characters');
    expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(storedHash), isTrue, reason: 'Hash must be valid lowercase hex');
    expect(storedSalt.isNotEmpty, isTrue, reason: 'Salt must not be empty');

    final res = await pin.verifyPin(pin: rawPin, operation: 'contract_creation');
    expect(res.ok, isTrue, reason: 'Verification with correct raw PIN must succeed');
  });

  test('PIN required enforcement', () async {
    await pin.setPin(pin: '1234', userId: adminId);

    // Case 1: require = true
    await pin.setPinRequired(required: true, userId: adminId);
    expect(await pin.isPinRequired(), isTrue);

    // Wrong PIN -> fail
    final wrongRes = await pin.verifyPin(pin: '9999', operation: 'create_contract');
    expect(wrongRes.ok, isFalse, reason: 'Wrong PIN must fail when require=true');

    // Correct PIN -> success
    final correctRes = await pin.verifyPin(pin: '1234', operation: 'create_contract');
    expect(correctRes.ok, isTrue, reason: 'Correct PIN must succeed when require=true');

    // Case 2: require = false
    await pin.setPinRequired(required: false, userId: adminId);
    expect(await pin.isPinRequired(), isFalse);

    // Without PIN -> success
    final noPinRes = await pin.verifyPin(pin: '', operation: 'create_contract');
    expect(noPinRes.ok, isTrue, reason: 'Empty PIN must succeed when require=false');
  });
}
