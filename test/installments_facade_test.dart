import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_plan_entity.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_summary.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:dartz/dartz.dart';
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

  const adminId = 'admin-1';
  const cashierId = 'cashier-1';
  const branchId = 'b1';
  const managerPin = '1234';
  final start = DateTime(2026, 1, 1);

  final adminUser = UserModel(
    id: adminId,
    name: 'Admin',
    email: 'admin@erp.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  final cashierUser = UserModel(
    id: cashierId,
    name: 'Cashier',
    email: 'cashier@erp.com',
    role: 'cashier',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> seedSaleAndCustomer({
    required String saleId,
    required String customerId,
    int total = 100000,
  }) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.customers).insertOnConflictUpdate(
      CustomersCompanion.insert(
        id: customerId,
        branchId: branchId,
        name: 'Customer-$customerId',
        phone: '010${customerId.hashCode.abs()}',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.into(db.sales).insertOnConflictUpdate(
      SalesCompanion.insert(
        id: saleId,
        branchId: branchId,
        shortRef: 'S-${saleId.hashCode.abs()}',
        cashierId: 'c1',
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuthLocalDataSource()..setUser(adminUser);
    txWriter = TxWriter(db);
    branchProvider = BranchProvider(db);
    gate = FeatureGate(db, auth, txWriter, branchProvider);
    pinService = ManagerPinService(db, txWriter, branchProvider, auth, gate);

    // Setup manager PIN
    await pinService.setPin(pin: managerPin, userId: adminId);

    // Enable installments feature by default for functional tests
    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: adminId);

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

  // ===========================================================================
  // Group 1: Plan CRUD (8 tests)
  // ===========================================================================
  group('Plan CRUD', () {
    test('1. createPlan creates active plan in DB with UUID and audit log (admin)', () async {
      final res = await facade.createPlan(
        name: '6 Months Plan',
        description: 'Standard plan',
        durationMonths: 6,
        downPaymentPiasters: 10000,
        interestBp: 500,
      );

      expect(res.isRight(), isTrue);
      final plan = res.getOrElse(() => throw Exception());
      expect(plan.name, '6 Months Plan');
      expect(plan.durationMonths, 6);
      expect(plan.downPaymentPiasters, 10000);
      expect(plan.interestBp, 500);
      expect(plan.isActive, isTrue);

      final row = await (db.select(db.installmentPlans)..where((t) => t.id.equals(plan.id))).getSingle();
      expect(row.name, '6 Months Plan');

      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('installment_plan_created'))).get();
      expect(audit.length, 1);
      expect(audit.first.entityId, plan.id);
    });

    test('2. createPlan is blocked when feature.installments disabled (FeatureDisabledFailure)', () async {
      await gate.setFeatureEnabled(FeatureKeys.installments, false, userId: adminId);

      final res = await facade.createPlan(
        name: 'Plan',
        durationMonths: 6,
        downPaymentPiasters: 0,
        interestBp: 0,
      );

      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f, isA<FeatureDisabledFailure>()), (_) => fail('must fail'));
    });

    test('3. createPlan is blocked for cashier at domain level (AuthFailure)', () async {
      auth.setUser(cashierUser);

      final res = await facade.createPlan(
        name: 'Cashier Plan',
        durationMonths: 6,
        downPaymentPiasters: 0,
        interestBp: 0,
      );

      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f, isA<AuthFailure>()), (_) => fail('must fail'));
    });

    test('4. createPlan validation fails on empty name, invalid duration, or negative down payment', () async {
      final r1 = await facade.createPlan(name: '  ', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      expect(r1.isLeft(), isTrue);

      final r2 = await facade.createPlan(name: 'Valid', durationMonths: 0, downPaymentPiasters: 0, interestBp: 0);
      expect(r2.isLeft(), isTrue);

      final r3 = await facade.createPlan(name: 'Valid', durationMonths: 121, downPaymentPiasters: 0, interestBp: 0);
      expect(r3.isLeft(), isTrue);

      final r4 = await facade.createPlan(name: 'Valid', durationMonths: 6, downPaymentPiasters: -1, interestBp: 0);
      expect(r4.isLeft(), isTrue);

      final r5 = await facade.createPlan(name: 'Valid', durationMonths: 6, downPaymentPiasters: 0, interestBp: 10001);
      expect(r5.isLeft(), isTrue);
    });

    test('5. listPlans returns all non-deleted plans ordered by createdAt desc', () async {
      await facade.createPlan(name: 'Plan A', durationMonths: 3, downPaymentPiasters: 0, interestBp: 0);
      await facade.createPlan(name: 'Plan B', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);

      final res = await facade.listPlans();
      expect(res.isRight(), isTrue);
      final list = res.getOrElse(() => []);
      expect(list.length, 2);
    });

    test('6. updatePlan updates plan details and writes audit log when no contracts linked', () async {
      final createRes = await facade.createPlan(name: 'Old Name', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      final plan = createRes.getOrElse(() => throw Exception());

      final updatedPlan = InstallmentPlanEntity(
        id: plan.id,
        branchId: plan.branchId,
        name: 'New Name',
        durationMonths: 12,
        downPaymentPiasters: 5000,
        interestBp: 200,
        isActive: true,
        createdAt: plan.createdAt,
        updatedAt: plan.updatedAt,
      );

      final res = await facade.updatePlan(updatedPlan);
      expect(res.isRight(), isTrue);

      final row = await (db.select(db.installmentPlans)..where((t) => t.id.equals(plan.id))).getSingle();
      expect(row.name, 'New Name');
      expect(row.durationMonths, 12);

      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('installment_plan_updated'))).get();
      expect(audit.length, 1);
    });

    test('6b. updatePlan is blocked for cashier at domain level (AuthFailure)', () async {
      final createRes = await facade.createPlan(name: 'Admin Plan', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      final plan = createRes.getOrElse(() => throw Exception());

      auth.setUser(cashierUser);

      final res = await facade.updatePlan(plan);
      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f, isA<AuthFailure>()), (_) => fail('must fail for cashier'));
    });

    test('7. updatePlan is rejected when active contracts are linked to plan', () async {
      await seedSaleAndCustomer(saleId: 's-plan', customerId: 'c-plan');
      final createRes = await facade.createPlan(name: 'Linked Plan', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      final plan = createRes.getOrElse(() => throw Exception());

      // Create contract linked to this plan
      await facade.createContract(
        saleId: 's-plan',
        customerId: 'c-plan',
        planId: plan.id,
        totalPiasters: 100000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );

      final updatedPlan = InstallmentPlanEntity(
        id: plan.id,
        branchId: plan.branchId,
        name: 'Attempted Update',
        durationMonths: 6,
        downPaymentPiasters: 0,
        interestBp: 0,
        isActive: true,
        createdAt: plan.createdAt,
        updatedAt: plan.updatedAt,
      );

      final res = await facade.updatePlan(updatedPlan);
      expect(res.isLeft(), isTrue);
      res.fold(
        (f) => expect(f.message, contains('لا يمكن تعديل الخطة لوجود عقود مرتبطة بها')),
        (_) => fail('must fail when contracts linked'),
      );
    });

    test('8. deactivatePlan sets isActive to false and writes audit log', () async {
      final createRes = await facade.createPlan(name: 'To Deactivate', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      final plan = createRes.getOrElse(() => throw Exception());

      final res = await facade.deactivatePlan(plan.id);
      expect(res.isRight(), isTrue);

      final row = await (db.select(db.installmentPlans)..where((t) => t.id.equals(plan.id))).getSingle();
      expect(row.isActive, isFalse);

      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('installment_plan_deactivated'))).get();
      expect(audit.length, 1);
    });

    test('8b. deactivatePlan is blocked for cashier at domain level (AuthFailure)', () async {
      final createRes = await facade.createPlan(name: 'Admin Plan 2', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      final plan = createRes.getOrElse(() => throw Exception());

      auth.setUser(cashierUser);

      final res = await facade.deactivatePlan(plan.id);
      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f, isA<AuthFailure>()), (_) => fail('must fail for cashier'));
    });
  });

  // ===========================================================================
  // Group 2: Contract Creation (6 tests)
  // ===========================================================================
  group('Contract Creation', () {
    test('9. createContract creates contract without down payment and calculates schedule + interest', () async {
      await seedSaleAndCustomer(saleId: 's-no-down', customerId: 'c-no-down');

      final res = await facade.createContract(
        saleId: 's-no-down',
        customerId: 'c-no-down',
        totalPiasters: 100000,
        downPaymentPiasters: 0,
        interestBp: 1000, // 10%
        interestModel: InstallmentInterestModel.percentTotal,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );

      expect(res.isRight(), isTrue);
      final contract = res.getOrElse(() => throw Exception());
      expect(contract.totalPiasters, 100000);
      expect(contract.downPaymentPiasters, 0);
      expect(contract.principalPiasters, 100000);
      expect(contract.remainingPiasters, 110000); // 100,000 + 10,000 interest
      expect(contract.status, 'active');

      final payments = await (db.select(db.installmentPayments)..where((t) => t.customerInstallmentId.equals(contract.id))).get();
      expect(payments.isEmpty, isTrue, reason: 'no payment row when downPayment == 0');

      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('installment_contract_created'))).get();
      expect(audit.length, 1);
    });

    test('10. createContract creates contract with down payment and atomically records payment row in single tx', () async {
      await seedSaleAndCustomer(saleId: 's-with-down', customerId: 'c-with-down');

      final res = await facade.createContract(
        saleId: 's-with-down',
        customerId: 'c-with-down',
        totalPiasters: 100000,
        downPaymentPiasters: 20000,
        interestBp: 1000, // 10%
        interestModel: InstallmentInterestModel.percentTotal,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );

      expect(res.isRight(), isTrue);
      final contract = res.getOrElse(() => throw Exception());
      expect(contract.totalPiasters, 100000);
      expect(contract.downPaymentPiasters, 20000);
      expect(contract.principalPiasters, 80000); // 100,000 - 20,000
      // For percentTotal: 10% of total 100,000 = 10,000 interest. Financed = 80,000. Remaining = 90,000
      expect(contract.remainingPiasters, 90000);

      // Verify down payment row was recorded atomically
      final payments = await (db.select(db.installmentPayments)..where((t) => t.customerInstallmentId.equals(contract.id))).get();
      expect(payments.length, 1);
      expect(payments.first.amountPiasters, 20000);
      expect(payments.first.receiptNumber, 'DOWN_PAYMENT');
      expect(payments.first.paymentMethod, 'cash');
    });

    test('11. createContract fails when saleId does not exist', () async {
      await seedSaleAndCustomer(saleId: 's-real', customerId: 'c-real');

      final res = await facade.createContract(
        saleId: 's-nonexistent',
        customerId: 'c-real',
        totalPiasters: 100000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );

      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f.message, contains('الفاتورة غير موجودة')), (_) => fail('must fail'));
    });

    test('12. createContract fails when manager PIN is wrong', () async {
      await seedSaleAndCustomer(saleId: 's-pin-fail', customerId: 'c-pin-fail');

      final res = await facade.createContract(
        saleId: 's-pin-fail',
        customerId: 'c-pin-fail',
        totalPiasters: 100000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: start,
        pin: 'wrong_pin',
      );

      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f, isA<AuthFailure>()), (_) => fail('must fail'));
    });

    test('13. createContract supports all 3 interest models (fixed, percentTotal, percentMonthly)', () async {
      await seedSaleAndCustomer(saleId: 's-m1', customerId: 'c-m1');
      await seedSaleAndCustomer(saleId: 's-m2', customerId: 'c-m2');
      await seedSaleAndCustomer(saleId: 's-m3', customerId: 'c-m3');

      // 1. Fixed interest model
      final rFixed = await facade.createContract(
        saleId: 's-m1',
        customerId: 'c-m1',
        totalPiasters: 100000,
        downPaymentPiasters: 20000,
        interestBp: 5000, // 5000 piasters fixed
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 5,
        startDate: start,
        pin: managerPin,
      );
      expect(rFixed.isRight(), isTrue);
      expect(rFixed.getOrElse(() => throw Exception()).remainingPiasters, 85000); // 80000 + 5000

      // 2. PercentTotal model (1000 bp = 10% on 100,000 = 10,000)
      final rTotal = await facade.createContract(
        saleId: 's-m2',
        customerId: 'c-m2',
        totalPiasters: 100000,
        downPaymentPiasters: 20000,
        interestBp: 1000,
        interestModel: InstallmentInterestModel.percentTotal,
        durationMonths: 5,
        startDate: start,
        pin: managerPin,
      );
      expect(rTotal.isRight(), isTrue);
      expect(rTotal.getOrElse(() => throw Exception()).remainingPiasters, 90000); // 80000 + 10000

      // 3. PercentMonthly model (100 bp = 1%/month on 80,000 for 5 months = 4,000)
      final rMonthly = await facade.createContract(
        saleId: 's-m3',
        customerId: 'c-m3',
        totalPiasters: 100000,
        downPaymentPiasters: 20000,
        interestBp: 100,
        interestModel: InstallmentInterestModel.percentMonthly,
        durationMonths: 5,
        startDate: start,
        pin: managerPin,
      );
      expect(rMonthly.isRight(), isTrue);
      expect(rMonthly.getOrElse(() => throw Exception()).remainingPiasters, 84000); // 80000 + 4000
    });

    test('14. cashier can create contract when valid manager PIN is provided', () async {
      await seedSaleAndCustomer(saleId: 's-cashier', customerId: 'c-cashier');
      auth.setUser(cashierUser);

      final res = await facade.createContract(
        saleId: 's-cashier',
        customerId: 'c-cashier',
        totalPiasters: 50000,
        downPaymentPiasters: 10000,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 4,
        startDate: start,
        pin: managerPin, // Cashier enters correct manager PIN
      );

      expect(res.isRight(), isTrue);
      final contract = res.getOrElse(() => throw Exception());
      expect(contract.createdBy, cashierId);
    });

    test('14b. createContract fails with ValidationFailure when sale already has an active contract', () async {
      await seedSaleAndCustomer(saleId: 's-duplicate', customerId: 'c-duplicate');

      final r1 = await facade.createContract(
        saleId: 's-duplicate',
        customerId: 'c-duplicate',
        totalPiasters: 50000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );
      expect(r1.isRight(), isTrue);

      // Attempt second contract on the same sale
      final r2 = await facade.createContract(
        saleId: 's-duplicate',
        customerId: 'c-duplicate',
        totalPiasters: 50000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );
      expect(r2.isLeft(), isTrue);
      r2.fold(
        (f) {
          expect(f, isA<ValidationFailure>());
          expect(f.message, 'sale_already_has_contract');
        },
        (_) => fail('must fail with ValidationFailure'),
      );
    });

    test('14c. createContract: TxWriter rollback on mid-transaction failure (atomicity)', () async {
      await seedSaleAndCustomer(saleId: 's-rollback', customerId: 'c-rollback');

      // TxWriter call #1 is ManagerPinService.verifyPin audit
      // TxWriter call #2 is createContract itself (contract + payment insertion)
      // Force failure during call #2 inside the Drift transaction
      txWriter.resetCallCount();
      txWriter.debugOnBeforeWrite = (callNumber) async {
        if (callNumber == 2) {
          throw Exception('simulated mid-transaction failure');
        }
      };
      addTearDown(() => txWriter.debugOnBeforeWrite = null);

      final result = await facade.createContract(
        saleId: 's-rollback',
        customerId: 'c-rollback',
        totalPiasters: 10000,
        downPaymentPiasters: 2000, // forces 2 inserts: contract + payment
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: start,
        pin: managerPin,
      );

      expect(result.isLeft(), isTrue,
          reason: 'Must fail because beforeAuditWrite throws');

      // Atomicity proof: NOTHING was written
      final contracts = await (db.select(db.customerInstallments)
            ..where((t) => t.saleId.equals('s-rollback')))
          .get();
      expect(contracts, isEmpty,
          reason: 'Contract row must roll back');

      final payments = await db.select(db.installmentPayments).get();
      expect(payments, isEmpty,
          reason: 'Payment row must roll back');

      final audits = await (db.select(db.auditLogs)
            ..where((t) => t.action.equals('installment_contract_created')))
          .get();
      expect(audits, isEmpty,
          reason: 'Audit row must roll back');

      final syncs = await (db.select(db.syncQueue)
            ..where((t) => t.entity.equals('customer_installments')))
          .get();
      expect(syncs, isEmpty,
          reason: 'Sync queue row must roll back');
    });
  });

  // ===========================================================================
  // Group 3: Payment Recording (4 tests)
  // ===========================================================================
  group('Payment Recording', () {
    test('15. recordPayment records payment, decreases remainingPiasters, and writes audit log', () async {
      await seedSaleAndCustomer(saleId: 's-pay1', customerId: 'c-pay1');
      final cRes = await facade.createContract(
        saleId: 's-pay1',
        customerId: 'c-pay1',
        totalPiasters: 100000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 5,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      final pRes = await facade.recordPayment(
        contractId: contract.id,
        amountPiasters: 25000,
        paymentMethod: 'cash',
        receiptNumber: 'REC-001',
        notes: 'First installment',
        pin: managerPin,
      );

      expect(pRes.isRight(), isTrue);
      final payment = pRes.getOrElse(() => throw Exception());
      expect(payment.amountPiasters, 25000);
      expect(payment.receiptNumber, 'REC-001');

      final updatedContract = await (db.select(db.customerInstallments)..where((t) => t.id.equals(contract.id))).getSingle();
      expect(updatedContract.remainingPiasters, 75000);
      expect(updatedContract.status, 'active');

      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('installment_payment_recorded'))).get();
      expect(audit.length, 1);
    });

    test('16. recordPayment marks contract completed when remaining reaches zero', () async {
      await seedSaleAndCustomer(saleId: 's-pay2', customerId: 'c-pay2');
      final cRes = await facade.createContract(
        saleId: 's-pay2',
        customerId: 'c-pay2',
        totalPiasters: 20000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 2,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      final pRes = await facade.recordPayment(
        contractId: contract.id,
        amountPiasters: 20000,
        paymentMethod: 'card',
        pin: managerPin,
      );

      expect(pRes.isRight(), isTrue);
      final updatedContract = await (db.select(db.customerInstallments)..where((t) => t.id.equals(contract.id))).getSingle();
      expect(updatedContract.remainingPiasters, 0);
      expect(updatedContract.status, 'completed');
    });

    test('17. recordPayment rejects overpayment exceeding remainingPiasters', () async {
      await seedSaleAndCustomer(saleId: 's-overpay', customerId: 'c-overpay');
      final cRes = await facade.createContract(
        saleId: 's-overpay',
        customerId: 'c-overpay',
        totalPiasters: 10000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 2,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      final pRes = await facade.recordPayment(
        contractId: contract.id,
        amountPiasters: 15000, // Exceeds 10,000 remaining
        paymentMethod: 'cash',
        pin: managerPin,
      );

      expect(pRes.isLeft(), isTrue);
      pRes.fold((f) => expect(f.message, contains('يتجاوز')), (_) => fail('must fail'));
    });

    test('18. recordPayment rejects payment on completed or cancelled contract', () async {
      await seedSaleAndCustomer(saleId: 's-comp-pay', customerId: 'c-comp-pay');
      final cRes = await facade.createContract(
        saleId: 's-comp-pay',
        customerId: 'c-comp-pay',
        totalPiasters: 10000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 2,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      // Pay off fully
      await facade.recordPayment(contractId: contract.id, amountPiasters: 10000, paymentMethod: 'cash', pin: managerPin);

      // Attempt another payment on completed contract
      final pRes = await facade.recordPayment(
        contractId: contract.id,
        amountPiasters: 1000,
        paymentMethod: 'cash',
        pin: managerPin,
      );
      expect(pRes.isLeft(), isTrue);
      pRes.fold((f) => expect(f.message, contains('مكتمل')), (_) => fail('must fail'));
    });
  });

  // ===========================================================================
  // Group 4: Cancellation (3 tests)
  // ===========================================================================
  group('Cancellation', () {
    test('19. cancelContract cancels active contract and updates status with audit log (admin)', () async {
      await seedSaleAndCustomer(saleId: 's-cancel', customerId: 'c-cancel');
      final cRes = await facade.createContract(
        saleId: 's-cancel',
        customerId: 'c-cancel',
        totalPiasters: 50000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 5,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      final res = await facade.cancelContract(contractId: contract.id, pin: managerPin);
      expect(res.isRight(), isTrue);

      final row = await (db.select(db.customerInstallments)..where((t) => t.id.equals(contract.id))).getSingle();
      expect(row.status, 'cancelled');

      final audit = await (db.select(db.auditLogs)..where((t) => t.action.equals('installment_contract_cancelled'))).get();
      expect(audit.length, 1);
    });

    test('20. cancelContract is blocked for cashier at domain level (AuthFailure)', () async {
      await seedSaleAndCustomer(saleId: 's-c-cashier', customerId: 'c-c-cashier');
      final cRes = await facade.createContract(
        saleId: 's-c-cashier',
        customerId: 'c-c-cashier',
        totalPiasters: 50000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 5,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      auth.setUser(cashierUser);

      final res = await facade.cancelContract(contractId: contract.id, pin: managerPin);
      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f, isA<AuthFailure>()), (_) => fail('must fail'));
    });

    test('21. cancelContract rejects cancelling an already completed contract', () async {
      await seedSaleAndCustomer(saleId: 's-c-done', customerId: 'c-c-done');
      final cRes = await facade.createContract(
        saleId: 's-c-done',
        customerId: 'c-c-done',
        totalPiasters: 10000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 2,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      // Pay off fully
      await facade.recordPayment(contractId: contract.id, amountPiasters: 10000, paymentMethod: 'cash', pin: managerPin);

      final res = await facade.cancelContract(contractId: contract.id, pin: managerPin);
      expect(res.isLeft(), isTrue);
      res.fold((f) => expect(f.message, contains('مكتمل')), (_) => fail('must fail'));
    });
  });

  // ===========================================================================
  // Group 5: Overdue & Reads (1 test)
  // ===========================================================================
  group('Overdue & Reads', () {
    test('22. listOverdueContracts returns only overdue active contracts based on statusAt(now)', () async {
      await seedSaleAndCustomer(saleId: 's-overdue1', customerId: 'c-overdue1');
      await seedSaleAndCustomer(saleId: 's-future', customerId: 'c-future');
      await seedSaleAndCustomer(saleId: 's-past-paid', customerId: 'c-past-paid');

      // 1. Contract with past endDate and remaining balance -> Overdue!
      await facade.createContract(
        saleId: 's-overdue1',
        customerId: 'c-overdue1',
        totalPiasters: 50000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 2,
        startDate: DateTime(2020, 1, 1), // in past
        pin: managerPin,
      );

      // 2. Contract with future endDate -> Active, not overdue
      await facade.createContract(
        saleId: 's-future',
        customerId: 'c-future',
        totalPiasters: 50000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 12,
        startDate: DateTime.now(), // in future
        pin: managerPin,
      );

      // 3. Contract with past endDate but completed -> Completed, not overdue
      final c3Res = await facade.createContract(
        saleId: 's-past-paid',
        customerId: 'c-past-paid',
        totalPiasters: 10000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 1,
        startDate: DateTime(2020, 1, 1),
        pin: managerPin,
      );
      final c3 = c3Res.getOrElse(() => throw Exception());
      await facade.recordPayment(contractId: c3.id, amountPiasters: 10000, paymentMethod: 'cash', pin: managerPin);

      // Call listOverdueContracts
      final overdueRes = await facade.listOverdueContracts();
      expect(overdueRes.isRight(), isTrue);
      final overdueList = overdueRes.getOrElse(() => []);

      expect(overdueList.length, 1);
      expect(overdueList.first.saleId, 's-overdue1');
    });

    test('23. getSummary calculates totalOutstanding, monthlyCollected, overdueTotal, and overdueCount', () async {
      final now = DateTime.now();
      await seedSaleAndCustomer(saleId: 's-sum1', customerId: 'c-sum1');
      await seedSaleAndCustomer(saleId: 's-sum2', customerId: 'c-sum2');

      // Contract 1: active, remaining 30000, 10000 down paid this month
      await facade.createContract(
        saleId: 's-sum1',
        customerId: 'c-sum1',
        totalPiasters: 40000,
        downPaymentPiasters: 10000,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: now,
        pin: managerPin,
      );

      // Contract 2: overdue, remaining 20000, no down payment
      final pastDate = DateTime(now.year, now.month - 4, 1);
      await facade.createContract(
        saleId: 's-sum2',
        customerId: 'c-sum2',
        totalPiasters: 20000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 2,
        startDate: pastDate,
        pin: managerPin,
      );

      final summaryRes = await facade.getSummary();
      expect(summaryRes.isRight(), isTrue);
      final summary = summaryRes.getOrElse(() => throw Exception());
      expect(summary, isA<InstallmentSummary>());

      expect(summary.totalOutstanding, 50000); // 30000 + 20000
      expect(summary.monthlyCollected, 10000); // down payment on s-sum1
      expect(summary.overdueTotal, 20000);
      expect(summary.overdueCount, 1);
    });
  });

  // ===========================================================================
  // Group 6: FeatureGate per-method enforcement (Blocker 1)
  // ===========================================================================
  group('FeatureGate per-method enforcement', () {
    final existingPlan = InstallmentPlanEntity(
      id: 'plan-gate',
      branchId: branchId,
      name: 'Gate Plan',
      durationMonths: 6,
      downPaymentPiasters: 0,
      interestBp: 0,
      isActive: true,
      createdAt: start,
      updatedAt: start,
    );

    final gatedMethods = <String, Future<Either<Failure, dynamic>> Function()>{
      'updatePlan': () => facade.updatePlan(existingPlan),
      'deactivatePlan': () => facade.deactivatePlan('plan-gate'),
      'createContract': () => facade.createContract(
            saleId: 's1',
            customerId: 'c1',
            totalPiasters: 1000,
            downPaymentPiasters: 0,
            interestBp: 0,
            interestModel: InstallmentInterestModel.fixed,
            durationMonths: 6,
            startDate: start,
            pin: managerPin,
          ),
      'cancelContract': () => facade.cancelContract(contractId: 'c1', pin: managerPin),
      'recordPayment': () => facade.recordPayment(
            contractId: 'c1',
            amountPiasters: 100,
            paymentMethod: 'cash',
            pin: managerPin,
          ),
    };

    for (final entry in gatedMethods.entries) {
      test('${entry.key} is gated when feature.installments disabled', () async {
        await gate.setFeatureEnabled(FeatureKeys.installments, false, userId: adminId);
        final result = await entry.value();
        expect(result.isLeft(), isTrue, reason: '${entry.key} must return Left when feature disabled');
        result.fold(
          (f) => expect(f, isA<FeatureDisabledFailure>(), reason: '${entry.key} must fail with FeatureDisabledFailure'),
          (_) => fail('${entry.key} must not succeed when feature disabled'),
        );
      });
    }

    test('ungated read methods bypass feature gate when feature.installments disabled', () async {
      await gate.setFeatureEnabled(FeatureKeys.installments, false, userId: adminId);

      final r1 = await facade.listPlans();
      expect(r1.isRight(), isTrue, reason: 'listPlans must bypass gate');

      final r2 = await facade.listContracts();
      expect(r2.isRight(), isTrue, reason: 'listContracts must bypass gate');

      final r3 = await facade.listOverdueContracts();
      expect(r3.isRight(), isTrue, reason: 'listOverdueContracts must bypass gate');

      final r4 = await facade.listPayments('some-contract');
      expect(r4.isRight(), isTrue, reason: 'listPayments must bypass gate');

      final r5 = facade.calculateSchedule(
        principalPiasters: 1000,
        durationMonths: 6,
        interestModel: InstallmentInterestModel.fixed,
        interestValue: 0,
        downPaymentPiasters: 0,
        startDate: start,
      );
      expect(r5.isRight(), isTrue, reason: 'calculateSchedule must bypass gate');

      final r6 = await facade.getSummary();
      expect(r6.isRight(), isTrue, reason: 'getSummary must bypass gate');
    });
  });

  // ===========================================================================
  // Group 7: Read queries & sync queue
  // ===========================================================================
  group('Read queries & sync queue', () {
    test('getContract returns contract when found, and ServerFailure when not found', () async {
      await seedSaleAndCustomer(saleId: 's-get', customerId: 'c-get');
      final cRes = await facade.createContract(
        saleId: 's-get',
        customerId: 'c-get',
        totalPiasters: 10000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 3,
        startDate: start,
        pin: managerPin,
      );
      final contract = cRes.getOrElse(() => throw Exception());

      final found = await facade.getContract(contract.id);
      expect(found.isRight(), isTrue);
      expect(found.getOrElse(() => throw Exception()).id, contract.id);

      final notFound = await facade.getContract('non-existent-id');
      expect(notFound.isLeft(), isTrue);
      notFound.fold((f) => expect(f.message, contains('غير موجود')), (_) => fail('must fail'));
    });

    test('listContracts filters by customerId, status, and date range', () async {
      await seedSaleAndCustomer(saleId: 's-filter1', customerId: 'c-cust1');
      await seedSaleAndCustomer(saleId: 's-filter2', customerId: 'c-cust2');

      final c1 = (await facade.createContract(
        saleId: 's-filter1',
        customerId: 'c-cust1',
        totalPiasters: 10000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 3,
        startDate: DateTime(2026, 1, 1),
        pin: managerPin,
      )).getOrElse(() => throw Exception());

      final c2 = (await facade.createContract(
        saleId: 's-filter2',
        customerId: 'c-cust2',
        totalPiasters: 20000,
        downPaymentPiasters: 0,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 6,
        startDate: DateTime(2026, 6, 1),
        pin: managerPin,
      )).getOrElse(() => throw Exception());

      // Filter by customerId
      final byCustomer = await facade.listContracts(customerId: 'c-cust1');
      expect(byCustomer.isRight(), isTrue);
      expect(byCustomer.getOrElse(() => []).length, 1);
      expect(byCustomer.getOrElse(() => []).first.id, c1.id);

      // Filter by date range
      final byDate = await facade.listContracts(fromDate: DateTime(2026, 5, 1));
      expect(byDate.isRight(), isTrue);
      expect(byDate.getOrElse(() => []).length, 1);
      expect(byDate.getOrElse(() => []).first.id, c2.id);
    });

    test('listPayments returns payment history ordered by paidAt asc', () async {
      await seedSaleAndCustomer(saleId: 's-pay-hist', customerId: 'c-pay-hist');
      final c = (await facade.createContract(
        saleId: 's-pay-hist',
        customerId: 'c-pay-hist',
        totalPiasters: 30000,
        downPaymentPiasters: 5000, // Down payment creates 1st payment row
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 3,
        startDate: start,
        pin: managerPin,
      )).getOrElse(() => throw Exception());

      await facade.recordPayment(
        contractId: c.id,
        amountPiasters: 10000,
        paymentMethod: 'cash',
        receiptNumber: 'REC-01',
        pin: managerPin,
      );

      final paymentsRes = await facade.listPayments(c.id);
      expect(paymentsRes.isRight(), isTrue);
      final payments = paymentsRes.getOrElse(() => []);
      expect(payments.length, 2);
      expect(payments[0].receiptNumber, 'DOWN_PAYMENT');
      expect(payments[1].receiptNumber, 'REC-01');
    });

    test('all mutations write to sync_queue via TxWriter', () async {
      final syncRowsBefore = await db.select(db.syncQueue).get();
      final beforeCount = syncRowsBefore.length;

      // 1. Plan mutation
      final planRes = await facade.createPlan(name: 'Sync Plan', durationMonths: 6, downPaymentPiasters: 0, interestBp: 0);
      final plan = planRes.getOrElse(() => throw Exception());

      // 2. Contract mutation
      await seedSaleAndCustomer(saleId: 's-sync', customerId: 'c-sync');
      final contractRes = await facade.createContract(
        saleId: 's-sync',
        customerId: 'c-sync',
        planId: plan.id,
        totalPiasters: 20000,
        downPaymentPiasters: 5000,
        interestBp: 0,
        interestModel: InstallmentInterestModel.fixed,
        durationMonths: 3,
        startDate: start,
        pin: managerPin,
      );
      final contract = contractRes.getOrElse(() => throw Exception());

      // 3. Payment mutation
      await facade.recordPayment(contractId: contract.id, amountPiasters: 5000, paymentMethod: 'cash', pin: managerPin);

      // 4. Cancel mutation
      await facade.cancelContract(contractId: contract.id, pin: managerPin);

      final syncRowsAfter = await db.select(db.syncQueue).get();
      expect(syncRowsAfter.length, greaterThan(beforeCount), reason: 'Every mutation must append to sync_queue');
      final entities = syncRowsAfter.map((r) => r.entity).toSet();
      expect(entities.contains('installment_plans'), isTrue);
      expect(entities.contains('customer_installments'), isTrue);
      expect(entities.contains('installment_payments'), isTrue);
    });
  });
}
