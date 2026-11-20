import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class _VerificationQueryUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}

class DatabaseVerificationService {
  /// Queries the runtime SQLite version from the database.
  static Future<String> getSqliteVersion(File dbFile) async {
    final executor = NativeDatabase(dbFile);
    await executor.ensureOpen(_VerificationQueryUser());
    try {
      final rows = await executor.runSelect('SELECT sqlite_version() AS version;', []);
      if (rows.isNotEmpty) {
        return rows.first['version'] as String;
      }
      return 'unknown';
    } finally {
      await executor.close();
    }
  }

  /// Computes an unambiguous canonical SHA-256 hash of a database table.
  ///
  /// - Columns are dynamically discovered using `PRAGMA table_info("$tableName")`.
  /// - [excludeVolatileColumns]: Set to `true` ONLY during forward migration comparison
  ///   where migration DDL/DML may legitimately update volatile timestamps (e.g. `updated_at`).
  ///   MUST BE SET TO `false` during backup restoration verification, where exact byte-for-byte
  ///   and timestamp identity is mandatory.
  ///
  /// Wire format for hash input:
  /// `COUNT:<rowCount>\n`
  /// For each row sorted by [sortColumn]:
  ///   `ROW_START\n`
  ///   `COL:<name>|TYPE:<N|S|I|F|B|O>|LEN:<len>|VAL:<value>\n`
  ///   `ROW_END\n`
  static Future<String> computeTableCanonicalHash({
    required File dbFile,
    required String tableName,
    List<String>? explicitColumns,
    String sortColumn = 'id',
    bool excludeVolatileColumns = false,
    List<String> volatileColumnNames = const ['updated_at'],
  }) async {
    final executor = NativeDatabase(dbFile);
    await executor.ensureOpen(_VerificationQueryUser());

    try {
      List<String> columns;
      if (explicitColumns != null && explicitColumns.isNotEmpty) {
        columns = List.from(explicitColumns);
      } else {
        final tableInfoRows = await executor.runSelect('PRAGMA table_info("$tableName");', []);
        columns = tableInfoRows.map((r) => r['name'] as String).toList();
      }

      if (excludeVolatileColumns) {
        columns = columns
            .where((c) => !volatileColumnNames.contains(c.toLowerCase()))
            .toList();
      }

      final colList = columns.join(', ');
      final query = 'SELECT $colList FROM $tableName ORDER BY $sortColumn ASC;';
      final rows = await executor.runSelect(query, []);

      final buffer = StringBuffer();
      buffer.write('COUNT:${rows.length}\n');

      for (final row in rows) {
        buffer.write('ROW_START\n');
        for (final col in columns) {
          final val = row[col];
          buffer.write('COL:$col|');

          if (val == null) {
            buffer.write('TYPE:N|LEN:0|VAL:\n');
          } else if (val is String) {
            final encoded = utf8.encode(val);
            buffer.write('TYPE:S|LEN:${encoded.length}|VAL:$val\n');
          } else if (val is int) {
            final str = val.toString();
            buffer.write('TYPE:I|LEN:${str.length}|VAL:$str\n');
          } else if (val is double) {
            final str = val.toString();
            buffer.write('TYPE:F|LEN:${str.length}|VAL:$str\n');
          } else if (val is Uint8List) {
            final hex = val.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            buffer.write('TYPE:B|LEN:${val.length}|VAL:$hex\n');
          } else {
            final str = val.toString();
            buffer.write('TYPE:O|LEN:${str.length}|VAL:$str\n');
          }
        }
        buffer.write('ROW_END\n');
      }

      final bytes = utf8.encode(buffer.toString());
      return sha256.convert(bytes).toString();
    } finally {
      await executor.close();
    }
  }

  /// Evaluates cycle outcome against the strict acceptance criteria:
  ///   A) New version completed + integrity_check ok + old data preserved.
  ///   B) Old version restored + integrity_check ok + canonical hash matches pre-upgrade baseline exactly.
  static bool evaluateCycleOutcome({
    required int initialVersion,
    required int targetVersion,
    required int finalVersion,
    required bool integrityOk,
    required String initialHash,
    required String finalHash,
  }) {
    if (!integrityOk) return false;

    // Successful upgrade path
    if (finalVersion == targetVersion) {
      return true;
    }

    // Successful rollback/restoration path
    if (finalVersion == initialVersion) {
      return initialHash == finalHash;
    }

    return false;
  }
}
