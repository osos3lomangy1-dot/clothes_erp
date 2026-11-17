import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
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
  late TxWriter txWriter;
  late BranchProvider branchProvider;
  late FakeAuthLocalDataSource auth;
  late FeatureGate gate;
  late ManagerPinService pinService;
  late InstallmentsFacadeImpl facade;
  late ShiftLocalDataSourceImpl shiftDs;
  late String activeShiftId;

  const adminId = 'admin-1';
  const branchId = 'b1';
  const managerPin = '1234';
  const customerId = 'cust-bulk-1';

  final adminUser = UserModel(
    id: adminId,
    name: 'Admin',
    email: 'admin@erp.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> seedSaleAndCustomer(String saleId, int total) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.customers).insertOnConflictUpdate(
      CustomersCompanion.insert(
        id: customerId,
        branchId: branchId,
        name: 'أحمد محمود',
        phone: '01012345678',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.sales).insertOnConflictUpdate(
      SalesCompanion.insert(
        id: saleId,
        branchId: branchId,
        shortRef: 'S-$saleId',
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

  Future<String> createTestContract({
    required String saleId,
    required int totalPiasters,
    required DateTime startDate,
  }) async {
    await seedSaleAndCustomer(saleId, totalPiasters);
    final res = await facade.createContract(
      saleId: saleId,
      customerId: customerId,
      totalPiasters: totalPiasters,
      downPaymentPiasters: 0,
      interestBp: 0,
      interestModel: InstallmentInterestModel.fixed,
      durationMonths: 5,
      startDate: startDate,
      pin: managerPin,
    );
    return res.getOrElse(() => throw Exception('Failed to create contract')).id;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuthLocalDataSource()..setUser(adminUser);
    txWriter = TxWriter(db);
    branchProvider = BranchProvider(db);
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
    shiftDs = ShiftLocalDataSourceImpl(db, branchProvider, txWriter, gate);

    await pinService.setPin(pin: managerPin, userId: adminId);
    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: adminId);

    final shift = await shiftDs.openShift(
      openingBalance: 10000,
      cashierId: adminId,
      cashierName: 'Admin',
    );
    activeShiftId = shift.id;
  });

  tearDown(() async => await db.close());

  group('Bulk Customer Installment Payment (FIFO Allocation)', () {
    test('allocates payment FIFO across 3 contracts and syncs with shift cash drawer', () async {
      // Create 3 contracts of 50 EGP (5000 piasters) each -> Total 150 EGP (15000 piasters)
      final c1Id = await createTestContract(
        saleId: 'sale-1',
        totalPiasters: 5000,
        startDate: DateTime(2026, 1, 1),
      );
      final c2Id = await createTestContract(
        saleId: 'sale-2',
        totalPiasters: 5000,
        startDate: DateTime(2026, 2, 1),
      );
      final c3Id = await createTestContract(
        saleId: 'sale-3',
        totalPiasters: 5000,
        startDate: DateTime(2026, 3, 1),
      );

      // Customer pays 70 EGP (7000 piasters):
      // Should pay 5000 to c1 (completed), 2000 to c2 (remaining 3000), 0 to c3 (remaining 5000)
      final result = await facade.recordBulkCustomerPayment(
        customerId: customerId,
        amountPiasters: 7000,
        paymentMethod: 'cash',
        pin: managerPin,
      );

      expect(result.isRight(), isTrue);
      final bulkRes = result.getOrElse(() => throw Exception('Expected Right'));
      expect(bulkRes.totalAmountPiasters, equals(7000));
      expect(bulkRes.affectedContractsCount, equals(2));
      expect(bulkRes.payments.length, equals(2));

      // Verify contracts state
      final c1 = (await facade.getContract(c1Id)).getOrElse(() => throw Exception());
      final c2 = (await facade.getContract(c2Id)).getOrElse(() => throw Exception());
      final c3 = (await facade.getContract(c3Id)).getOrElse(() => throw Exception());

      expect(c1.remainingPiasters, equals(0));
      expect(c1.status, equals('completed'));

      expect(c2.remainingPiasters, equals(3000));
      expect(c2.status, equals('active'));

      expect(c3.remainingPiasters, equals(5000));
      expect(c3.status, equals('active'));

      // Verify cash movements recorded with shiftId
      final movements = await (db.select(db.cashMovements)
            ..where((m) => m.type.equals('installment_payment')))
          .get();
      expect(movements.length, equals(2));
      expect(movements.fold<int>(0, (sum, m) => sum + m.amountPiasters), equals(7000));
      expect(movements.every((m) => m.shiftId == activeShiftId && m.direction == 'in'), isTrue);
    });

    test('paying exact total completes all customer contracts', () async {
      final c1Id = await createTestContract(
        saleId: 'sale-1',
        totalPiasters: 5000,
        startDate: DateTime(2026, 1, 1),
      );
      final c2Id = await createTestContract(
        saleId: 'sale-2',
        totalPiasters: 10000,
        startDate: DateTime(2026, 2, 1),
      );

      final result = await facade.recordBulkCustomerPayment(
        customerId: customerId,
        amountPiasters: 15000,
        paymentMethod: 'cash',
        pin: managerPin,
      );

      expect(result.isRight(), isTrue);
      final bulkRes = result.getOrElse(() => throw Exception());
      expect(bulkRes.affectedContractsCount, equals(2));

      final c1 = (await facade.getContract(c1Id)).getOrElse(() => throw Exception());
      final c2 = (await facade.getContract(c2Id)).getOrElse(() => throw Exception());

      expect(c1.remainingPiasters, equals(0));
      expect(c1.status, equals('completed'));
      expect(c2.remainingPiasters, equals(0));
      expect(c2.status, equals('completed'));
    });

    test('rejects overpayment exceeding total customer debt', () async {
      await createTestContract(
        saleId: 'sale-1',
        totalPiasters: 5000,
        startDate: DateTime(2026, 1, 1),
      );
      await createTestContract(
        saleId: 'sale-2',
        totalPiasters: 5000,
        startDate: DateTime(2026, 2, 1),
      );

      // Total debt is 10000 (100 EGP). Try paying 15000 (150 EGP).
      final result = await facade.recordBulkCustomerPayment(
        customerId: customerId,
        amountPiasters: 15000,
        paymentMethod: 'cash',
        pin: managerPin,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, contains('يتجاوز إجمالي ديون وأقساط العميل')),
        (_) => fail('Expected Left'),
      );

      // Ensure no payments or cash movements were created
      final payments = await db.select(db.installmentPayments).get();
      expect(payments, isEmpty);
    });

    test('rejects zero or negative payment amount', () async {
      await createTestContract(
        saleId: 'sale-1',
        totalPiasters: 5000,
        startDate: DateTime(2026, 1, 1),
      );

      final resZero = await facade.recordBulkCustomerPayment(
        customerId: customerId,
        amountPiasters: 0,
        paymentMethod: 'cash',
        pin: managerPin,
      );
      expect(resZero.isLeft(), isTrue);

      final resNeg = await facade.recordBulkCustomerPayment(
        customerId: customerId,
        amountPiasters: -100,
        paymentMethod: 'cash',
        pin: managerPin,
      );
      expect(resNeg.isLeft(), isTrue);
    });

    test('rejects wrong manager PIN', () async {
      await createTestContract(
        saleId: 'sale-1',
        totalPiasters: 5000,
        startDate: DateTime(2026, 1, 1),
      );

      final result = await facade.recordBulkCustomerPayment(
        customerId: customerId,
        amountPiasters: 2000,
        paymentMethod: 'cash',
        pin: '9999',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<AuthFailure>()),
        (_) => fail('Expected Left'),
      );
    });
  });
}
