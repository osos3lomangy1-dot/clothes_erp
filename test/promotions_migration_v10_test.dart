import 'package:clothes_erp/core/database/app_database.dart' hide Promotion;
import 'package:clothes_erp/features/promotions/data/datasources/promotions_local_data_source.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Promotions Migration (v9 -> v10) & Repository Tests', () {
    late AppDatabase db;
    late PromotionsLocalDataSource dataSource;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dataSource = PromotionsLocalDataSourceImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('1. migration v10 creates promotion_targets table', () async {
      final migrator = db.createMigrator();
      await db.migrateToV10(migrator);

      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='promotion_targets'",
      ).get();

      expect(tables, isNotEmpty);
      expect(tables.first.data['name'], equals('promotion_targets'));
    });

    test('2. migration v10 backfills promotion_targets from existing promotions.target_id', () async {
      final now = DateTime.now();

      // Insert existing promotions with target_id (v9 style)
      await db.customStatement('''
        INSERT INTO promotions (
          id, branch_id, name, type, scope, target_id, value_bp,
          min_quantity, starts_at, ends_at, is_active, priority,
          created_by, created_at, updated_at
        ) VALUES (
          'promo-legacy-1', 'b-1', 'Legacy Promo 1', 'percent', 'product', 'target-prod-1', 1000,
          1, '${now.toIso8601String()}', '${now.add(const Duration(days: 7)).toIso8601String()}', 1, 0,
          'user-1', '${now.toIso8601String()}', '${now.toIso8601String()}'
        );
      ''');

      await db.customStatement('''
        INSERT INTO promotions (
          id, branch_id, name, type, scope, target_id, value_bp,
          min_quantity, starts_at, ends_at, is_active, priority,
          created_by, created_at, updated_at
        ) VALUES (
          'promo-legacy-2', 'b-1', 'Legacy Promo 2', 'percent', 'category', 'target-cat-1', 500,
          1, '${now.toIso8601String()}', '${now.add(const Duration(days: 7)).toIso8601String()}', 1, 0,
          'user-1', '${now.toIso8601String()}', '${now.toIso8601String()}'
        );
      ''');

      // Run migration
      final migrator = db.createMigrator();
      await db.migrateToV10(migrator);

      // Verify backfilled rows
      final targets = await db.customSelect(
        "SELECT promotion_id, target_type, target_id FROM promotion_targets ORDER BY promotion_id ASC",
      ).get();

      expect(targets.length, equals(2));
      expect(targets[0].data['promotion_id'], equals('promo-legacy-1'));
      expect(targets[0].data['target_type'], equals('product'));
      expect(targets[0].data['target_id'], equals('target-prod-1'));

      expect(targets[1].data['promotion_id'], equals('promo-legacy-2'));
      expect(targets[1].data['target_type'], equals('category'));
      expect(targets[1].data['target_id'], equals('target-cat-1'));
    });

    test('3. migration v10 is idempotent (run twice, no duplicate rows)', () async {
      final now = DateTime.now();

      await db.customStatement('''
        INSERT INTO promotions (
          id, branch_id, name, type, scope, target_id, value_bp,
          min_quantity, starts_at, ends_at, is_active, priority,
          created_by, created_at, updated_at
        ) VALUES (
          'promo-idemp', 'b-1', 'Idemp Promo', 'percent', 'product', 'target-p1', 1000,
          1, '${now.toIso8601String()}', '${now.add(const Duration(days: 7)).toIso8601String()}', 1, 0,
          'user-1', '${now.toIso8601String()}', '${now.toIso8601String()}'
        );
      ''');

      final migrator = db.createMigrator();
      // Run once
      await db.migrateToV10(migrator);
      final count1 = await db.customSelect(
        "SELECT COUNT(*) as c FROM promotion_targets WHERE promotion_id = 'promo-idemp'",
      ).getSingle();
      expect(count1.data['c'], equals(1));

      // Run second time (idempotency check)
      await db.migrateToV10(migrator);
      final count2 = await db.customSelect(
        "SELECT COUNT(*) as c FROM promotion_targets WHERE promotion_id = 'promo-idemp'",
      ).getSingle();
      expect(count2.data['c'], equals(1));
    });

    test('4. createPromotion with multiple targetIds inserts N promotion_targets rows', () async {
      final now = DateTime.now();
      final promo = Promotion(
        id: 'promo-multi-1',
        branchId: 'b-1',
        name: 'Multi Target Promo',
        type: 'percent',
        scope: 'product',
        targetIds: const ['prod-1', 'prod-2', 'prod-3'],
        valueBp: 1500,
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(days: 5)),
        createdBy: 'user-admin',
        createdAt: now,
        updatedAt: now,
      );

      await dataSource.createPromotion(promo);

      // Verify promotion row created
      final fetched = await dataSource.getPromotionById('promo-multi-1');
      expect(fetched, isNotNull);
      expect(fetched!.targetIds, equals(['prod-1', 'prod-2', 'prod-3']));
      expect(fetched.targetId, equals('prod-1')); // legacy fallback

      // Verify promotion_targets table rows directly
      final rows = await db.customSelect(
        "SELECT target_id, target_type FROM promotion_targets WHERE promotion_id = 'promo-multi-1' AND deleted_at IS NULL ORDER BY target_id ASC",
      ).get();

      expect(rows.length, equals(3));
      expect(rows.map((r) => r.data['target_id'] as String).toList(), equals(['prod-1', 'prod-2', 'prod-3']));
      expect(rows.every((r) => r.data['target_type'] == 'product'), isTrue);
    });

    test('5. updatePromotion replaces targetIds (soft-delete old, insert new)', () async {
      final now = DateTime.now();
      final promo = Promotion(
        id: 'promo-update-1',
        branchId: 'b-1',
        name: 'Initial Promo',
        type: 'fixed',
        scope: 'product',
        targetIds: const ['prod-A', 'prod-B'],
        valuePiasters: 2000,
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(days: 5)),
        createdBy: 'user-admin',
        createdAt: now,
        updatedAt: now,
      );

      await dataSource.createPromotion(promo);

      // Now update with new targetIds
      final updatedPromo = promo.copyWith(
        name: 'Updated Promo',
        targetIds: const ['prod-B', 'prod-C', 'prod-D'],
      );

      await dataSource.updatePromotion(updatedPromo);

      final fetched = await dataSource.getPromotionById('promo-update-1');
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Updated Promo'));
      expect(fetched.targetIds, equals(['prod-B', 'prod-C', 'prod-D']));

      // Check active targets in DB
      final activeRows = await db.customSelect(
        "SELECT target_id FROM promotion_targets WHERE promotion_id = 'promo-update-1' AND deleted_at IS NULL ORDER BY target_id ASC",
      ).get();
      expect(activeRows.length, equals(3));
      expect(activeRows.map((r) => r.data['target_id'] as String).toList(), equals(['prod-B', 'prod-C', 'prod-D']));

      // Check soft-deleted old targets in DB
      final deletedRows = await db.customSelect(
        "SELECT target_id FROM promotion_targets WHERE promotion_id = 'promo-update-1' AND deleted_at IS NOT NULL ORDER BY target_id ASC",
      ).get();
      expect(deletedRows.length, equals(2));
      expect(deletedRows.map((r) => r.data['target_id'] as String).toList(), equals(['prod-A', 'prod-B']));
    });
  });
}
