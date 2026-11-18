import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../database/app_database.dart';
import '../features/feature_gate.dart';
import '../utils/logging.dart';

class BackupMetaKeys {
  static const String autoEnabled = 'backup.auto_enabled';
  static const String directory = 'backup.directory';
  static const String retentionCount = 'backup.retention_count';
  static const String lastBackupAt = 'backup.last_backup_at';
  static const String lastBackupPath = 'backup.last_backup_path';
  static const String lastAutoDate = 'backup.last_auto_date';
}

class LocalBackupConfig {
  final bool autoEnabled;
  final String directoryPath;
  final int retentionCount;
  final DateTime? lastBackupAt;
  final String? lastBackupPath;
  final String? lastAutoDate;

  const LocalBackupConfig({
    required this.autoEnabled,
    required this.directoryPath,
    required this.retentionCount,
    this.lastBackupAt,
    this.lastBackupPath,
    this.lastAutoDate,
  });
}

class BackupFileInfo {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;

  const BackupFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}

class BackupResult {
  final String filePath;
  final int sizeBytes;
  final DateTime createdAt;

  const BackupResult({
    required this.filePath,
    required this.sizeBytes,
    required this.createdAt,
  });
}

class RestoreResult {
  final String restoredFromPath;
  final String safetyBackupPath;

  const RestoreResult({
    required this.restoredFromPath,
    required this.safetyBackupPath,
  });
}

/// Safe local SQLite backup & restore service using SQLite's `VACUUM INTO`
/// (produces an atomic, consistent single-file backup even while WAL mode is active).
class LocalBackupService {
  final AppDatabase _db;
  final FeatureGate _featureGate;
  final Future<Directory> Function()? _defaultBackupDirProvider;
  final Future<File> Function()? _liveDbFileProvider;

  LocalBackupService(
    this._db,
    this._featureGate, {
    Future<Directory> Function()? defaultBackupDirProvider,
    Future<File> Function()? liveDbFileProvider,
  })  : _defaultBackupDirProvider = defaultBackupDirProvider,
        _liveDbFileProvider = liveDbFileProvider;

  Future<Directory> _resolveDefaultBackupDir() async {
    if (_defaultBackupDirProvider != null) {
      return _defaultBackupDirProvider();
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      return Directory('${docs.path}${Platform.pathSeparator}SalesSystemBackups');
    } catch (_) {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}${Platform.pathSeparator}backups');
    }
  }

  Future<File> resolveLiveDbFile() async {
    if (_liveDbFileProvider != null) {
      return _liveDbFileProvider();
    }
    final supportDir = await getApplicationSupportDirectory();
    return File('${supportDir.path}${Platform.pathSeparator}clothes_erp.sqlite');
  }

  Future<LocalBackupConfig> loadConfig() async {
    final autoRaw = await _featureGate.getMeta(BackupMetaKeys.autoEnabled);
    final dirRaw = await _featureGate.getMeta(BackupMetaKeys.directory);
    final retentionRaw = await _featureGate.getMeta(BackupMetaKeys.retentionCount);
    final lastAtRaw = await _featureGate.getMeta(BackupMetaKeys.lastBackupAt);
    final lastPathRaw = await _featureGate.getMeta(BackupMetaKeys.lastBackupPath);
    final lastAutoRaw = await _featureGate.getMeta(BackupMetaKeys.lastAutoDate);

    final defaultDir = await _resolveDefaultBackupDir();
    final directoryPath = (dirRaw != null && dirRaw.trim().isNotEmpty)
        ? dirRaw.trim()
        : defaultDir.path;

    return LocalBackupConfig(
      autoEnabled: autoRaw != '0', // enabled by default for local safety
      directoryPath: directoryPath,
      retentionCount: (int.tryParse(retentionRaw ?? '') ?? 30).clamp(3, 365),
      lastBackupAt: lastAtRaw != null ? DateTime.tryParse(lastAtRaw) : null,
      lastBackupPath: (lastPathRaw != null && lastPathRaw.isNotEmpty) ? lastPathRaw : null,
      lastAutoDate: lastAutoRaw,
    );
  }

  Future<void> setAutoEnabled(bool enabled, {required String userId}) async {
    await _featureGate.setMeta(
      BackupMetaKeys.autoEnabled,
      enabled ? '1' : '0',
      userId: userId,
    );
  }

  Future<void> setBackupDirectory(String directoryPath, {required String userId}) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('مسار مجلد النسخ الاحتياطي غير صالح');
    }
    final dir = Directory(trimmed);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await _featureGate.setMeta(
      BackupMetaKeys.directory,
      trimmed,
      userId: userId,
    );
  }

  Future<void> setRetentionCount(int count, {required String userId}) async {
    final clamped = count.clamp(3, 365);
    await _featureGate.setMeta(
      BackupMetaKeys.retentionCount,
      '$clamped',
      userId: userId,
    );
  }

  /// Creates an atomic, WAL-safe single-file SQLite backup at [targetFilePath].
  /// If [targetFilePath] is omitted, saves inside the configured backup folder.
  Future<BackupResult> createBackup({
    String? targetFilePath,
    String userId = 'system',
    bool updateMetadata = true,
  }) async {
    final now = DateTime.now();
    String destinationPath;
    if (targetFilePath != null && targetFilePath.trim().isNotEmpty) {
      destinationPath = targetFilePath.trim();
      if (!destinationPath.toLowerCase().endsWith('.sqlite') &&
          !destinationPath.toLowerCase().endsWith('.db')) {
        destinationPath = '$destinationPath.sqlite';
      }
    } else {
      final config = await loadConfig();
      final dir = Directory(config.directoryPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final stamp = _formatTimestamp(now);
      destinationPath =
          '${dir.path}${Platform.pathSeparator}sales_erp_backup_$stamp.sqlite';
    }

    final destFile = File(destinationPath);
    if (!destFile.parent.existsSync()) {
      await destFile.parent.create(recursive: true);
    }
    // VACUUM INTO requires the destination file not to exist yet
    if (destFile.existsSync()) {
      await destFile.delete();
    }

    final escapedPath = destFile.path.replaceAll("'", "''");
    await _db.customStatement("VACUUM INTO '$escapedPath'");

    if (!destFile.existsSync()) {
      throw Exception('فشل إنشاء ملف النسخة الاحتياطية');
    }
    final sizeBytes = await destFile.length();
    if (sizeBytes <= 0) {
      throw Exception('ملف النسخة الاحتياطية فارغ');
    }

    if (updateMetadata) {
      await _featureGate.setMeta(
        BackupMetaKeys.lastBackupAt,
        now.toIso8601String(),
        userId: userId,
      );
      await _featureGate.setMeta(
        BackupMetaKeys.lastBackupPath,
        destFile.path,
        userId: userId,
      );
    }

    return BackupResult(
      filePath: destFile.path,
      sizeBytes: sizeBytes,
      createdAt: now,
    );
  }

  /// Runs a silent daily automatic backup if enabled and not yet created today,
  /// then prunes older `auto_backup_*.sqlite` files beyond retention count.
  Future<BackupResult?> runAutoBackupIfDue({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final config = await loadConfig();
    if (!config.autoEnabled) return null;

    final todayKey = _formatDateOnly(current);
    if (config.lastAutoDate == todayKey) return null;

    try {
      final dir = Directory(config.directoryPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final targetPath =
          '${dir.path}${Platform.pathSeparator}auto_backup_$todayKey.sqlite';
      final result = await createBackup(
        targetFilePath: targetPath,
        userId: 'system_auto_backup',
        updateMetadata: true,
      );
      await _featureGate.setMeta(
        BackupMetaKeys.lastAutoDate,
        todayKey,
        userId: 'system_auto_backup',
      );
      await pruneOldAutoBackups(
        directoryPath: dir.path,
        keepCount: config.retentionCount,
      );
      Logging.info('💾 [AutoBackup] Created daily backup: ${result.filePath}');
      return result;
    } catch (e) {
      Logging.error('⚠️ [AutoBackup] Failed: $e');
      return null;
    }
  }

  /// Deletes older `auto_backup_*.sqlite` files keeping only the newest [keepCount].
  Future<int> pruneOldAutoBackups({
    required String directoryPath,
    required int keepCount,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return 0;

    final autoFiles = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = _basename(entity.path).toLowerCase();
        if (name.startsWith('auto_backup_') && name.endsWith('.sqlite')) {
          autoFiles.add(entity);
        }
      }
    }

    // Sort newest first by filename (YYYY-MM-DD lexical order) then modified time
    autoFiles.sort((a, b) => _basename(b.path).compareTo(_basename(a.path)));

    int deleted = 0;
    if (autoFiles.length > keepCount) {
      for (final file in autoFiles.sublist(keepCount)) {
        try {
          await file.delete();
          deleted++;
        } catch (_) {}
      }
    }
    return deleted;
  }

  /// Lists `.sqlite` / `.db` backup files inside the configured backup folder (newest first).
  Future<List<BackupFileInfo>> listBackups({String? directoryPath}) async {
    final dirPath = directoryPath ?? (await loadConfig()).directoryPath;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];

    final files = <BackupFileInfo>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = _basename(entity.path);
        final lower = name.toLowerCase();
        if (lower.endsWith('.sqlite') || lower.endsWith('.db')) {
          try {
            final stat = await entity.stat();
            files.add(BackupFileInfo(
              path: entity.path,
              name: name,
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
            ));
          } catch (_) {}
        }
      }
    }
    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  /// Validates that [filePath] is a healthy SQLite file belonging to this ERP system.
  /// Returns `null` if valid, or a clear Arabic error message if invalid.
  Future<String?> validateBackupFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return 'ملف النسخة الاحتياطية غير موجود';
    }
    if (await file.length() < 100) {
      return 'الملف المحدد فارغ أو غير صالح كقاعدة بيانات';
    }

    sqlite.Database? candidate;
    try {
      candidate = sqlite.sqlite3.open(
        file.path,
        mode: sqlite.OpenMode.readOnly,
      );

      final integrity = candidate.select('PRAGMA integrity_check;');
      final integrityOk = integrity.isNotEmpty &&
          integrity.first.values.first?.toString().toLowerCase() == 'ok';
      if (!integrityOk) {
        return 'ملف النسخة الاحتياطية تالف (فشل فحص سلامة قاعدة البيانات)';
      }

      final tablesResult = candidate.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users', 'products', 'sales')",
      );
      if (tablesResult.length < 3) {
        return 'هذا الملف ليس نسخة احتياطية صالحة لنظام المبيعات (جداول أساسية مفقودة)';
      }
      return null;
    } catch (e) {
      return 'تعذر قراءة الملف كقاعدة بيانات SQLite صالحة';
    } finally {
      try {
        candidate?.dispose();
      } catch (_) {}
    }
  }

  /// Pending-restore staging suffix placed next to the live DB file.
  static const String pendingRestoreSuffix = '.pending_restore';

  /// Applies a staged `.pending_restore` file onto [liveFile] BEFORE SQLite
  /// opens the database. Safe on Windows because no SQLite handle is open yet.
  /// Returns `true` if a pending restore was applied.
  static Future<bool> applyPendingRestoreIfPresent(File liveFile) async {
    final pendingFile = File('${liveFile.path}$pendingRestoreSuffix');
    if (!pendingFile.existsSync()) return false;

    if (!liveFile.parent.existsSync()) {
      await liveFile.parent.create(recursive: true);
    }

    if (Platform.isWindows && liveFile.existsSync()) {
      try {
        await Process.run('attrib', ['-r', liveFile.path]);
      } catch (_) {}
    }

    // Remove WAL / SHM sidecars so stale journals are never replayed
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${liveFile.path}$suffix');
      if (sidecar.existsSync()) {
        await sidecar.delete();
      }
    }

    // Delete existing live file first (Windows File.copy / File.rename fails with
    // PathExistsException errno=183 if target exists or is read-only)
    if (liveFile.existsSync()) {
      await liveFile.delete();
    }

    try {
      await pendingFile.rename(liveFile.path);
    } catch (_) {
      await pendingFile.copy(liveFile.path);
      if (pendingFile.existsSync()) {
        await pendingFile.delete();
      }
    }
    return true;
  }

  /// Restores the live database from [sourceBackupPath]:
  /// 1. Validates backup integrity & schema.
  /// 2. Creates an automatic pre-restore safety snapshot of the current database.
  /// 3. Stages the verified backup as `clothes_erp.sqlite.pending_restore` so
  ///    even if Windows holds a background isolate lock on `clothes_erp.sqlite`
  ///    until process exit, startup applies the swap atomically before SQLite opens.
  /// 4. Closes the active database connection and attempts immediate replacement;
  ///    if Windows still holds a lock, the staged file completes the restore on restart.
  ///
  /// The app MUST be restarted after restore succeeds.
  Future<RestoreResult> restoreFromBackup({
    required String sourceBackupPath,
    String userId = 'admin',
  }) async {
    final validationError = await validateBackupFile(sourceBackupPath);
    if (validationError != null) {
      throw Exception(validationError);
    }

    final liveFile = await resolveLiveDbFile();
    final sourceFile = File(sourceBackupPath);
    if (sourceFile.absolute.path.toLowerCase() ==
        liveFile.absolute.path.toLowerCase()) {
      throw Exception('لا يمكن استعادة ملف قاعدة البيانات النشط على نفسه');
    }

    // Step 1: Take automatic pre-restore safety backup
    final config = await loadConfig();
    final safetyDir = Directory(config.directoryPath);
    if (!safetyDir.existsSync()) {
      await safetyDir.create(recursive: true);
    }
    final safetyPath =
        '${safetyDir.path}${Platform.pathSeparator}pre_restore_safety_${_formatTimestamp(DateTime.now())}.sqlite';
    final safety = await createBackup(
      targetFilePath: safetyPath,
      userId: userId,
      updateMetadata: false,
    );

    // Step 2: Stage verified backup next to live DB (never locked by SQLite)
    if (!liveFile.parent.existsSync()) {
      await liveFile.parent.create(recursive: true);
    }
    final pendingFile = File('${liveFile.path}$pendingRestoreSuffix');
    if (pendingFile.existsSync()) {
      await pendingFile.delete();
    }
    await sourceFile.copy(pendingFile.path);

    // Step 3: Close live DB connection & try immediate swap
    try {
      await _db.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await applyPendingRestoreIfPresent(liveFile);
    } catch (e) {
      // On Windows, Drift's background isolate (shareAcrossIsolates: true) may
      // still hold a file handle until process exit. That's completely safe:
      // `pendingFile` is staged and AppDatabase applies it on next launch
      // BEFORE SQLite opens the file.
      Logging.info('💾 [Restore] Staged for atomic apply on restart: $e');
    }

    return RestoreResult(
      restoredFromPath: sourceFile.path,
      safetyBackupPath: safety.filePath,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} كيلوبايت';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} ميجابايت';
  }

  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatTimestamp(DateTime dt) {
    final date = _formatDateOnly(dt);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '${date}_$hh-$mm-$ss';
  }

  static String _basename(String fullPath) {
    final normalized = fullPath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }
}

