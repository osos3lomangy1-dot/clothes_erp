import 'dart:io';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _FakeAuth implements AuthLocalDataSource {
  @override
  Future<void> cacheUser(UserModel user) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<UserModel?> getCachedUser() async => UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'admin@test.local',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakeBranch implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
}

void main() {
  late Directory tempRoot;
  late Directory backupDir;
  late File liveDbFile;
  late AppDatabase db;
  late FeatureGate featureGate;
  late LocalBackupService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('clothes_erp_backup_test_');
    backupDir = Directory('${tempRoot.path}${Platform.pathSeparator}backups');
    await backupDir.create(recursive: true);
    liveDbFile = File('${tempRoot.path}${Platform.pathSeparator}clothes_erp.sqlite');

    db = AppDatabase(NativeDatabase(liveDbFile));
    featureGate = FeatureGate(db, _FakeAuth(), TxWriter(db), _FakeBranch());
    service = LocalBackupService(
      db,
      featureGate,
      defaultBackupDirProvider: () async => backupDir,
      liveDbFileProvider: () async => liveDbFile,
    );

    // Ensure DB tables are initialized
    await db.select(db.appMeta).get();
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('1. createBackup produces valid standalone SQLite snapshot and updates metadata', () async {
    final now = DateTime.now();
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-1',
          branchId: 'branch-1',
          name: 'ملابس رجالي',
          createdAt: now,
          updatedAt: now,
        ));

    final result = await service.createBackup(userId: 'admin-1');
    expect(File(result.filePath).existsSync(), isTrue);
    expect(result.sizeBytes, greaterThan(0));

    // Validate the created backup
    final validationErr = await service.validateBackupFile(result.filePath);
    expect(validationErr, isNull);

    // Verify metadata updated
    final cfg = await service.loadConfig();
    expect(cfg.lastBackupAt, isNotNull);
    expect(cfg.lastBackupPath, result.filePath);

    // Verify backup actually contains the inserted category
    final checkDb = sqlite.sqlite3.open(result.filePath, mode: sqlite.OpenMode.readOnly);
    try {
      final rows = checkDb.select("SELECT name FROM categories WHERE id = 'cat-1'");
      expect(rows.length, 1);
      expect(rows.first['name'], 'ملابس رجالي');
    } finally {
      checkDb.dispose();
    }
  });

  test('2. validateBackupFile rejects missing, corrupt, and non-ERP SQLite files', () async {
    // Missing file
    expect(
      await service.validateBackupFile('${tempRoot.path}/does_not_exist.sqlite'),
      isNotNull,
    );

    // Plain text file disguised as .sqlite
    final junkFile = File('${tempRoot.path}/junk.sqlite');
    await junkFile.writeAsString('not a real sqlite database' * 10);
    expect(await service.validateBackupFile(junkFile.path), isNotNull);

    // Valid SQLite DB but missing ERP tables
    final otherDbFile = File('${tempRoot.path}/other.sqlite');
    final otherDb = sqlite.sqlite3.open(otherDbFile.path);
    otherDb.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT);');
    otherDb.execute("INSERT INTO notes (body) VALUES ('hello');");
    otherDb.dispose();
    expect(await service.validateBackupFile(otherDbFile.path), isNotNull);
  });

  test('3. runAutoBackupIfDue creates once per day and prunes older auto-backups beyond retention', () async {
    await service.setRetentionCount(3, userId: 'admin-1');

    // Seed 4 older auto backups + 1 manual backup (manual must NEVER be pruned)
    for (final day in ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04']) {
      await File('${backupDir.path}${Platform.pathSeparator}auto_backup_$day.sqlite')
          .writeAsString('dummy');
    }
    final manualFile = File('${backupDir.path}${Platform.pathSeparator}sales_erp_backup_manual.sqlite');
    await manualFile.writeAsString('manual');

    // First run on 2026-01-05 -> creates backup & prunes down to 3 auto backups
    final first = await service.runAutoBackupIfDue(now: DateTime(2026, 1, 5, 10, 0));
    expect(first, isNotNull);
    expect(File(first!.filePath).existsSync(), isTrue);

    // Second run same day -> skipped (returns null)
    final second = await service.runAutoBackupIfDue(now: DateTime(2026, 1, 5, 18, 0));
    expect(second, isNull);

    // Manual backup untouched, only 3 newest auto backups remain (03, 04, 05)
    expect(manualFile.existsSync(), isTrue);
    final remainingAuto = backupDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('auto_backup_'))
        .toList();
    expect(remainingAuto.length, 3);
    expect(remainingAuto.any((f) => f.path.endsWith('auto_backup_2026-01-05.sqlite')), isTrue);
    expect(remainingAuto.any((f) => f.path.endsWith('auto_backup_2026-01-01.sqlite')), isFalse);
  });

  test('4. restoreFromBackup saves pre-restore safety copy, clears WAL/SHM, and restores old state', () async {
    final now = DateTime.now();
    // 1. Insert original category & take backup
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-original',
          branchId: 'branch-1',
          name: 'قسم أصلي قبل التعديل',
          createdAt: now,
          updatedAt: now,
        ));
    final snapshot = await service.createBackup(
      targetFilePath: '${tempRoot.path}${Platform.pathSeparator}good_snapshot.sqlite',
      userId: 'admin-1',
    );

    // 2. Mutate live DB AFTER backup (add another category that shouldn't exist after restore)
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-after',
          branchId: 'branch-1',
          name: 'قسم مضاف بعد النسخة',
          createdAt: now,
          updatedAt: now,
        ));

    // Create dummy WAL/SHM files to verify cleanup
    final walFile = File('${liveDbFile.path}-wal');
    final shmFile = File('${liveDbFile.path}-shm');
    if (!walFile.existsSync()) await walFile.writeAsBytes([1, 2, 3]);
    if (!shmFile.existsSync()) await shmFile.writeAsBytes([1, 2, 3]);

    // 3. Restore from snapshot
    final restoreRes = await service.restoreFromBackup(
      sourceBackupPath: snapshot.filePath,
      userId: 'admin-1',
    );

    expect(File(restoreRes.safetyBackupPath).existsSync(), isTrue);
    expect(walFile.existsSync(), isFalse);
    expect(shmFile.existsSync(), isFalse);

    // 4. Open restored DB and verify original row exists while post-backup row is gone
    final restoredDb = sqlite.sqlite3.open(liveDbFile.path, mode: sqlite.OpenMode.readOnly);
    try {
      final orig = restoredDb.select("SELECT id FROM categories WHERE id = 'cat-original'");
      final after = restoredDb.select("SELECT id FROM categories WHERE id = 'cat-after'");
      expect(orig.length, 1);
      expect(after.isEmpty, isTrue);
    } finally {
      restoredDb.dispose();
    }

    // 5. Verify pre-restore safety backup preserved the post-backup row
    final safetyDb = sqlite.sqlite3.open(restoreRes.safetyBackupPath, mode: sqlite.OpenMode.readOnly);
    try {
      final afterInSafety = safetyDb.select("SELECT id FROM categories WHERE id = 'cat-after'");
      expect(afterInSafety.length, 1);
    } finally {
      safetyDb.dispose();
    }
  });

  test('5. applyPendingRestoreIfPresent atomically swaps staged restore onto existing live file', () async {
    final now = DateTime.now();
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-v1',
          branchId: 'branch-1',
          name: 'نسخة قديمة',
          createdAt: now,
          updatedAt: now,
        ));
    final v1Snapshot = await service.createBackup(
      targetFilePath: '${tempRoot.path}${Platform.pathSeparator}v1.sqlite',
      userId: 'admin-1',
    );
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-v2',
          branchId: 'branch-1',
          name: 'نسخة جديدة',
          createdAt: now,
          updatedAt: now,
        ));

    await db.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Stage .pending_restore alongside an already-existing live DB + WAL/SHM
    final pendingFile = File('${liveDbFile.path}${LocalBackupService.pendingRestoreSuffix}');
    await File(v1Snapshot.filePath).copy(pendingFile.path);
    final walFile = File('${liveDbFile.path}-wal');
    await walFile.writeAsBytes([9, 9, 9]);

    final applied = await LocalBackupService.applyPendingRestoreIfPresent(liveDbFile);
    expect(applied, isTrue);
    expect(pendingFile.existsSync(), isFalse);
    expect(walFile.existsSync(), isFalse);

    final checkDb = sqlite.sqlite3.open(liveDbFile.path, mode: sqlite.OpenMode.readOnly);
    try {
      expect(checkDb.select("SELECT id FROM categories WHERE id = 'cat-v1'").length, 1);
      expect(checkDb.select("SELECT id FROM categories WHERE id = 'cat-v2'").isEmpty, isTrue);
    } finally {
      checkDb.dispose();
    }
  });
}
