import 'dart:convert';
import 'dart:io';

// INVARIANT: The marker file is written and flushed BEFORE any destructive or irreversible operation it describes.
// If the marker file is absent, no migration or recovery is assumed to be in progress.
// If the marker file is present with backup_state == 'verified', recovery is guaranteed to be safe from the referenced backup.

enum BackupState {
  pending,
  verified,
}

enum RestoreState {
  none,
  restoreInProgress,
}

class UnsupportedMarkerVersionException implements Exception {
  final int foundVersion;
  final int supportedVersion;

  const UnsupportedMarkerVersionException(this.foundVersion, this.supportedVersion);

  @override
  String toString() =>
      'UnsupportedMarkerVersionException: Found format_version $foundVersion, but maximum supported is $supportedVersion.';
}

class CorruptedMarkerException implements Exception {
  final String message;
  final Object? cause;
  const CorruptedMarkerException(this.message, [this.cause]);

  @override
  String toString() => 'CorruptedMarkerException: $message ($cause)';
}

class MarkerRenameFailedException implements Exception {
  final String message;
  final Object? cause;
  const MarkerRenameFailedException(this.message, [this.cause]);

  @override
  String toString() => 'MarkerRenameFailedException: $message ($cause)';
}

class MarkerDeletionFailedException implements Exception {
  final String message;
  final Object? cause;
  const MarkerDeletionFailedException(this.message, [this.cause]);

  @override
  String toString() => 'MarkerDeletionFailedException: $message ($cause)';
}

class MigrationMarker {
  static const int currentFormatVersion = 1;

  final int formatVersion;
  final String appVersion;
  final int versionFrom;
  final int versionTo;
  final String backupPath;
  final String? sourceHash;
  final BackupState backupState;
  final RestoreState restoreState;
  final int attemptCount;
  final DateTime timestamp;

  const MigrationMarker({
    this.formatVersion = currentFormatVersion,
    required this.appVersion,
    required this.versionFrom,
    required this.versionTo,
    required this.backupPath,
    this.sourceHash,
    this.backupState = BackupState.pending,
    this.restoreState = RestoreState.none,
    this.attemptCount = 1,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'format_version': formatVersion,
        'app_version': appVersion,
        'version_from': versionFrom,
        'version_to': versionTo,
        'backup_path': backupPath,
        if (sourceHash != null) 'source_hash': sourceHash,
        'backup_state': backupState.name,
        'restore_state': restoreState.name,
        'attempt_count': attemptCount,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory MigrationMarker.fromJson(Map<String, dynamic> json) {
    final formatVersion = json['format_version'] as int? ?? 1;
    if (formatVersion > currentFormatVersion) {
      throw UnsupportedMarkerVersionException(formatVersion, currentFormatVersion);
    }

    final appVersion = json['app_version'] as String?;
    if (appVersion == null || appVersion.trim().isEmpty) {
      throw const CorruptedMarkerException('Missing or empty app_version in marker');
    }

    final versionFrom = json['version_from'] as int?;
    final versionTo = json['version_to'] as int?;
    final backupPath = json['backup_path'] as String?;
    final sourceHash = json['source_hash'] as String?;

    if (versionFrom == null || versionTo == null || backupPath == null) {
      throw const CorruptedMarkerException('Missing required version or backup path fields');
    }

    final backupStateStr = json['backup_state'] as String?;
    final BackupState backupState;
    if (backupStateStr == BackupState.verified.name) {
      backupState = BackupState.verified;
    } else if (backupStateStr == BackupState.pending.name) {
      backupState = BackupState.pending;
    } else {
      throw CorruptedMarkerException('Unknown backup_state value: $backupStateStr');
    }

    final restoreStateStr = json['restore_state'] as String?;
    final RestoreState restoreState;
    if (restoreStateStr == RestoreState.none.name) {
      restoreState = RestoreState.none;
    } else if (restoreStateStr == RestoreState.restoreInProgress.name) {
      restoreState = RestoreState.restoreInProgress;
    } else {
      throw CorruptedMarkerException('Unknown restore_state value: $restoreStateStr');
    }

    final timestampMs = json['timestamp'] as int?;
    if (timestampMs == null) {
      throw const CorruptedMarkerException('Missing or invalid timestamp in marker');
    }

    return MigrationMarker(
      formatVersion: formatVersion,
      appVersion: appVersion,
      versionFrom: versionFrom,
      versionTo: versionTo,
      backupPath: backupPath,
      sourceHash: sourceHash,
      backupState: backupState,
      restoreState: restoreState,
      attemptCount: (json['attempt_count'] as int?) ?? 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }

  MigrationMarker copyWith({
    int? formatVersion,
    String? appVersion,
    int? versionFrom,
    int? versionTo,
    String? backupPath,
    String? sourceHash,
    BackupState? backupState,
    RestoreState? restoreState,
    int? attemptCount,
    DateTime? timestamp,
  }) {
    return MigrationMarker(
      formatVersion: formatVersion ?? this.formatVersion,
      appVersion: appVersion ?? this.appVersion,
      versionFrom: versionFrom ?? this.versionFrom,
      versionTo: versionTo ?? this.versionTo,
      backupPath: backupPath ?? this.backupPath,
      sourceHash: sourceHash ?? this.sourceHash,
      backupState: backupState ?? this.backupState,
      restoreState: restoreState ?? this.restoreState,
      attemptCount: attemptCount ?? this.attemptCount,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class MigrationMarkerService {
  final Directory directory;
  static const String markerFileName = 'migration.inprogress';

  MigrationMarkerService(this.directory);

  File get _markerFile => File('${directory.path}/$markerFileName');
  File get _tempMarkerFile => File('${directory.path}/$markerFileName.tmp');

  bool exists() => _markerFile.existsSync();

  /// Writes marker atomically:
  /// 1. Writes payload to `<marker>.tmp` with explicit `flush()`.
  /// 2. Performs atomic rename directly over target file without deleting target beforehand.
  /// 3. If rename fails after 5 retries, throws [MarkerRenameFailedException] without fallback.
  Future<void> writeMarker(MigrationMarker marker) async {
    final jsonStr = jsonEncode(marker.toJson());

    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final raf = await _tempMarkerFile.open(mode: FileMode.write);
    await raf.writeString(jsonStr);
    await raf.flush();
    await raf.close();

    await _atomicRenameWithRetry(_tempMarkerFile, _markerFile);
  }

  /// Reads and parses the active marker.
  ///
  /// Side Effect & Invariant Rationale:
  /// Cleans up any leftover `<marker>.tmp` file.
  /// This cleanup is safe and sound because of our core INVARIANT:
  /// "The marker file is written and flushed BEFORE any irreversible or destructive
  /// operation it describes."
  /// Therefore:
  /// 1) If `.tmp` exists alongside a valid main marker, `.tmp` is merely stale artifact from
  ///    a completed write.
  /// 2) If `.tmp` exists alone without a main marker, the write was interrupted before the
  ///    migration or backup ever began. No schema or data changes occurred, so removing
  ///    the orphan `.tmp` safely resets the state.
  Future<MigrationMarker?> readMarker() async {
    if (_tempMarkerFile.existsSync()) {
      try {
        await _deleteWithRetry(_tempMarkerFile);
      } catch (_) {}
    }

    if (!_markerFile.existsSync()) return null;

    try {
      final content = await _markerFile.readAsString();
      if (content.trim().isEmpty) {
        throw const CorruptedMarkerException('Marker file is empty');
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const CorruptedMarkerException('Marker content is not a valid JSON map');
      }
      return MigrationMarker.fromJson(decoded);
    } catch (e) {
      if (e is CorruptedMarkerException || e is UnsupportedMarkerVersionException) {
        rethrow;
      }
      throw CorruptedMarkerException('Failed to read or parse marker file', e);
    }
  }

  Future<void> updateBackupState(BackupState state) async {
    final current = await readMarker();
    if (current == null) {
      throw StateError('Cannot update backupState: No active marker found.');
    }
    await writeMarker(current.copyWith(backupState: state));
  }

  Future<void> updateRestoreState(RestoreState state) async {
    final current = await readMarker();
    if (current == null) {
      throw StateError('Cannot update restoreState: No active marker found.');
    }
    await writeMarker(current.copyWith(restoreState: state));
  }

  Future<void> incrementAttemptCount() async {
    final current = await readMarker();
    if (current == null) return;
    await writeMarker(current.copyWith(attemptCount: current.attemptCount + 1));
  }

  /// Deletes the marker and any temp file.
  /// Throws [MarkerDeletionFailedException] if deletion cannot be completed.
  Future<void> clearMarker() async {
    await _deleteWithRetry(_markerFile);
    await _deleteWithRetry(_tempMarkerFile);
  }

  /// Direct atomic rename on Windows/POSIX.
  /// Does NOT delete the target file prior to rename, guaranteeing that at no instant
  /// does the target marker disappear when replacing an existing marker.
  static Future<void> _atomicRenameWithRetry(File source, File target) async {
    int attempts = 0;
    Object? lastError;
    while (attempts < 5) {
      try {
        await source.rename(target.path);
        return;
      } catch (e) {
        lastError = e;
        attempts++;
        if (attempts < 5) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    throw MarkerRenameFailedException(
      'Failed to rename ${source.path} to ${target.path} after 5 attempts',
      lastError,
    );
  }

  static Future<void> _deleteWithRetry(File file) async {
    if (!file.existsSync()) return;
    int attempts = 0;
    Object? lastError;
    while (attempts < 5) {
      try {
        await file.delete();
        return;
      } catch (e) {
        lastError = e;
        attempts++;
        if (attempts < 5) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    throw MarkerDeletionFailedException(
      'Failed to delete file ${file.path} after 5 attempts',
      lastError,
    );
  }
}
