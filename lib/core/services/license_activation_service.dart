import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'license_crypto_codec.dart';

export 'license_crypto_codec.dart';

enum LicenseState {
  trialActive,
  trialExpired,
  licensedLifetime,
  licensedExpiring,
  clockTampered,
}

class LicenseInfo {
  final LicenseState state;
  final String machineId;
  final int daysRemaining;
  final String? licenseKey;
  final String licenseType; // 'trial', 'lifetime', 'annual', 'trial_extension'
  final String tier; // 'basic', 'pro', 'enterprise'
  final DateTime? expiryDate;
  final DateTime? firstInstalledAt;
  final bool isActivated;
  final String statusMessage;

  const LicenseInfo({
    required this.state,
    required this.machineId,
    required this.daysRemaining,
    this.licenseKey,
    required this.licenseType,
    required this.tier,
    this.expiryDate,
    this.firstInstalledAt,
    required this.isActivated,
    required this.statusMessage,
  });

  bool get isValid =>
      state == LicenseState.trialActive ||
      state == LicenseState.licensedLifetime ||
      state == LicenseState.licensedExpiring;
}

class LicenseActivationService {
  static const String secretKey = LicenseCryptoCodec.secretKey;
  static const int defaultTrialDays = 14;

  final AppDatabase _db;
  final _statusController = StreamController<LicenseInfo>.broadcast();

  LicenseActivationService(this._db);

  Stream<LicenseInfo> get onStatusChanged => _statusController.stream;

  void dispose() {
    _statusController.close();
  }

  /// Generates or retrieves the unique hardware machine identifier.
  /// Formatted as: BAY3AH-XXXX-YYYY-ZZZZ
  Future<String> getMachineId() async {
    final existingRow = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('license.machine_id')))
        .getSingleOrNull();

    if (existingRow != null && existingRow.value.trim().isNotEmpty) {
      return existingRow.value.trim();
    }

    // Derive deterministic hardware fingerprint
    var raw = '${Platform.operatingSystem}_${Platform.environment['COMPUTERNAME'] ?? 'LOCAL'}_'
        '${Platform.environment['PROCESSOR_IDENTIFIER'] ?? 'CPU'}_'
        '${Platform.environment['PROCESSOR_REVISION'] ?? 'REV'}';

    if (Platform.isWindows) {
      try {
        final result = Process.runSync(
          'reg',
          ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid'],
          runInShell: true,
        );
        if (result.exitCode == 0 && result.stdout != null) {
          final match = RegExp(r'MachineGuid\s+REG_SZ\s+([a-zA-Z0-9\-]+)')
              .firstMatch(result.stdout.toString());
          if (match != null) {
            raw += '_${match.group(1)}';
          }
        }
      } catch (_) {}
    }

    final hashBytes = sha256.convert(utf8.encode(raw)).bytes;
    final hexStr = hashBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    final machineId = 'BAY3AH-${hexStr.substring(0, 4)}-${hexStr.substring(4, 8)}-${hexStr.substring(8, 12)}';

    await _db.into(_db.appMeta).insert(
          AppMetaCompanion.insert(
            key: 'license.machine_id',
            value: machineId,
            updatedAt: DateTime.now(),
          ),
          mode: InsertMode.insertOrReplace,
        );

    return machineId;
  }

  /// Checks the current license and trial lifecycle, including anti-clock rollback detection.
  Future<LicenseInfo> checkLicenseStatus() async {
    final machineId = await getMachineId();
    final now = DateTime.now();

    // 1. Anti-Clock Rollback Detection
    final lastSeenRow = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('license.last_seen_date')))
        .getSingleOrNull();

    if (lastSeenRow != null) {
      final lastSeen = DateTime.tryParse(lastSeenRow.value);
      if (lastSeen != null && now.isBefore(lastSeen.subtract(const Duration(minutes: 5)))) {
        final info = LicenseInfo(
          state: LicenseState.clockTampered,
          machineId: machineId,
          daysRemaining: 0,
          licenseType: 'none',
          tier: 'none',
          isActivated: false,
          statusMessage: 'تم اكتشاف تلاعب في ساعة النظام. يرجى ضبط توقيت ويندوز أو إدخال كود التفعيل.',
        );
        _statusController.add(info);
        return info;
      }
    }

    // Record last seen date
    await _db.into(_db.appMeta).insert(
          AppMetaCompanion.insert(
            key: 'license.last_seen_date',
            value: now.toIso8601String(),
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );

    // 2. Check for active license key
    final statusRow = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('license.status')))
        .getSingleOrNull();
    final keyRow = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('license.key')))
        .getSingleOrNull();

    if (statusRow?.value == 'active' && keyRow != null && keyRow.value.trim().isNotEmpty) {
      final key = keyRow.value.trim();
      final verification = verifyKey(key, expectedMachineId: machineId);

      if (verification != null) {
        final isLifetime = verification.type == 'lifetime' || verification.expiryDate == null;
        if (isLifetime) {
          final info = LicenseInfo(
            state: LicenseState.licensedLifetime,
            machineId: machineId,
            daysRemaining: 9999,
            licenseKey: key,
            licenseType: 'lifetime',
            tier: verification.tier,
            isActivated: true,
            statusMessage: 'نسخة مرخصة ومدفوعة رسمياً مدى الحياة',
          );
          _statusController.add(info);
          return info;
        } else {
          final exp = verification.expiryDate!;
          final remaining = exp.difference(now).inDays;
          if (now.isBefore(exp)) {
            final info = LicenseInfo(
              state: LicenseState.licensedExpiring,
              machineId: machineId,
              daysRemaining: remaining,
              licenseKey: key,
              licenseType: verification.type,
              tier: verification.tier,
              expiryDate: exp,
              isActivated: true,
              statusMessage: 'نسخة مرخصة رسمياً (متبقي $remaining يوم)',
            );
            _statusController.add(info);
            return info;
          }
        }
      }
    }

    // 3. Fallback: Free Trial Lifecycle (14 days)
    final trialStartRow = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('license.trial_start')))
        .getSingleOrNull();

    DateTime trialStart;
    if (trialStartRow == null) {
      trialStart = now;
      await _db.into(_db.appMeta).insert(
            AppMetaCompanion.insert(
              key: 'license.trial_start',
              value: trialStart.toIso8601String(),
              updatedAt: now,
            ),
            mode: InsertMode.insertOrReplace,
          );
    } else {
      trialStart = DateTime.tryParse(trialStartRow.value) ?? now;
    }

    final trialEnd = trialStart.add(const Duration(days: defaultTrialDays));
    final remainingDays = trialEnd.difference(now).inDays;

    if (now.isBefore(trialEnd) && remainingDays >= 0) {
      final info = LicenseInfo(
        state: LicenseState.trialActive,
        machineId: machineId,
        daysRemaining: remainingDays,
        licenseType: 'trial',
        tier: 'enterprise',
        firstInstalledAt: trialStart,
        expiryDate: trialEnd,
        isActivated: false,
        statusMessage: 'النسخة التجريبية المجانية - متبقي $remainingDays يوم',
      );
      _statusController.add(info);
      return info;
    } else {
      final info = LicenseInfo(
        state: LicenseState.trialExpired,
        machineId: machineId,
        daysRemaining: 0,
        licenseType: 'trial',
        tier: 'enterprise',
        firstInstalledAt: trialStart,
        expiryDate: trialEnd,
        isActivated: false,
        statusMessage: 'انتهت الفترة التجريبية للنظام. يرجى إدخال كود التفعيل المرخص للمتابعة.',
      );
      _statusController.add(info);
      return info;
    }
  }

  /// Verifies and activates a license key for this machine.
  Future<LicenseInfo> activateLicense(String licenseKey) async {
    final cleanKey = licenseKey.trim();
    if (cleanKey.isEmpty) {
      throw Exception('يرجى إدخال كود التفعيل.');
    }

    final machineId = await getMachineId();
    final verification = verifyKey(cleanKey, expectedMachineId: machineId);

    if (verification == null) {
      throw Exception('كود التفعيل غير صالح، أو مخصص لجهاز آخر، أو تم التلاعب به.');
    }

    final now = DateTime.now();
    if (verification.expiryDate != null && now.isAfter(verification.expiryDate!)) {
      throw Exception('كود التفعيل منتهي الصلاحية.');
    }

    // Persist activated license
    await _db.into(_db.appMeta).insert(
          AppMetaCompanion.insert(
            key: 'license.status',
            value: 'active',
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );

    await _db.into(_db.appMeta).insert(
          AppMetaCompanion.insert(
            key: 'license.key',
            value: cleanKey,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );

    await _db.into(_db.appMeta).insert(
          AppMetaCompanion.insert(
            key: 'license.type',
            value: verification.type,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );

    await _db.into(_db.appMeta).insert(
          AppMetaCompanion.insert(
            key: 'license.tier',
            value: verification.tier,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );

    if (verification.expiryDate != null) {
      await _db.into(_db.appMeta).insert(
            AppMetaCompanion.insert(
              key: 'license.expiry',
              value: verification.expiryDate!.toIso8601String(),
              updatedAt: now,
            ),
            mode: InsertMode.insertOrReplace,
          );
    }

    return await checkLicenseStatus();
  }

  /// Cryptographic offline key verification.
  static DecodedLicensePayload? verifyKey(
    String key, {
    String? expectedMachineId,
  }) {
    return LicenseCryptoCodec.verifyKey(key, expectedMachineId: expectedMachineId);
  }

  /// Generates a signed cryptographic license key for a specific Machine ID.
  static String generateKey({
    required String machineId,
    required String type,
    required String tier,
    DateTime? expiryDate,
  }) {
    return LicenseCryptoCodec.generateKey(
      machineId: machineId,
      type: type,
      tier: tier,
      expiryDate: expiryDate,
    );
  }
}
