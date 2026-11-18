import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';

class PinVerificationResult {
  final bool ok;
  final String? error;
  final bool locked;
  const PinVerificationResult._(this.ok, this.error, this.locked);
  const PinVerificationResult.success() : this._(true, null, false);
  const PinVerificationResult.failure(String e) : this._(false, e, false);
  const PinVerificationResult.lockedOut(String e) : this._(false, e, true);
}

@lazySingleton
class ManagerPinService {
  static const _saltKey = 'installments.pin.salt';
  static const _hashKey = 'installments.pin.hash';
  static const _failedKey = 'installments.pin.failed_attempts';
  static const _lockedUntilKey = 'installments.pin.locked_until';
  static const _requirePinKey = 'installments.pin.require';
  static const int maxAttempts = 5;
  static const Duration lockoutWindow = Duration(minutes: 15);

  final AppDatabase _db;
  final TxWriter _txWriter;
  final BranchProvider _branchProvider;
  final AuthLocalDataSource _auth;
  final FeatureGate _featureGate;
  final _rng = Random.secure();

  ManagerPinService(this._db, this._txWriter, this._branchProvider, this._auth, this._featureGate);

  Future<String?> _getMeta(String key) async {
    final row = await (_db.select(_db.appMeta)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  String _newSalt() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  Future<Either<Failure, Unit>> setPin({required String pin, required String userId}) async {
    if (!await _featureGate.isCurrentUserAdmin()) {
      return const Left(AuthFailure('غير مصرح: تعيين الرقم السري متاح للمدير فقط'));
    }
    final salt = _newSalt();
    final hash = _hash(pin, salt);
    final branchId = await _branchProvider.getBranchId();
    final oldHash = await _getMeta(_hashKey);
    await _txWriter.write(
      writeFn: () async {
        final now = DateTime.now();
        await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: Value(_saltKey), value: Value(salt), updatedAt: Value(now)));
        await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: Value(_hashKey), value: Value(hash), updatedAt: Value(now)));
        await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: const Value(_failedKey), value: const Value('0'), updatedAt: Value(now)));
        await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: const Value(_lockedUntilKey), value: const Value(''), updatedAt: Value(now)));
      },
      branchId: branchId,
      entity: 'app_meta',
      entityId: _hashKey,
      operation: 'upsert',
      userId: userId,
      oldValue: oldHash == null ? null : '***',
      newValue: '***',
      auditAction: oldHash == null ? 'pin_set' : 'pin_rotated',
      payload: '{"entity":"installments_pin"}',
    );
    return const Right(unit);
  }

  Future<bool> isPinSet() async => (await _getMeta(_hashKey)) != null;

  Future<bool> isPinRequired() async {
    final v = await _getMeta(_requirePinKey);
    if (v == null) return true; // default ON
    return v == '1';
  }

  Future<void> setPinRequired({required bool required, required String userId}) async {
    await _featureGate.setMeta(_requirePinKey, required ? '1' : '0', userId: userId);
  }

  Future<PinVerificationResult> verifyPin({required String pin, required String operation, DateTime? now}) async {
    final current = now ?? DateTime.now();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'unknown';
    final branchId = await _branchProvider.getBranchId();

    if (!await isPinRequired()) {
      await _txWriter.write(
        writeFn: () async {},
        branchId: branchId,
        entity: 'installments_pin',
        entityId: operation,
        operation: 'verify',
        userId: userId,
        oldValue: null,
        newValue: 'skipped_not_required',
        auditAction: 'pin_verify_skipped',
        payload: '{"operation":"$operation","required":false}',
      );
      return const PinVerificationResult.success();
    }

    final lockedUntilStr = await _getMeta(_lockedUntilKey);
    if (lockedUntilStr != null && lockedUntilStr.isNotEmpty) {
      final lockedUntil = DateTime.tryParse(lockedUntilStr);
      if (lockedUntil != null && current.isBefore(lockedUntil)) {
        await _txWriter.write(
          writeFn: () async {},
          branchId: branchId,
          entity: 'installments_pin',
          entityId: operation,
          operation: 'verify',
          userId: userId,
          oldValue: null,
          newValue: 'locked',
          auditAction: 'pin_verify_locked',
          payload: '{"operation":"$operation","locked":true}',
        );
        return PinVerificationResult.lockedOut('الرقم السري مقفل مؤقتاً. حاول لاحقاً.');
      }
    }

    final salt = await _getMeta(_saltKey);
    final hash = await _getMeta(_hashKey);
    if (salt == null || hash == null) {
      await _txWriter.write(
        writeFn: () async {},
        branchId: branchId,
        entity: 'installments_pin',
        entityId: operation,
        operation: 'verify',
        userId: userId,
        oldValue: null,
        newValue: 'not_set',
        auditAction: 'pin_verify_failed',
        payload: '{"operation":"$operation","reason":"not_set"}',
      );
      return const PinVerificationResult.failure('لم يتم تعيين الرقم السري بعد');
    }

    final ok = _hash(pin, salt) == hash;
    final failed = int.tryParse(await _getMeta(_failedKey) ?? '0') ?? 0;

    if (ok) {
      await _txWriter.write(
        writeFn: () async {
          await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: const Value(_failedKey), value: const Value('0'), updatedAt: Value(current)));
          await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: const Value(_lockedUntilKey), value: const Value(''), updatedAt: Value(current)));
        },
        branchId: branchId,
        entity: 'app_meta',
        entityId: _failedKey,
        operation: 'upsert',
        userId: userId,
        oldValue: '$failed',
        newValue: '0',
        auditAction: 'pin_verify_success',
        payload: '{"operation":"$operation"}',
      );
      return const PinVerificationResult.success();
    } else {
      final newFailed = failed + 1;
      final lock = newFailed >= maxAttempts;
      final lockedUntil = lock ? current.add(lockoutWindow).toIso8601String() : '';
      await _txWriter.write(
        writeFn: () async {
          await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: Value(_failedKey), value: Value('$newFailed'), updatedAt: Value(current)));
          await _db.into(_db.appMeta).insertOnConflictUpdate(AppMetaCompanion(key: Value(_lockedUntilKey), value: Value(lockedUntil), updatedAt: Value(current)));
        },
        branchId: branchId,
        entity: 'app_meta',
        entityId: _failedKey,
        operation: 'upsert',
        userId: userId,
        oldValue: '$failed',
        newValue: '$newFailed',
        auditAction: lock ? 'pin_verify_locked' : 'pin_verify_failed',
        payload: '{"operation":"$operation","attempts":$newFailed}',
      );
      if (lock) {
        return PinVerificationResult.lockedOut('تم قفل الرقم السري بعد محاولات فاشلة متعددة');
      }
      return const PinVerificationResult.failure('الرقم السري غير صحيح');
    }
  }
}
