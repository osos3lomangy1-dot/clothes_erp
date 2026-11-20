import 'dart:io';
import 'package:clothes_erp/core/database/migration_marker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late MigrationMarkerService markerService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('marker_test_تجربة_');
    markerService = MigrationMarkerService(tempDir);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('writes marker atomically via .tmp and flush, then reads back accurately', () async {
    expect(markerService.exists(), isFalse);

    final initialMarker = MigrationMarker(
      formatVersion: 1,
      appVersion: '1.2.3',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/pre_mig_v11.db',
      backupState: BackupState.pending,
      restoreState: RestoreState.none,
      attemptCount: 1,
      timestamp: DateTime(2026, 11, 19, 14, 0),
    );

    await markerService.writeMarker(initialMarker);

    expect(markerService.exists(), isTrue);

    final read = await markerService.readMarker();
    expect(read, isNotNull);
    expect(read!.formatVersion, 1);
    expect(read.appVersion, '1.2.3');
    expect(read.versionFrom, 11);
    expect(read.versionTo, 12);
    expect(read.backupPath, '${tempDir.path}/pre_mig_v11.db');
    expect(read.backupState, BackupState.pending);
    expect(read.restoreState, RestoreState.none);
    expect(read.attemptCount, 1);
  });

  test('proves atomic rename directly replaces an existing marker file on Windows without prior deletion', () async {
    final markerV1 = MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/backup_v1.db',
      backupState: BackupState.pending,
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(markerV1);

    final targetFile = File('${tempDir.path}/${MigrationMarkerService.markerFileName}');
    expect(targetFile.existsSync(), isTrue);
    final initialContent = await targetFile.readAsString();
    expect(initialContent.contains('backup_v1.db'), isTrue);

    // Write markerV2 directly over the existing file
    final markerV2 = markerV1.copyWith(
      backupState: BackupState.verified,
      backupPath: '${tempDir.path}/backup_v2.db',
    );
    await markerService.writeMarker(markerV2);

    expect(targetFile.existsSync(), isTrue);
    final updatedContent = await targetFile.readAsString();
    expect(updatedContent.contains('backup_v2.db'), isTrue);
    expect(updatedContent.contains('"backup_state":"verified"'), isTrue);

    final read = await markerService.readMarker();
    expect(read!.backupState, BackupState.verified);
    expect(read.backupPath, '${tempDir.path}/backup_v2.db');
  });

  test('updates backupState to verified atomically', () async {
    final marker = MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/backup.db',
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(marker);

    await markerService.updateBackupState(BackupState.verified);

    final read = await markerService.readMarker();
    expect(read!.backupState, BackupState.verified);
  });

  test('updates restoreState to restoreInProgress atomically', () async {
    final marker = MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/backup.db',
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(marker);

    await markerService.updateRestoreState(RestoreState.restoreInProgress);

    final read = await markerService.readMarker();
    expect(read!.restoreState, RestoreState.restoreInProgress);
  });

  test('increments attempt count safely', () async {
    final marker = MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/backup.db',
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(marker);

    await markerService.incrementAttemptCount();
    var read = await markerService.readMarker();
    expect(read!.attemptCount, 2);

    await markerService.incrementAttemptCount();
    read = await markerService.readMarker();
    expect(read!.attemptCount, 3);
  });

  test('detects corrupted or empty marker file and throws CorruptedMarkerException', () async {
    // 1. Empty file
    final markerFile = File('${tempDir.path}/${MigrationMarkerService.markerFileName}');
    await markerFile.writeAsString('   ');
    expect(() => markerService.readMarker(), throwsA(isA<CorruptedMarkerException>()));

    // 2. Malformed JSON
    await markerFile.writeAsString('{"version_from": 11, TRUNCATED_JSON...');
    expect(() => markerService.readMarker(), throwsA(isA<CorruptedMarkerException>()));

    // 3. Missing app_version
    await markerFile.writeAsString('{"version_from": 11, "version_to": 12, "backup_path": "b.db", "backup_state": "pending", "restore_state": "none", "timestamp": 1700000000000}');
    expect(() => markerService.readMarker(), throwsA(isA<CorruptedMarkerException>()));

    // 4. Missing timestamp
    await markerFile.writeAsString('{"version_from": 11, "version_to": 12, "app_version": "1.0.0", "backup_path": "b.db", "backup_state": "pending", "restore_state": "none"}');
    expect(() => markerService.readMarker(), throwsA(isA<CorruptedMarkerException>()));
  });

  test('rejects unknown enum values strictly with CorruptedMarkerException', () async {
    final markerFile = File('${tempDir.path}/${MigrationMarkerService.markerFileName}');

    // Unknown backup_state
    await markerFile.writeAsString('''
      {
        "format_version": 1,
        "app_version": "1.0.0",
        "version_from": 11,
        "version_to": 12,
        "backup_path": "b.db",
        "backup_state": "UNKNOWN_FUTURE_STATE",
        "restore_state": "none",
        "attempt_count": 1,
        "timestamp": 1700000000000
      }
    ''');
    expect(() => markerService.readMarker(), throwsA(isA<CorruptedMarkerException>()));

    // Unknown restore_state
    await markerFile.writeAsString('''
      {
        "format_version": 1,
        "app_version": "1.0.0",
        "version_from": 11,
        "version_to": 12,
        "backup_path": "b.db",
        "backup_state": "pending",
        "restore_state": "SOME_UNKNOWN_STATE",
        "attempt_count": 1,
        "timestamp": 1700000000000
      }
    ''');
    expect(() => markerService.readMarker(), throwsA(isA<CorruptedMarkerException>()));
  });

  test('rejects higher format_version strictly with UnsupportedMarkerVersionException', () async {
    final markerFile = File('${tempDir.path}/${MigrationMarkerService.markerFileName}');
    await markerFile.writeAsString('''
      {
        "format_version": 99,
        "app_version": "2.0.0",
        "version_from": 11,
        "version_to": 12,
        "backup_path": "b.db",
        "backup_state": "pending",
        "restore_state": "none",
        "attempt_count": 1,
        "timestamp": 1700000000000
      }
    ''');
    expect(() => markerService.readMarker(), throwsA(isA<UnsupportedMarkerVersionException>()));
  });

  test('clears marker file safely and handles repeated calls without error', () async {
    final marker = MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/backup.db',
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(marker);
    expect(markerService.exists(), isTrue);

    await markerService.clearMarker();
    expect(markerService.exists(), isFalse);

    // Repeated call is safe (idempotent)
    await markerService.clearMarker();
    expect(markerService.exists(), isFalse);
  });

  test('cleans up orphan .tmp file on readMarker() when main marker exists', () async {
    final marker = MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: '${tempDir.path}/backup.db',
      timestamp: DateTime.now(),
    );
    await markerService.writeMarker(marker);

    // Simulate an orphan .tmp left behind
    final tmpFile = File('${tempDir.path}/${MigrationMarkerService.markerFileName}.tmp');
    await tmpFile.writeAsString('orphan partial content');
    expect(tmpFile.existsSync(), isTrue);

    // readMarker() cleans up orphan .tmp and returns valid main marker
    final read = await markerService.readMarker();
    expect(read, isNotNull);
    expect(read!.versionFrom, 11);
    expect(tmpFile.existsSync(), isFalse);
  });

  test('cleans up orphan .tmp file on readMarker() when main marker does NOT exist', () async {
    // Simulate power cut during initial marker creation before rename
    final tmpFile = File('${tempDir.path}/${MigrationMarkerService.markerFileName}.tmp');
    await tmpFile.writeAsString('unfinalized marker data');
    expect(tmpFile.existsSync(), isTrue);

    final read = await markerService.readMarker();
    expect(read, isNull);
    expect(tmpFile.existsSync(), isFalse);
  });
}
