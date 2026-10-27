import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

class TxWriter {
  final AppDatabase db;
  final _uuid = const Uuid();

  TxWriter(this.db);

  Future<void> write({
    required Future<void> Function() writeFn,
    required String branchId,
    required String entity,
    required String entityId,
    required String operation,
    required String userId,
    String? oldValue,
    String? newValue,
  }) async {
    await db.transaction(() async {
      await writeFn();
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        entity: entity,
        entityId: entityId,
        operation: operation,
        payload: '{}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        userId: userId,
        action: operation,
        entity: entity,
        entityId: entityId,
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        createdAt: DateTime.now(),
      ));
    });
  }
}
