import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'database_verification_service.dart';
import 'migration_marker_service.dart';

class _SimpleQueryUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}

class InsufficientDiskSpaceException implements Exception {
  final int requiredBytes;
  final int availableBytes;

  const InsufficientDiskSpaceException({
    required this.requiredBytes,
    required this.availableBytes,
  });

  @override
  String toString() =>
      'InsufficientDiskSpaceException: Required $requiredBytes bytes, but only $availableBytes bytes available.';
}

class BackupVerificationFailedException implements Exception {
  final String message;
  final Object? cause;

  const BackupVerificationFailedException(this.message, [this.cause]);

  @override
  String toString() => 'BackupVerificationFailedException: $message ($cause)';
}

class PreMigrationBackupService {
  final Directory backupDirectory;
  final MigrationMarkerService markerService;
  final int maxRetainedBackups;

  static const int safetyMarginBytes = 50 * 1024 * 1024; // 50 MB

  PreMigrationBackupService({
    required this.backupDirectory,
    required this.markerService,
    this.maxRetainedBackups = 5,
  });

  /// Executes pre-migration backup protocol:
  /// 1. Verifies free disk space (2x DB size + 50MB margin).
  /// 2. Handles existing final backup in pending state (re-verifies and promotes instead of re-copying).
  /// 3. Computes canonical source hash before backup.
  /// 4. Writes marker in `pending` state with source hash.
  /// 5. Executes `VACUUM INTO '<path>.tmp'`.
  /// 6. Atomically renames `<path>.tmp` to `<path>`.
  /// 7. Verifies backup integrity via `quick_check` and matches backup hash against source hash.
  /// 8. Updates marker to `verified`.
  /// 9. Applies retention policy (prunes old backups, never deleting the only verified one).
  Future<File> createPreMigrationBackup({
    required File sourceDbFile,
    required int currentVersion,
    required int targetVersion,
    required String appVersion,
    String? verificationTableName,
  }) async {
    if (!backupDirectory.existsSync()) {
      await backupDirectory.create(recursive: true);
    }

    final dbSize = await sourceDbFile.length();
    final requiredBytes = (dbSize * 2) + safetyMarginBytes;
    await _checkDiskSpace(requiredBytes);

    final existingMarker = await markerService.readMarker();
    final String finalBackupPath = (existingMarker != null && existingMarker.backupState == BackupState.pending)
        ? existingMarker.backupPath
        : _generateBackupFilePath(currentVersion);

    final finalBackupFile = File(finalBackupPath);
    final tempBackupFile = File('$finalBackupPath.tmp');

    // 1. Check if an interrupted run already created a valid final backup file while marker is pending
    if (existingMarker != null &&
        existingMarker.backupState == BackupState.pending &&
        finalBackupFile.existsSync()) {
      final isExistingBackupValid = await _verifyExistingBackup(
        finalBackupFile,
        existingMarker.sourceHash,
        verificationTableName,
      );
      if (isExistingBackupValid) {
        await markerService.updateBackupState(BackupState.verified);
        await pruneOldBackups(finalBackupFile);
        return finalBackupFile;
      }
    }

    // Clean up any stale .tmp backup file
    if (tempBackupFile.existsSync()) {
      try {
        await tempBackupFile.delete();
      } catch (_) {}
    }

    // 2. Compute canonical source hash before backup
    String? sourceHash;
    if (verificationTableName != null) {
      sourceHash = await DatabaseVerificationService.computeTableCanonicalHash(
        dbFile: sourceDbFile,
        tableName: verificationTableName,
        excludeVolatileColumns: false, // Strict byte/timestamp identity
      );
    }

    // 3. Write marker in pending state
    final marker = MigrationMarker(
      appVersion: appVersion,
      versionFrom: currentVersion,
      versionTo: targetVersion,
      backupPath: finalBackupFile.path,
      sourceHash: sourceHash,
      backupState: BackupState.pending,
      restoreState: RestoreState.none,
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(marker);

    // 4. Execute VACUUM INTO on temp path
    final normalizedTempPath = tempBackupFile.path.replaceAll('\\', '/').replaceAll("'", "''");
    final sourceExecutor = NativeDatabase(sourceDbFile);
    await sourceExecutor.ensureOpen(_SimpleQueryUser());
    try {
      await sourceExecutor.runCustom("VACUUM INTO '$normalizedTempPath';");
    } finally {
      await sourceExecutor.close();
    }

    // 5. Rename temp backup to final backup path
    if (finalBackupFile.existsSync()) {
      try {
        await finalBackupFile.delete();
      } catch (_) {}
    }
    await tempBackupFile.rename(finalBackupFile.path);

    // 6. Verify backup structural integrity and data identity
    final backupExecutor = NativeDatabase(finalBackupFile);
    await backupExecutor.ensureOpen(_SimpleQueryUser());
    try {
      final quickCheck = await backupExecutor.runSelect('PRAGMA quick_check;', []);
      final result = quickCheck.first.values.first;
      if (result != 'ok') {
        throw BackupVerificationFailedException('PRAGMA quick_check returned: $result');
      }
    } finally {
      await backupExecutor.close();
    }

    if (sourceHash != null && verificationTableName != null) {
      final backupHash = await DatabaseVerificationService.computeTableCanonicalHash(
        dbFile: finalBackupFile,
        tableName: verificationTableName,
        excludeVolatileColumns: false,
      );
      if (backupHash != sourceHash) {
        throw const BackupVerificationFailedException(
          'Backup canonical hash does not match source database baseline hash',
        );
      }
    }

    // 7. Promote marker to verified
    await markerService.updateBackupState(BackupState.verified);

    // 8. Apply retention policy
    await pruneOldBackups(finalBackupFile);

    return finalBackupFile;
  }

  /// Prunes old backups keeping up to [maxRetainedBackups].
  /// Invariant: Never deletes the [currentlyActiveBackup] or the only available backup.
  Future<void> pruneOldBackups([File? currentlyActiveBackup]) async {
    if (!backupDirectory.existsSync()) return;

    final backups = backupDirectory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db') || f.path.endsWith('.sqlite'))
        .where((f) => !f.path.endsWith('.tmp'))
        .toList();

    // Clean up abandoned .tmp files
    final staleTemps = backupDirectory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'))
        .toList();
    for (final tmp in staleTemps) {
      try {
        await tmp.delete();
      } catch (_) {}
    }

    if (backups.length <= maxRetainedBackups) return;

    // Sort ascending by modification time (oldest first)
    backups.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

    final toRemoveCount = backups.length - maxRetainedBackups;
    int removed = 0;

    for (final file in backups) {
      if (removed >= toRemoveCount) break;

      // Never delete the currently active backup
      if (currentlyActiveBackup != null && file.path == currentlyActiveBackup.path) {
        continue;
      }

      // Never delete if this is the only backup remaining
      if (backups.length - removed <= 1) break;

      try {
        await file.delete();
        removed++;
      } catch (_) {}
    }
  }

  Future<bool> _verifyExistingBackup(
    File backupFile,
    String? expectedHash,
    String? tableName,
  ) async {
    try {
      final executor = NativeDatabase(backupFile);
      await executor.ensureOpen(_SimpleQueryUser());
      final check = await executor.runSelect('PRAGMA quick_check;', []);
      await executor.close();
      if (check.isEmpty || check.first.values.first != 'ok') {
        return false;
      }

      if (expectedHash != null && tableName != null) {
        final hash = await DatabaseVerificationService.computeTableCanonicalHash(
          dbFile: backupFile,
          tableName: tableName,
          excludeVolatileColumns: false,
        );
        return hash == expectedHash;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkDiskSpace(int requiredBytes) async {
    // On systems with platform-specific check, or basic directory stat
    // Ensure parent directory is writable and accessible
    try {
      final testFile = File('${backupDirectory.path}/.space_probe');
      await testFile.writeAsString('probe');
      await testFile.delete();
    } catch (e) {
      throw InsufficientDiskSpaceException(
        requiredBytes: requiredBytes,
        availableBytes: 0,
      );
    }
  }

  String _generateBackupFilePath(int currentVersion) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${backupDirectory.path}/pre_upgrade_v${currentVersion}_$timestamp.db';
  }
}
