import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
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
  late TxWriter txWriter;
  late BranchProvider branchProvider;
  late _FakeAuthLocalDataSource auth;
  late FeatureGate gate;
  late ManagerPinService pinService;
  late InstallmentsFacadeImpl facade;
  late ShiftLocalDataSource shiftDs;

  const adminId = 'admin-1';
  const branchId = 'b1';
  const managerPin = '1234';

  final adminUser = UserModel(
    id: adminId,
    name: 'Admin',
    email: 'admin@erp.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    txWriter = TxWriter(db);
    branchProvider = BranchProvider(db);
    auth = _FakeAuthLocalDataSource()..setUser(adminUser);
    gate = FeatureGate(db, auth, txWriter, branchProvider);
    pinService = ManagerPinService(db, txWriter, branchProvider, auth, gate);

    // Setup manager PIN
    await pinService.setPin(pin: managerPin, userId: adminId);

    // Enable installments feature by default
    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: adminId);

    facade = InstallmentsFacadeImpl(
      db,
      txWriter,
      branchProvider,
      auth,
      gate,
      pinService,
    );
    shiftDs = ShiftLocalDataSourceImpl(db, branchProvider, txWriter, gate);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedSaleAndCustomer({
    required String saleId,
    required String customerId,
    int total = 500000,
  }) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.customers).insertOnConflictUpdate(
      CustomersCompanion.insert(
        id: customerId,
        branchId: branchId,
        name: 'Customer-$customerId',
        phone: '01012345678',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.sales).insertOnConflictUpdate(
      SalesCompanion.insert(
        id: saleId,
        branchId: branchId,
        shortRef: 'S-${saleId.hashCode.abs()}',
        cashierId: adminId,
        subtotal: total,
        discountType: 'none',
        total: total,
        paymentMethod: 'cash',
        date: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<String> seedContract({
    String contractId = 'c1',
    String saleId = 's1',
    String customerId = 'cust-1',
    int total = 500000,
    int downPayment = 0,
  }) async {
    await seedSaleAndCustomer(saleId: saleId, customerId: customerId, total: total);
    final res = await facade.createContract(
      saleId: saleId,
      customerId: customerId,
      totalPiasters: total,
      downPaymentPiasters: downPayment,
      interestBp: 0,
      interestModel: InstallmentInterestModel.fixed,
      durationMonths: 5,
      startDate: DateTime(2026, 1, 1),
      pin: managerPin,
    );
    return res.getOrElse(() => throw Exception('Failed to create contract: $res')).id;
  }

  group('Installment Payment & Cash Movements Integration Tests', () {
    test('1. recordPayment creates cash_movement with type installment_payment (cash)', () async {
      final contractId = await seedContract();

      final result = await facade.recordPayment(
        contractId: contractId,
        amountPiasters: 100000, // 1000 EGP
        paymentMethod: 'cash',
        pin: managerPin,
        notes: 'قسط شهر نوفمبر كاش',
      );

      expect(result.isRight(), isTrue);

      final movements = await (db.select(db.cashMovements)
            ..where((m) => m.type.equals('installment_payment')))
          .get();

      expect(movements.length, 1);
      final m = movements.first;
      expect(m.type, 'installment_payment');
      expect(m.method, 'cash');
      expect(m.direction, 'in');
      expect(m.amountPiasters, 100000);
      expect(m.referenceId, contractId);
      expect(m.notes, contains('قسط شهر نوفمبر كاش'));
    });

    test('2. recordPayment creates cash_movement with method card', () async {
      final contractId = await seedContract(saleId: 's-card', customerId: 'c-card');

      final result = await facade.recordPayment(
        contractId: contractId,
        amountPiasters: 150000, // 1500 EGP
        paymentMethod: 'card',
        pin: managerPin,
        notes: 'قسط فيزا',
      );

      expect(result.isRight(), isTrue);

      final movements = await (db.select(db.cashMovements)
            ..where((m) => m.type.equals('installment_payment')))
          .get();

      expect(movements.length, 1);
      final m = movements.first;
      expect(m.type, 'installment_payment');
      expect(m.method, 'card');
      expect(m.direction, 'in');
      expect(m.amountPiasters, 150000);
      expect(m.referenceId, contractId);
    });

    test('3. closeShift includes installment payments in cashIn and expected cash', () async {
      // 1. Open shift with 500 EGP (50,000 piasters)
      final shift = await shiftDs.openShift(
        openingBalance: 50000,
        cashierId: adminId,
        cashierName: 'Admin',
      );

      // 2. Seed contract and record installment payment of 1000 EGP (100,000 piasters) cash
      final contractId = await seedContract(saleId: 's-shift', customerId: 'c-shift');
      final res = await facade.recordPayment(
        contractId: contractId,
        amountPiasters: 100000,
        paymentMethod: 'cash',
        pin: managerPin,
      );
      expect(res.isRight(), isTrue);

      // 3. Verify movement was linked to shift
      final m = await (db.select(db.cashMovements)
            ..where((m) => m.type.equals('installment_payment')))
          .getSingle();
      expect(m.shiftId, shift.id);

      // 4. Check shift summary
      final summary = await shiftDs.getShiftSummary(shift.id);
      // Expected cash in drawer must be 500 opening + 1000 installment cash = 1500 EGP (150,000 piasters)
      expect(summary.expectedCashInDrawer, 150000);

      // 5. Close shift with counted 1500 EGP -> difference = 0
      final closed = await shiftDs.closeShift(
        countedBalance: 150000,
        shiftId: shift.id,
        userId: adminId,
      );
      expect(closed.expectedBalance, 150000);
      expect(closed.difference, 0);
    });

    test('4. recordPayment rejects overpayment without modifying remaining or creating cash_movement', () async {
      final contractId = await seedContract(saleId: 's-overpay', customerId: 'c-overpay', total: 100000);
      final contractBefore = await (db.select(db.customerInstallments)
            ..where((c) => c.id.equals(contractId)))
          .getSingle();

      // Trigger an invalid payment attempt (overpayment)
      final res = await facade.recordPayment(
        contractId: contractId,
        amountPiasters: 9999999, // Exceeds remaining
        paymentMethod: 'cash',
        pin: managerPin,
      );

      expect(res.isLeft(), isTrue);

      // Verify no installment_payments inserted
      final payments = await (db.select(db.installmentPayments)
            ..where((p) => p.customerInstallmentId.equals(contractId)))
          .get();
      expect(payments, isEmpty);

      // Verify no cash_movements inserted
      final movements = await (db.select(db.cashMovements)
            ..where((m) => m.referenceId.equals(contractId)))
          .get();
      expect(movements, isEmpty);

      // Verify contract remaining unchanged
      final contractAfter = await (db.select(db.customerInstallments)
            ..where((c) => c.id.equals(contractId)))
          .getSingle();
      expect(contractAfter.remainingPiasters, contractBefore.remainingPiasters);
    });
  });
}
