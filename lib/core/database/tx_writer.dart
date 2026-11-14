import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

import 'package:injectable/injectable.dart';

@injectable
class TxWriter {
  final AppDatabase db;
  final _uuid = const Uuid();

  Future<void> Function()? beforeAuditWrite;

  @visibleForTesting
  Future<void> Function(int callNumber)? debugOnBeforeWrite;
  int _callCount = 0;

  TxWriter(this.db);

  void resetCallCount() => _callCount = 0;

  Future<void> write({
    required Future<void> Function() writeFn,
    required String branchId,
    required String entity,
    required String entityId,
    required String operation,
    required String userId,
    String? oldValue,
    String? newValue,
    String? auditAction,
    String payload = '{}',
  }) async {
    _callCount++;
    final callNum = _callCount;
    await db.transaction(() async {
      await writeFn();
      if (beforeAuditWrite != null) await beforeAuditWrite!();
      if (debugOnBeforeWrite != null) await debugOnBeforeWrite!(callNum);
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        entity: entity,
        entityId: entityId,
        operation: operation,
        payload: payload,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        userId: userId,
        action: auditAction ?? operation,
        entity: entity,
        entityId: entityId,
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        createdAt: DateTime.now(),
      ));
    });
  }
}
