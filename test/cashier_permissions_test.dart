import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/domain/models/cashier_permissions_config.dart';
import 'package:clothes_erp/features/auth/services/cashier_permissions_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
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
  late FeatureGate gate;
  late _FakeAuthLocalDataSource authDs;
  late UserModel adminUser;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    authDs = _FakeAuthLocalDataSource();
    adminUser = UserModel(
      id: 'admin_1',
      name: 'Admin',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    authDs.setUser(adminUser);
    final tx = TxWriter(db);
    final branch = BranchProvider(db);
    gate = FeatureGate(db, authDs, tx, branch);
  });

  tearDown(() async {
    await db.close();
  });

  group('CashierPermissionsConfig Tests', () {
    test('default permissions are strict and secure', () {
      const config = CashierPermissionsConfig();
      expect(config.allowCreditSale, false);
      expect(config.allowInstallments, false);
      expect(config.allowGoodsIntake, false);
      expect(config.allowCashExpenses, false);
      expect(config.allowViewInvoicesHistory, false);
      expect(config.allowManualDiscount, false);
      expect(config.allowManageCustomers, true);
    });

    test('toJson and fromJson preserves all flags', () {
      const original = CashierPermissionsConfig(
        allowCreditSale: true,
        allowInstallments: true,
        allowGoodsIntake: true,
        allowCashExpenses: true,
        allowViewInvoicesHistory: true,
        allowManualDiscount: true,
        allowManageCustomers: false,
      );

      final jsonStr = original.toJson();
      final restored = CashierPermissionsConfig.fromJson(jsonStr);

      expect(restored.allowCreditSale, true);
      expect(restored.allowInstallments, true);
      expect(restored.allowGoodsIntake, true);
      expect(restored.allowCashExpenses, true);
      expect(restored.allowViewInvoicesHistory, true);
      expect(restored.allowManualDiscount, true);
      expect(restored.allowManageCustomers, false);
    });

    test('service saves and loads from FeatureGate', () async {
      await CashierPermissionsService.loadFromFeatureGate(gate);
      expect(CashierPermissionsService.current.allowCreditSale, false);

      const updated = CashierPermissionsConfig(
        allowCreditSale: true,
        allowInstallments: true,
      );
      await CashierPermissionsService.save(gate, updated, userId: adminUser.id);

      expect(CashierPermissionsService.current.allowCreditSale, true);
      expect(CashierPermissionsService.current.allowInstallments, true);

      // Verify persistence in DB
      await CashierPermissionsService.loadFromFeatureGate(gate);
      expect(CashierPermissionsService.current.allowCreditSale, true);
      expect(CashierPermissionsService.current.allowInstallments, true);
    });
  });
}

