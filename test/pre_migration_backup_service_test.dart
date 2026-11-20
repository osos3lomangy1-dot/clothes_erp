import 'dart:io';
import 'package:clothes_erp/core/database/migration_marker_service.dart';
import 'package:clothes_erp/core/database/pre_migration_backup_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'tools/upgrade_verification_tools.dart';

class _User extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}

void main() {
  late Directory tempDir;
  late Directory backupDir;
  late File sourceDbFile;
  late MigrationMarkerService markerService;
  late PreMigrationBackupService backupService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pre_mig_backup_test_');
    backupDir = Directory('${tempDir.path}/backups');
    sourceDbFile = File('${tempDir.path}/source.sqlite');
    markerService = MigrationMarkerService(tempDir);
    backupService = PreMigrationBackupService(
      backupDirectory: backupDir,
      markerService: markerService,
      maxRetainedBackups: 3,
    );

    // Setup source DB with sample data
    final executor = NativeDatabase(sourceDbFile);
    await executor.ensureOpen(_User());
    await executor.runCustom('''
      PRAGMA user_version = 11;
      CREATE TABLE test_data (id INTEGER PRIMARY KEY, name TEXT, updated_at TEXT);
      INSERT INTO test_data VALUES (1, 'منتج تجريبي', '2026-11-19 12:00:00');
    ''');
    await executor.close();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('successfully takes pre-migration backup, verifies hash identity, and promotes marker to verified', () async {
    final preHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: sourceDbFile,
      tableName: 'test_data',
      excludeVolatileColumns: false, // Strict comparison
    );

    final backupFile = await backupService.createPreMigrationBackup(
      sourceDbFile: sourceDbFile,
      currentVersion: 11,
      targetVersion: 12,
      appVersion: '1.0.0',
      verificationTableName: 'test_data',
    );

    expect(backupFile.existsSync(), isTrue);

    // Verify marker is verified and holds sourceHash
    final marker = await markerService.readMarker();
    expect(marker, isNotNull);
    expect(marker!.backupState, BackupState.verified);
    expect(marker.sourceHash, equals(preHash));
    expect(marker.backupPath, equals(backupFile.path));

    // Verify backup DB quick_check and hash
    final backupExecutor = NativeDatabase(backupFile);
    await backupExecutor.ensureOpen(_User());
    final check = await backupExecutor.runSelect('PRAGMA quick_check;', []);
    expect(check.first.values.first, 'ok');
    await backupExecutor.close();

    final backupHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: backupFile,
      tableName: 'test_data',
      excludeVolatileColumns: false,
    );
    expect(backupHash, equals(preHash));
  });

  test('promotes existing valid final backup from pending to verified without re-copying', () async {
    // 1. Manually create a valid backup file
    final backupFile = File('${backupDir.path}/pre_upgrade_v11_12345.db');
    if (!backupDir.existsSync()) backupDir.createSync(recursive: true);

    final sourceHash = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: sourceDbFile,
      tableName: 'test_data',
      excludeVolatileColumns: false,
    );

    sourceDbFile.copySync(backupFile.path);

    // 2. Set marker in pending state referencing this backup
    await markerService.writeMarker(MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: backupFile.path,
      sourceHash: sourceHash,
      backupState: BackupState.pending,
      timestamp: DateTime.now(),
    ));

    // 3. Run createPreMigrationBackup -> should detect valid file and promote to verified directly
    final verifiedFile = await backupService.createPreMigrationBackup(
      sourceDbFile: sourceDbFile,
      currentVersion: 11,
      targetVersion: 12,
      appVersion: '1.0.0',
      verificationTableName: 'test_data',
    );

    expect(verifiedFile.path, equals(backupFile.path));
    final updatedMarker = await markerService.readMarker();
    expect(updatedMarker!.backupState, BackupState.verified);
  });

  test('prunes old backups according to retention policy, never deleting the active one', () async {
    if (!backupDir.existsSync()) backupDir.createSync(recursive: true);

    final f1 = File('${backupDir.path}/pre_upgrade_v11_100.db')..writeAsStringSync('b1');
    await Future.delayed(const Duration(milliseconds: 20));
    File('${backupDir.path}/pre_upgrade_v11_200.db').writeAsStringSync('b2');
    await Future.delayed(const Duration(milliseconds: 20));
    File('${backupDir.path}/pre_upgrade_v11_300.db').writeAsStringSync('b3');
    await Future.delayed(const Duration(milliseconds: 20));
    final f4 = File('${backupDir.path}/pre_upgrade_v11_400.db')..writeAsStringSync('b4');

    expect(backupDir.listSync().whereType<File>().length, 4);

    // Prune keeping 3, preserving f4 as active
    await backupService.pruneOldBackups(f4);

    final remaining = backupDir.listSync().whereType<File>().toList();
    expect(remaining.length, 3);
    // Oldest f1 must be pruned
    expect(f1.existsSync(), isFalse);
    expect(f4.existsSync(), isTrue);
  });
}
