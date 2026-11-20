import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'database_verification_service.dart';
import 'migration_marker_service.dart';

class _RecoveryQueryUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}

  @override
  int get schemaVersion => 1;
}

enum EmergencyReason { none, incompleteMigration, databaseCorrupted }

class EmergencyStatus {
  final bool isEmergency;
  final EmergencyReason reason;
  final MigrationMarker? marker;
  final File? backupFile;
  final String? integrityMessage;

  const EmergencyStatus({
    required this.isEmergency,
    this.reason = EmergencyReason.none,
    this.marker,
    this.backupFile,
    this.integrityMessage,
  });
}

class EmergencyRecoveryService {
  final File activeDbFile;
  final MigrationMarkerService markerService;
  final String appVersion;

  EmergencyRecoveryService({
    required this.activeDbFile,
    required this.markerService,
    this.appVersion = '1.0.0',
  });

  /// Evaluates whether emergency recovery is required at startup.
  Future<EmergencyStatus> checkRecoveryNeeded() async {
    // 1. Check for active migration marker
    try {
      final marker = await markerService.readMarker();
      if (marker != null && marker.backupState == BackupState.verified) {
        final bFile = File(marker.backupPath);
        if (bFile.existsSync()) {
          return EmergencyStatus(
            isEmergency: true,
            reason: EmergencyReason.incompleteMigration,
            marker: marker,
            backupFile: bFile,
          );
        }
      }
    } catch (_) {}

    // 2. Check if active DB file is physically damaged / corrupted
    if (activeDbFile.existsSync()) {
      try {
        final version = await DatabaseVerificationService.getSqliteVersion(
          activeDbFile,
        );
        if (version.isEmpty || version == 'unknown') {
          return EmergencyStatus(
            isEmergency: true,
            reason: EmergencyReason.databaseCorrupted,
            integrityMessage: 'Unable to open SQLite database header',
          );
        }

        final executor = NativeDatabase(activeDbFile);
        await executor.ensureOpen(_RecoveryQueryUser());
        final rows = await executor.runSelect('PRAGMA quick_check;', []);
        await executor.close();

        if (rows.isEmpty || rows.first.values.first != 'ok') {
          return EmergencyStatus(
            isEmergency: true,
            reason: EmergencyReason.databaseCorrupted,
            integrityMessage: rows.isEmpty
                ? 'Empty check result'
                : rows.first.values.first.toString(),
          );
        }
      } catch (e) {
        return EmergencyStatus(
          isEmergency: true,
          reason: EmergencyReason.databaseCorrupted,
          integrityMessage: e.toString(),
        );
      }
    }

    return const EmergencyStatus(isEmergency: false);
  }

  /// Exports a privacy-safe diagnostic report (ZERO customer/financial data).
  Future<String> exportDiagnosticReport(EmergencyStatus status) async {
    String sqliteVer = 'unknown';
    int activeSize = 0;
    int backupSize = 0;

    if (activeDbFile.existsSync()) {
      try {
        activeSize = await activeDbFile.length();
        sqliteVer = await DatabaseVerificationService.getSqliteVersion(
          activeDbFile,
        );
      } catch (_) {}
    }

    if (status.backupFile != null && status.backupFile!.existsSync()) {
      try {
        backupSize = await status.backupFile!.length();
      } catch (_) {}
    }

    final report = <String, dynamic>{
      'report_type': 'Bay3ah_ERP_Emergency_Diagnostic',
      'generated_at': DateTime.now().toIso8601String(),
      'app_version': appVersion,
      'os_platform': Platform.operatingSystem,
      'sqlite_version': sqliteVer,
      'emergency_reason': status.reason.name,
      'integrity_message': status.integrityMessage ?? 'none',
      'active_db_exists': activeDbFile.existsSync(),
      'active_db_bytes': activeSize,
      'backup_db_exists': status.backupFile?.existsSync() ?? false,
      'backup_db_bytes': backupSize,
      'marker_details': status.marker != null
          ? {
              'format_version': status.marker!.formatVersion,
              'version_from': status.marker!.versionFrom,
              'version_to': status.marker!.versionTo,
              'backup_state': status.marker!.backupState.name,
              'attempt_count': status.marker!.attemptCount,
              'timestamp': status.marker!.timestamp.toIso8601String(),
            }
          : null,
    };

    return const JsonEncoder.withIndent('  ').convert(report);
  }

  /// Performs atomic protected manual restoration from the verified backup.
  Future<bool> restoreFromVerifiedBackup(File backupFile) async {
    if (!backupFile.existsSync()) {
      throw StateError('Backup file does not exist at ${backupFile.path}');
    }

    // 1. Move corrupted/current active file aside
    if (activeDbFile.existsSync()) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final failedBackup = File('${activeDbFile.path}.corrupt_$nowMs');
      try {
        await activeDbFile.rename(failedBackup.path);
      } catch (_) {
        await activeDbFile.copy(failedBackup.path);
        try {
          await activeDbFile.delete();
        } catch (_) {}
      }
    }

    // Clean any stale WAL/SHM sidecars
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${activeDbFile.path}$suffix');
      if (sidecar.existsSync()) {
        try {
          await sidecar.delete();
        } catch (_) {}
      }
    }

    // 2. Copy verified backup to active path
    await backupFile.copy(activeDbFile.path);

    // 3. Verify integrity of the restored file
    final executor = NativeDatabase(activeDbFile);
    await executor.ensureOpen(_RecoveryQueryUser());
    final rows = await executor.runSelect('PRAGMA quick_check;', []);
    await executor.close();

    if (rows.isEmpty || rows.first.values.first != 'ok') {
      throw StateError('Restored database failed quick_check');
    }

    // 4. migration marker
    await markerService.clearMarker();
    return true;
  }
}
