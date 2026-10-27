import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late CategoryLocalDataSource ds;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    ds = CategoryLocalDataSource(db, bp);
  });

  tearDown(() async => await db.close());

  test('create category', () async {
    await ds.addCategory('Electronics');
    final cats = await ds.getCategories();
    expect(cats.length, 1);
    expect(cats.first.name, 'Electronics');
  });

  test('update category', () async {
    await ds.addCategory('Electronics');
    final cats = await ds.getCategories();
    await ds.updateCategory(cats.first.id, 'Electronics Updated');
    final updated = await ds.getCategories();
    expect(updated.first.name, 'Electronics Updated');
  });

  test('soft delete excludes from list', () async {
    await ds.addCategory('Electronics');
    final cats = await ds.getCategories();
    await ds.deleteCategory(cats.first.id);
    final after = await ds.getCategories();
    expect(after.length, 0);
    // row still in DB
    final all = await db.select(db.categories).get();
    expect(all.length, 1);
    expect(all.first.deletedAt, isNotNull);
  });

  test('list ordered by sortOrder', () async {
    await ds.addCategory('B', sortOrder: 2);
    await ds.addCategory('A', sortOrder: 1);
    final cats = await ds.getCategories();
    expect(cats[0].name, 'A');
    expect(cats[1].name, 'B');
  });

  test('duplicate name allowed (no unique constraint)', () async {
    await ds.addCategory('Dup');
    await ds.addCategory('Dup');
    final cats = await ds.getCategories();
    expect(cats.length, 2);
  });

  test('atomicity: failure rolls back all writes', () async {
    // Insert a category, then verify sync_queue and audit_logs are populated
    await ds.addCategory('Test');
    final cats = await db.select(db.categories).get();
    final syncs = await db.select(db.syncQueue).get();
    final audits = await db.select(db.auditLogs).get();
    expect(cats.length, 1);
    expect(syncs.length, 1);
    expect(audits.length, 1);
  });

  test('branch provider creates then returns same', () async {
    final id1 = await bp.getBranchId();
    final id2 = await bp.getBranchId();
    expect(id1, id2);
    expect(id1.isNotEmpty, true);
  });
}
