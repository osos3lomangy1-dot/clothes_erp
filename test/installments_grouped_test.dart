import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthDs implements AuthLocalDataSource {
  UserModel? _user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<void> clearCache() async => _user = null;
}

void main() {
  late AppDatabase db;
  late TxWriter txWriter;
  late BranchProvider branchProvider;
  late _FakeAuthDs auth;
  late FeatureGate gate;
  late ManagerPinService pinService;
  late InstallmentsFacade facade;

  const branchId = 'test-branch';
  final now = DateTime.now();

  Future<void> insertCustomer({required String id, required String name}) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: id,
        branchId: branchId,
        name: name,
        phone: '010${id.hashCode.abs()}',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> insertContract({
    required String id,
    required String customerId,
    required int totalPiasters,
    required int remainingPiasters,
    required int monthlyAmountPiasters,
    required String status,
    required DateTime startDate,
    required DateTime endDate,
    DateTime? deletedAt,
  }) async {
    await db.into(db.customerInstallments).insert(
      CustomerInstallmentsCompanion.insert(
        id: id,
        branchId: branchId,
        saleId: 'sale-$id',
        customerId: customerId,
        totalPiasters: totalPiasters,
        downPaymentPiasters: const Value(0),
        principalPiasters: totalPiasters,
        interestBp: 0,
        monthlyAmountPiasters: monthlyAmountPiasters,
        remainingPiasters: remainingPiasters,
        durationMonths: 6,
        startDate: startDate,
        endDate: endDate,
        status: Value(status),
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
        deletedAt: Value(deletedAt),
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    txWriter = TxWriter(db);
    branchProvider = BranchProvider(db);
    auth = _FakeAuthDs()
      ..cacheUser(UserModel(
        id: 'u1',
        name: 'Admin',
        email: 'admin@store.com',
        role: 'admin',
        isActive: true,
        createdAt: now,
      ));
    gate = FeatureGate(db, auth, txWriter, branchProvider);
    pinService = ManagerPinService(db, txWriter, branchProvider, auth, gate);

    facade = InstallmentsFacadeImpl(
      db,
      txWriter,
      branchProvider,
      auth,
      gate,
      pinService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('getGroupedByCustomer Unit Tests', () {
    test('1. getGroupedByCustomer aggregates contracts per customer', () async {
      await insertCustomer(id: 'c1', name: 'أحمد علي');
      await insertCustomer(id: 'c2', name: 'محمود حسن');

      // Customer 1: 2 active contracts
      await insertContract(
        id: 'cont-1',
        customerId: 'c1',
        totalPiasters: 100000,
        remainingPiasters: 60000,
        monthlyAmountPiasters: 10000,
        status: 'active',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.add(const Duration(days: 150)),
      );
      await insertContract(
        id: 'cont-2',
        customerId: 'c1',
        totalPiasters: 50000,
        remainingPiasters: 40000,
        monthlyAmountPiasters: 8000,
        status: 'active',
        startDate: now.subtract(const Duration(days: 10)),
        endDate: now.add(const Duration(days: 170)),
      );

      // Customer 2: 1 active contract
      await insertContract(
        id: 'cont-3',
        customerId: 'c2',
        totalPiasters: 80000,
        remainingPiasters: 50000,
        monthlyAmountPiasters: 12000,
        status: 'active',
        startDate: now.subtract(const Duration(days: 5)),
        endDate: now.add(const Duration(days: 175)),
      );

      final result = await facade.getGroupedByCustomer(now: now);
      expect(result.isRight(), isTrue);

      final groups = result.getOrElse(() => []);
      expect(groups.length, 2);

      final g1 = groups.firstWhere((g) => g.customerId == 'c1');
      expect(g1.customerName, 'أحمد علي');
      expect(g1.contractsCount, 2);
      expect(g1.contracts.length, 2);

      final g2 = groups.firstWhere((g) => g.customerId == 'c2');
      expect(g2.customerName, 'محمود حسن');
      expect(g2.contractsCount, 1);
    });

    test('2. customer with 0 active contracts is excluded', () async {
      await insertCustomer(id: 'c-inactive', name: 'عميل مكتمل');

      // Completed contract
      await insertContract(
        id: 'cont-comp',
        customerId: 'c-inactive',
        totalPiasters: 50000,
        remainingPiasters: 0,
        monthlyAmountPiasters: 10000,
        status: 'completed',
        startDate: now.subtract(const Duration(days: 180)),
        endDate: now.subtract(const Duration(days: 10)),
      );

      final result = await facade.getGroupedByCustomer(now: now);
      final groups = result.getOrElse(() => []);
      expect(groups.any((g) => g.customerId == 'c-inactive'), isFalse);
    });

    test('3. customer with 3 contracts shows correct count, total remaining, total monthly', () async {
      await insertCustomer(id: 'c-multi', name: 'سامي كمال');

      await insertContract(
        id: 'cont-m1',
        customerId: 'c-multi',
        totalPiasters: 100000,
        remainingPiasters: 10000,
        monthlyAmountPiasters: 5000,
        status: 'active',
        startDate: now,
        endDate: now.add(const Duration(days: 180)),
      );
      await insertContract(
        id: 'cont-m2',
        customerId: 'c-multi',
        totalPiasters: 200000,
        remainingPiasters: 20000,
        monthlyAmountPiasters: 10000,
        status: 'active',
        startDate: now,
        endDate: now.add(const Duration(days: 180)),
      );
      await insertContract(
        id: 'cont-m3',
        customerId: 'c-multi',
        totalPiasters: 300000,
        remainingPiasters: 30000,
        monthlyAmountPiasters: 15000,
        status: 'active',
        startDate: now,
        endDate: now.add(const Duration(days: 180)),
      );

      final result = await facade.getGroupedByCustomer(now: now);
      final groups = result.getOrElse(() => []);
      final group = groups.firstWhere((g) => g.customerId == 'c-multi');

      expect(group.contractsCount, 3);
      expect(group.totalRemainingPiasters, 60000);
      expect(group.totalMonthlyAmountPiasters, 30000);
      expect(group.currentMonthDuePiasters, 30000);
    });

    test('4. cancelled contracts excluded from grouping', () async {
      await insertCustomer(id: 'c-cancelled', name: 'عميل ملغي');

      await insertContract(
        id: 'cont-can',
        customerId: 'c-cancelled',
        totalPiasters: 60000,
        remainingPiasters: 60000,
        monthlyAmountPiasters: 10000,
        status: 'cancelled',
        startDate: now,
        endDate: now.add(const Duration(days: 180)),
      );

      final result = await facade.getGroupedByCustomer(now: now);
      final groups = result.getOrElse(() => []);
      expect(groups.any((g) => g.customerId == 'c-cancelled'), isFalse);
    });

    test('5. completed contracts excluded from grouping', () async {
      await insertCustomer(id: 'c-done', name: 'عميل منتهي');

      await insertContract(
        id: 'cont-done',
        customerId: 'c-done',
        totalPiasters: 50000,
        remainingPiasters: 0,
        monthlyAmountPiasters: 10000,
        status: 'completed',
        startDate: now.subtract(const Duration(days: 180)),
        endDate: now.subtract(const Duration(days: 30)),
      );

      final result = await facade.getGroupedByCustomer(now: now);
      final groups = result.getOrElse(() => []);
      expect(groups.any((g) => g.customerId == 'c-done'), isFalse);
    });

    test('6. overdue contracts included in grouping', () async {
      await insertCustomer(id: 'c-overdue', name: 'عميل متأخر');

      // End date in the past, remaining > 0 → statusAt(now) == 'overdue'
      await insertContract(
        id: 'cont-over',
        customerId: 'c-overdue',
        totalPiasters: 70000,
        remainingPiasters: 35000,
        monthlyAmountPiasters: 10000,
        status: 'active', // stored status is active
        startDate: now.subtract(const Duration(days: 200)),
        endDate: now.subtract(const Duration(days: 20)), // past due
      );

      final result = await facade.getGroupedByCustomer(now: now);
      final groups = result.getOrElse(() => []);
      final overdueGroup = groups.firstWhere((g) => g.customerId == 'c-overdue');

      expect(overdueGroup.contractsCount, 1);
      expect(overdueGroup.totalRemainingPiasters, 35000);
      expect(overdueGroup.contracts.first.statusAt(now), 'overdue');
    });

    test('7. customerName is populated from customers table', () async {
      const expectedName = 'طارق عبد الرحمن السعيد';
      await insertCustomer(id: 'c-special', name: expectedName);

      await insertContract(
        id: 'cont-spec',
        customerId: 'c-special',
        totalPiasters: 90000,
        remainingPiasters: 45000,
        monthlyAmountPiasters: 15000,
        status: 'active',
        startDate: now,
        endDate: now.add(const Duration(days: 180)),
      );

      final result = await facade.getGroupedByCustomer(now: now);
      final groups = result.getOrElse(() => []);
      final group = groups.firstWhere((g) => g.customerId == 'c-special');

      expect(group.customerName, expectedName);
    });
  });
}
