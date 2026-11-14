import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late FakeAuthLocalDataSource auth;
  late FeatureGate gate;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    auth = FakeAuthLocalDataSource();
    auth.setUser(UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'a@a.a',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    ));
    gate = FeatureGate(db, auth, TxWriter(db), branchProvider);
  });

  tearDown(() async {
    await db.close();
  });

  group('FeatureGate Phase 1', () {
    test('core features always enabled and not disableable', () async {
      final features = await gate.getFeatures();
      for (final k in [
        FeatureKeys.auth,
        FeatureKeys.pos,
        FeatureKeys.inventory,
        FeatureKeys.inventoryLogs,
        FeatureKeys.customers,
      ]) {
        expect(features[k], true, reason: '$k must be enabled by default');
      }

      await expectLater(
        () => gate.setFeatureEnabled(FeatureKeys.pos, false, userId: 'admin-1'),
        throwsA(isA<Exception>()),
      );
      final after = await gate.getFeatures();
      expect(after[FeatureKeys.pos], true);
    });

    test('dependencies: enabling child enables parent automatically', () async {
      await gate.setFeatureEnabled(FeatureKeys.suppliers, false, userId: 'admin-1');
      await gate.setFeatureEnabled(FeatureKeys.purchases, false, userId: 'admin-1');
      var f = await gate.getFeatures();
      expect(f[FeatureKeys.purchases], false);
      expect(f[FeatureKeys.suppliers], false);

      await gate.setFeatureEnabled(FeatureKeys.suppliers, true, userId: 'admin-1');
      f = await gate.getFeatures();
      expect(f[FeatureKeys.suppliers], true);
      expect(f[FeatureKeys.purchases], true, reason: 'parent purchases must be enabled');

      await gate.setFeatureEnabled(FeatureKeys.payroll, false, userId: 'admin-1');
      await gate.setFeatureEnabled(FeatureKeys.employees, false, userId: 'admin-1');
      await gate.setFeatureEnabled(FeatureKeys.payroll, true, userId: 'admin-1');
      f = await gate.getFeatures();
      expect(f[FeatureKeys.employees], true);
      expect(f[FeatureKeys.payroll], true);
    });

    test('disable-parent is rejected when dependent child is enabled (DependencyBlockedFailure)', () async {
      // defaults: purchases and suppliers enabled
      var f = await gate.getFeatures();
      expect(f[FeatureKeys.purchases], true);
      expect(f[FeatureKeys.suppliers], true);

      await expectLater(
        () => gate.setFeatureEnabled(FeatureKeys.purchases, false, userId: 'admin-1'),
        throwsA(isA<DependencyBlockedFailure>()),
      );
      f = await gate.getFeatures();
      expect(f[FeatureKeys.purchases], true, reason: 'parent must remain enabled');
      expect(f[FeatureKeys.suppliers], true);
    });

    test('disabling feature with existing data does not delete data', () async {
      final now = DateTime.now();
      final branchId = await branchProvider.getBranchId();
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'exp-1',
        branchId: branchId,
        category: 'rent',
        amount: 1000,
        userId: 'u1',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));
      expect((await db.select(db.expenses).get()).length, 1);

      await gate.setFeatureEnabled(FeatureKeys.expenses, false, userId: 'admin-1');
      final f = await gate.getFeatures();
      expect(f[FeatureKeys.expenses], false);

      final rows = await db.select(db.expenses).get();
      expect(rows.length, 1, reason: 'existing expense data must remain');
      expect(rows.first.deletedAt, isNull);
    });

    test('cashier cannot change feature/payment settings at domain level (not UI)', () async {
      auth.setUser(UserModel(
        id: 'cashier-1',
        name: 'Cashier',
        email: 'c@c.c',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ));
      await expectLater(
        () => gate.setFeatureEnabled(FeatureKeys.expenses, false, userId: 'cashier-1'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => gate.setMeta('payment.cash', '0', userId: 'cashier-1'),
        throwsA(isA<Exception>()),
      );
      auth.setUser(UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ));
      final features = await gate.getFeatures();
      expect(features[FeatureKeys.expenses], true, reason: 'cashier attempt must not change state');
    });

    test('changes emit via FeatureGate stream (sidebar updates immediately)', () async {
      final events = <Map<String, bool>>[];
      final sub = gate.watchFeatures().listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await gate.setFeatureEnabled(FeatureKeys.expenses, false, userId: 'admin-1');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await gate.setFeatureEnabled(FeatureKeys.expenses, true, userId: 'admin-1');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();

      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.any((m) => m[FeatureKeys.expenses] == false), true);
      expect(events.last[FeatureKeys.expenses], true);
    });

    test('setting change propagates to SettingsCubit stream/state', () async {
      final cubit = SettingsCubit(gate)..start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cubit.state.features[FeatureKeys.expenses], true);

      await gate.setFeatureEnabled(FeatureKeys.expenses, false, userId: 'admin-1');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(cubit.state.features[FeatureKeys.expenses], false, reason: 'cubit stream emits updated feature map');

      await gate.setFeatureEnabled(FeatureKeys.expenses, true, userId: 'admin-1');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(cubit.state.features[FeatureKeys.expenses], true);
      await cubit.close();
    });

    test('old shop with no feature keys uses defaults', () async {
      final features = await gate.getFeatures();
      expect(features[FeatureKeys.auth], true);
      expect(features[FeatureKeys.pos], true);
      expect(features[FeatureKeys.inventory], true);
      expect(features[FeatureKeys.inventoryLogs], true);
      expect(features[FeatureKeys.customers], true);
      expect(features[FeatureKeys.purchases], true);
      expect(features[FeatureKeys.suppliers], true);
      expect(features[FeatureKeys.employees], true);
      expect(features[FeatureKeys.payroll], true);
      expect(features[FeatureKeys.shifts], true);
      expect(features[FeatureKeys.reports], true);
      expect(features[FeatureKeys.expenses], true);
      expect(features[FeatureKeys.installments], false);
      expect(features[FeatureKeys.partners], false);
      expect(features[FeatureKeys.loyalty], false);
    });

    test('stores each feature as separate feature.<name> key (distinct rows, no blob) and audits', () async {
      await gate.setFeatureEnabled(FeatureKeys.reports, false, userId: 'admin-1');
      await gate.setFeatureEnabled(FeatureKeys.expenses, false, userId: 'admin-1');
      final rows = await (db.select(db.appMeta)..where((t) => t.key.like('feature.%'))).get();
      final keys = rows.map((r) => r.key).toSet();
      expect(keys.contains('feature.reports'), true);
      expect(keys.contains('feature.expenses'), true);
      expect(keys.length, greaterThanOrEqualTo(2), reason: 'distinct feature.* rows stored separately');
      expect(keys.any((k) => k == 'features' || k == 'features_json'), false, reason: 'no serialized blob key');

      final reportRow = rows.firstWhere((r) => r.key == 'feature.reports');
      expect(reportRow.value, '0');

      final audits = await (db.select(db.auditLogs)
            ..where((a) => a.action.equals('feature_toggle') & a.entityId.equals('feature.reports')))
          .get();
      expect(audits.isNotEmpty, true);
      expect(audits.last.oldValue, isNotNull);
      expect(audits.last.newValue, '0');
      expect(audits.last.userId, 'admin-1');
    });

    test('feature.installments key exists conceptually but not enabled by default', () async {
      final features = await gate.getFeatures();
      expect(features.containsKey(FeatureKeys.installments), true);
      expect(features[FeatureKeys.installments], false);
      // enabling installments should auto-enable customers (core/already true)
      await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: 'admin-1');
      final f2 = await gate.getFeatures();
      expect(f2[FeatureKeys.installments], true);
      expect(f2[FeatureKeys.customers], true);
    });
    test('feature toggle enqueues sync_queue entry via TxWriter', () async {
      await gate.setFeatureEnabled(FeatureKeys.reports, false, userId: 'admin-1');
      final rows = await (db.select(db.syncQueue)
            ..where((q) => q.entity.equals('app_meta') & q.entityId.equals('feature.reports')))
          .get();
      expect(rows.isNotEmpty, true);
      expect(rows.last.operation, 'upsert');
    });

    test('feature toggle audit_logs written in same transaction as app_meta', () async {
      await gate.setFeatureEnabled(FeatureKeys.expenses, false, userId: 'admin-1');
      final meta = await (db.select(db.appMeta)..where((t) => t.key.equals('feature.expenses'))).getSingle();
      expect(meta.value, '0');
      final audits = await (db.select(db.auditLogs)
            ..where((a) => a.action.equals('feature_toggle') & a.entityId.equals('feature.expenses')))
          .get();
      expect(audits.isNotEmpty, true);
      expect(audits.last.oldValue, isNotNull);
      expect(audits.last.newValue, '0');
    });

    test('payment method change enqueues sync_queue entry via TxWriter', () async {
      await gate.setMeta('payment.cash', '0', userId: 'admin-1');
      final rows = await (db.select(db.syncQueue)
            ..where((q) => q.entity.equals('app_meta') & q.entityId.equals('payment.cash')))
          .get();
      expect(rows.isNotEmpty, true);
      expect(rows.last.operation, 'upsert');
    });
  });
}
