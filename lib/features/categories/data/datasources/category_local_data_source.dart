import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';

@lazySingleton
class CategoryLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final _uuid = const Uuid();

  CategoryLocalDataSource(this._db, this._branchProvider);

  Future<String> _branchId() => _branchProvider.getBranchId();

  Future<List<Category>> getCategories() async {
    return (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<void> addCategory(String name, {String? description, int sortOrder = 0}) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final branchId = await _branchId();
    await _db.transaction(() async {
      await _db.into(_db.categories).insert(CategoriesCompanion.insert(
        id: id,
        branchId: branchId,
        name: name,
        sortOrder: Value(sortOrder),
        createdAt: now,
        updatedAt: now,
      ));
      await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        entity: 'category',
        entityId: id,
        operation: 'insert',
        payload: '{}',
        createdAt: now,
        updatedAt: now,
      ));
      await _db.into(_db.auditLogs).insert(AuditLogsCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        userId: 'system',
        action: 'create',
        entity: 'category',
        entityId: id,
        createdAt: now,
      ));
    });
  }

  Future<void> updateCategory(String id, String name, {String? description, int? sortOrder}) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(name: Value(name), sortOrder: sortOrder != null ? Value(sortOrder) : const Value.absent(), updatedAt: Value(now)),
      );
      await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        entity: 'category',
        entityId: id,
        operation: 'update',
        payload: '{}',
        createdAt: now,
        updatedAt: now,
      ));
      await _db.into(_db.auditLogs).insert(AuditLogsCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        userId: 'system',
        action: 'update',
        entity: 'category',
        entityId: id,
        createdAt: now,
      ));
    });
  }

  Future<void> deleteCategory(String id) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        entity: 'category',
        entityId: id,
        operation: 'delete',
        payload: '{}',
        createdAt: now,
        updatedAt: now,
      ));
      await _db.into(_db.auditLogs).insert(AuditLogsCompanion.insert(
        id: _uuid.v4(),
        branchId: branchId,
        userId: 'system',
        action: 'delete',
        entity: 'category',
        entityId: id,
        createdAt: now,
      ));
    });
  }
}
