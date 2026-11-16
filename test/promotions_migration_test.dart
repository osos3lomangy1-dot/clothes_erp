import 'dart:io';

import 'package:clothes_erp/core/database/app_database.dart' hide Promotion;
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/promotions/data/datasources/promotions_local_data_source.dart';
import 'package:clothes_erp/features/promotions/data/repositories/promotions_repository_impl.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFeatureGate implements FeatureGate {
  bool promotionsEnabled = false;

  @override
  Future<bool> isEnabled(String key) async {
    if (key == FeatureKeys.promotions) return promotionsEnabled;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'b-main';
}

void main() {
  group('Promotions Migration (v8 -> v9) & Repository Tests', () {
    late File tempDbFile;

    setUp(() {
      tempDbFile = File(
        '${Directory.systemTemp.path}/promotions_mig_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      if (tempDbFile.existsSync()) {
        tempDbFile.deleteSync();
      }
    });

    tearDown(() {
      if (tempDbFile.existsSync()) {
        try {
          tempDbFile.deleteSync();
        } catch (_) {}
      }
    });

    test('v8 -> v9 migration creates tables and column, and is idempotent', () async {
      final db = AppDatabase(NativeDatabase(tempDbFile));

      // Trigger database creation
      await db.customSelect('SELECT 1').get();

      // Verify PRAGMA user_version is 10
      final versionResult = await db.customSelect('PRAGMA user_version').getSingle();
      expect(versionResult.data['user_version'], equals(10));

      // Verify tables exist
      Future<bool> tableExists(String table) async {
        final rows = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
        ).get();
        return rows.isNotEmpty;
      }

      expect(await tableExists('promotions'), isTrue);
      expect(await tableExists('promotion_applications'), isTrue);

      // Verify column promotion_discount_piasters on sale_items
      final saleItemCols = await db.customSelect('PRAGMA table_info("sale_items")').get();
      final colNames = saleItemCols.map((c) => (c.data['name'] as String).toLowerCase()).toSet();
      expect(colNames.contains('promotion_discount_piasters'), isTrue);

      // Verify idempotency: calling migrateToV9 again must succeed cleanly
      final migrator = db.createMigrator();
      await expectLater(db.migrateToV9(migrator), completes);

      await db.close();
    });

    test('FeatureGate blocks CREATE when disabled, but allows READ', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeFeatureGate = _FakeFeatureGate();
      final branchProvider = _TestBranchProvider();
      final localDataSource = PromotionsLocalDataSourceImpl(db);
      final repo = PromotionsRepositoryImpl(
        localDataSource,
        fakeFeatureGate,
        branchProvider,
      );

      final now = DateTime(2026, 11, 15, 12, 0);
      final testPromo = Promotion(
        id: 'p-repo-1',
        branchId: 'b-main',
        name: 'عرض الخصم',
        type: 'percent',
        scope: 'all',
        valueBp: 1500,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 5)),
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      );

      // 1. Feature disabled (default)
      fakeFeatureGate.promotionsEnabled = false;

      // Read is allowed even when disabled
      final activeListResult = await repo.getActivePromotions(now: now);
      expect(activeListResult.isRight(), isTrue);
      expect(activeListResult.getOrElse(() => []), isEmpty);

      // Create is BLOCKED
      final createResult = await repo.createPromotion(testPromo);
      expect(createResult.isLeft(), isTrue);
      createResult.fold(
        (failure) {
          expect(failure, isA<FeatureDisabledFailure>());
          expect((failure as FeatureDisabledFailure).featureKey, FeatureKeys.promotions);
        },
        (_) => fail('Should have failed when feature disabled'),
      );

      // 2. Feature enabled
      fakeFeatureGate.promotionsEnabled = true;

      // Create succeeds
      final createSuccessResult = await repo.createPromotion(testPromo);
      expect(createSuccessResult.isRight(), isTrue);

      // Read now returns the inserted promotion
      final activeAfterResult = await repo.getActivePromotions(now: now);
      expect(activeAfterResult.isRight(), isTrue);
      final list = activeAfterResult.getOrElse(() => []);
      expect(list.length, equals(1));
      expect(list.first.id, equals('p-repo-1'));
      expect(list.first.name, equals('عرض الخصم'));

      await db.close();
    });
  });
}
