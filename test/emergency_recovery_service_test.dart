import 'dart:convert';
import 'dart:io';
import 'package:clothes_erp/core/database/emergency_recovery_service.dart';
import 'package:clothes_erp/core/database/migration_marker_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}

void main() {
  late Directory tempDir;
  late File activeDbFile;
  late File backupFile;
  late MigrationMarkerService markerService;
  late EmergencyRecoveryService recoveryService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('emergency_test_');
    activeDbFile = File('${tempDir.path}/clothes_erp.sqlite');
    backupFile = File('${tempDir.path}/pre_upgrade_v11.db');
    markerService = MigrationMarkerService(tempDir);
    recoveryService = EmergencyRecoveryService(
      activeDbFile: activeDbFile,
      markerService: markerService,
      appVersion: '1.0.0',
    );

    // Setup a valid backup file with sample customer
    final executor = NativeDatabase(backupFile);
    await executor.ensureOpen(_User());
    await executor.runCustom('''
      PRAGMA user_version = 11;
      CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);
      INSERT INTO customers VALUES (1, 'عميل النسخة الاحتياطية');
    ''');
    await executor.close();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('detects emergency when verified migration marker is present', () async {
    await markerService.writeMarker(MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: backupFile.path,
      backupState: BackupState.verified,
      timestamp: DateTime.now(),
    ));

    final status = await recoveryService.checkRecoveryNeeded();
    expect(status.isEmergency, isTrue);
    expect(status.reason, EmergencyReason.incompleteMigration);
    expect(status.backupFile, isNotNull);
    expect(status.backupFile!.path, backupFile.path);
  });

  test('detects emergency when active database file is corrupted', () async {
    // Write corrupt partial header
    await activeDbFile.writeAsString('NOT A VALID SQLITE HEADER FILE');

    final status = await recoveryService.checkRecoveryNeeded();
    expect(status.isEmergency, isTrue);
    expect(status.reason, EmergencyReason.databaseCorrupted);
  });

  test('successfully performs manual restoration from verified backup and clears marker', () async {
    // Active DB is corrupt
    await activeDbFile.writeAsString('CORRUPT GARBAGE');

    await markerService.writeMarker(MigrationMarker(
      appVersion: '1.0.0',
      versionFrom: 11,
      versionTo: 12,
      backupPath: backupFile.path,
      backupState: BackupState.verified,
      timestamp: DateTime.now(),
    ));

    final success = await recoveryService.restoreFromVerifiedBackup(backupFile);
    expect(success, isTrue);

    // Marker is cleared
    expect(markerService.exists(), isFalse);

    // Restored DB has quick_check ok
    final executor = NativeDatabase(activeDbFile);
    await executor.ensureOpen(_User());
    final check = await executor.runSelect('PRAGMA quick_check;', []);
    expect(check.first.values.first, 'ok');

    // Data matches backup
    final rows = await executor.runSelect('SELECT name FROM customers WHERE id = 1;', []);
    expect(rows.first['name'], 'عميل النسخة الاحتياطية');
    await executor.close();
  });

  test('exports diagnostic report without any customer data', () async {
    await activeDbFile.writeAsString('CORRUPT FILE');
    final status = await recoveryService.checkRecoveryNeeded();

    final jsonReport = await recoveryService.exportDiagnosticReport(status);
    final decoded = jsonDecode(jsonReport) as Map<String, dynamic>;

    expect(decoded['report_type'], 'Bay3ah_ERP_Emergency_Diagnostic');
    expect(decoded['app_version'], '1.0.0');
    expect(decoded['emergency_reason'], 'databaseCorrupted');
    expect(decoded.containsKey('customers'), isFalse);
    expect(decoded.containsKey('sales'), isFalse);
    expect(decoded.containsKey('phone'), isFalse);
  });
}

