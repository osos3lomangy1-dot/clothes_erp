import 'dart:io';
import 'tools/upgrade_verification_tools.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('harness_test_');
    dbFile = File('${tempDir.path}/test_db.sqlite');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('reports sqlite_version accurately', () async {
    final executor = NativeDatabase(dbFile);
    await executor.ensureOpen(_TestUser());
    await executor.runCustom('CREATE TABLE dummy (id INTEGER PRIMARY KEY);');
    await executor.close();

    final version = await UpgradeVerificationTools.getSqliteVersion(dbFile);
    expect(version, isNotEmpty);
    expect(version, isNot('unknown'));
    // ignore: avoid_print
    print('SQLite runtime version in test environment: $version');
  });

  test('computes canonical hash with dynamic column discovery, distinguishing empty string vs null', () async {
    final executor = NativeDatabase(dbFile);
    await executor.ensureOpen(_TestUser());
    await executor.runCustom('''
      CREATE TABLE test_table (
        id INTEGER PRIMARY KEY,
        name TEXT,
        score REAL,
        data BLOB,
        updated_at TEXT
      );
    ''');

    // Row 1: name is empty string ''
    await executor.runInsert(
      'INSERT INTO test_table (id, name, score, data, updated_at) VALUES (?, ?, ?, ?, ?);',
      [1, '', 95.5, Uint8List.fromList([1, 2, 3]), '2026-11-19 12:00:00'],
    );
    await executor.close();

    // Canonical hash using dynamic column discovery (no manual list)
    final hashEmptyString = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'test_table',
      excludeVolatileColumns: true,
    );

    // Update row 1 to name = null
    final executor2 = NativeDatabase(dbFile);
    await executor2.ensureOpen(_TestUser());
    await executor2.runUpdate('UPDATE test_table SET name = NULL WHERE id = 1;', []);
    await executor2.close();

    final hashNull = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'test_table',
      excludeVolatileColumns: true,
    );

    // Hashes MUST differ because NULL != ''
    expect(hashEmptyString, isNot(equals(hashNull)));
  });

  test('excludeVolatileColumns differentiates restoration comparison from forward migration comparison', () async {
    final executor = NativeDatabase(dbFile);
    await executor.ensureOpen(_TestUser());
    await executor.runCustom('''
      CREATE TABLE test_table (
        id INTEGER PRIMARY KEY,
        val TEXT,
        updated_at TEXT
      );
    ''');
    await executor.runInsert(
      'INSERT INTO test_table (id, val, updated_at) VALUES (?, ?, ?);',
      [1, 'hello', '2026-11-19 10:00:00'],
    );
    await executor.close();

    // 1. In forward migration: excludeVolatileColumns = true ignores updated_at
    final forwardHash1 = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'test_table',
      excludeVolatileColumns: true,
    );

    // Modify updated_at
    final executor2 = NativeDatabase(dbFile);
    await executor2.ensureOpen(_TestUser());
    await executor2.runUpdate(
      'UPDATE test_table SET updated_at = ? WHERE id = 1;',
      ['2026-11-19 18:30:00'],
    );
    await executor2.close();

    final forwardHash2 = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'test_table',
      excludeVolatileColumns: true,
    );
    expect(forwardHash1, equals(forwardHash2));

    // 2. In restoration verification: excludeVolatileColumns = false (STRICT)
    // Changing updated_at MUST produce a different hash because restored state must match 100%
    final strictHashAfterUpdate = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'test_table',
      excludeVolatileColumns: false,
    );

    // Revert updated_at back to original
    final executor3 = NativeDatabase(dbFile);
    await executor3.ensureOpen(_TestUser());
    await executor3.runUpdate(
      'UPDATE test_table SET updated_at = ? WHERE id = 1;',
      ['2026-11-19 10:00:00'],
    );
    await executor3.close();

    final strictHashOriginal = await UpgradeVerificationTools.computeTableCanonicalHash(
      dbFile: dbFile,
      tableName: 'test_table',
      excludeVolatileColumns: false,
    );
    expect(strictHashAfterUpdate, isNot(equals(strictHashOriginal)));
  });

  test('evaluates cycle outcome according to strict acceptance criteria', () {
    // 1. Success on upgrade: target reached and integrity ok
    expect(
      UpgradeVerificationTools.evaluateCycleOutcome(
        initialVersion: 11,
        targetVersion: 12,
        finalVersion: 12,
        integrityOk: true,
        initialHash: 'hashA',
        finalHash: 'hashB',
      ),
      isTrue,
    );

    // 2. Success on rollback: rolled back to initial version, integrity ok, hash matches initial
    expect(
      UpgradeVerificationTools.evaluateCycleOutcome(
        initialVersion: 11,
        targetVersion: 12,
        finalVersion: 11,
        integrityOk: true,
        initialHash: 'hashA',
        finalHash: 'hashA',
      ),
      isTrue,
    );

    // 3. Failure: rolled back to initial version but hash differs
    expect(
      UpgradeVerificationTools.evaluateCycleOutcome(
        initialVersion: 11,
        targetVersion: 12,
        finalVersion: 11,
        integrityOk: true,
        initialHash: 'hashA',
        finalHash: 'differentHash',
      ),
      isFalse,
    );

    // 4. Failure: integrity check failed
    expect(
      UpgradeVerificationTools.evaluateCycleOutcome(
        initialVersion: 11,
        targetVersion: 12,
        finalVersion: 12,
        integrityOk: false,
        initialHash: 'hashA',
        finalHash: 'hashB',
      ),
      isFalse,
    );

    // 5. Failure: intermediate unmanaged version
    expect(
      UpgradeVerificationTools.evaluateCycleOutcome(
        initialVersion: 6,
        targetVersion: 11,
        finalVersion: 8,
        integrityOk: true,
        initialHash: 'hashA',
        finalHash: 'hashIntermediate',
      ),
      isFalse,
    );
  });
}
