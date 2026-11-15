import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../pos/domain/entities/payment_split.dart';
import '../services/manager_pin_service.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/installment_payment_entity.dart';
import '../../domain/entities/installment_plan_entity.dart';
import '../../domain/entities/installment_schedule_entry.dart';
import '../../domain/entities/installment_summary.dart';
import '../../domain/facades/installments_facade.dart';
import '../../domain/services/installment_calculator.dart';

@LazySingleton(as: InstallmentsFacade)
class InstallmentsFacadeImpl implements InstallmentsFacade {
  final AppDatabase _db;
  final TxWriter _txWriter;
  final BranchProvider _branchProvider;
  final AuthLocalDataSource _auth;
  final FeatureGate _featureGate;
  final ManagerPinService _pinService;

  InstallmentsFacadeImpl(
    this._db,
    this._txWriter,
    this._branchProvider,
    this._auth,
    this._featureGate,
    this._pinService,
  );

  // ---------------------------------------------------------------------------
  // Plans
  // ---------------------------------------------------------------------------

  @override
  Future<Either<Failure, InstallmentPlanEntity>> createPlan({
    required String name,
    String? description,
    required int durationMonths,
    required int downPaymentPiasters,
    required int interestBp,
  }) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }
    if (!await _featureGate.isCurrentUserAdmin()) {
      return const Left(AuthFailure('غير مصرح: إدارة خطط التقسيط متاحة للمدير فقط'));
    }
    if (name.trim().isEmpty) {
      return const Left(ServerFailure('اسم الخطة مطلوب'));
    }
    if (durationMonths < 1 || durationMonths > 120) {
      return const Left(ServerFailure('مدة الخطة يجب أن تكون بين شهر و 120 شهراً'));
    }
    if (downPaymentPiasters < 0) {
      return const Left(ServerFailure('الدفعة المقدمة لا يمكن أن تكون سالبة'));
    }
    if (interestBp < 0 || interestBp > 10000) {
      return const Left(ServerFailure('نسبة الفائدة غير صالحة'));
    }

    final planId = const Uuid().v4();
    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'admin';
    final now = DateTime.now();

    final plan = InstallmentPlanEntity(
      id: planId,
      branchId: branchId,
      name: name.trim(),
      description: description,
      durationMonths: durationMonths,
      downPaymentPiasters: downPaymentPiasters,
      interestBp: interestBp,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    await _txWriter.write(
      writeFn: () async {
        await _db.into(_db.installmentPlans).insert(
          InstallmentPlansCompanion.insert(
            id: planId,
            branchId: branchId,
            name: name.trim(),
            description: Value(description),
            durationMonths: durationMonths,
            downPaymentPiasters: Value(downPaymentPiasters),
            interestBp: Value(interestBp),
            isActive: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
      },
      branchId: branchId,
      entity: 'installment_plans',
      entityId: planId,
      operation: 'create',
      userId: userId,
      oldValue: null,
      newValue: 'active',
      auditAction: 'installment_plan_created',
      payload: jsonEncode({
        'id': planId,
        'name': name.trim(),
        'durationMonths': durationMonths,
        'downPaymentPiasters': downPaymentPiasters,
        'interestBp': interestBp,
      }),
    );

    return Right(plan);
  }

  @override
  Future<Either<Failure, List<InstallmentPlanEntity>>> listPlans() async {
    final rows = await (_db.select(_db.installmentPlans)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .get();
    return Right(rows.map(_mapPlan).toList());
  }

  @override
  Future<Either<Failure, Unit>> updatePlan(InstallmentPlanEntity plan) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }
    if (!await _featureGate.isCurrentUserAdmin()) {
      return const Left(AuthFailure('غير مصرح: تعديل خطط التقسيط متاح للمدير فقط'));
    }
    if (plan.name.trim().isEmpty) {
      return const Left(ServerFailure('اسم الخطة مطلوب'));
    }
    if (plan.durationMonths < 1 || plan.durationMonths > 120) {
      return const Left(ServerFailure('مدة الخطة يجب أن تكون بين شهر و 120 شهراً'));
    }

    final existing = await (_db.select(_db.installmentPlans)
      ..where((t) => t.id.equals(plan.id) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (existing == null) {
      return const Left(ServerFailure('الخطة غير موجودة'));
    }

    // Check if any contract is linked to this plan
    final linkedContracts = await (_db.select(_db.customerInstallments)
      ..where((t) => t.planId.equals(plan.id) & t.deletedAt.isNull()))
      .get();
    if (linkedContracts.isNotEmpty) {
      return const Left(ServerFailure('لا يمكن تعديل الخطة لوجود عقود مرتبطة بها'));
    }

    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'admin';
    final now = DateTime.now();

    await _txWriter.write(
      writeFn: () async {
        await (_db.update(_db.installmentPlans)..where((t) => t.id.equals(plan.id))).write(
          InstallmentPlansCompanion(
            name: Value(plan.name.trim()),
            description: Value(plan.description),
            durationMonths: Value(plan.durationMonths),
            downPaymentPiasters: Value(plan.downPaymentPiasters),
            interestBp: Value(plan.interestBp),
            isActive: Value(plan.isActive),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'installment_plans',
      entityId: plan.id,
      operation: 'update',
      userId: userId,
      oldValue: existing.name,
      newValue: plan.name.trim(),
      auditAction: 'installment_plan_updated',
      payload: jsonEncode({
        'id': plan.id,
        'name': plan.name.trim(),
        'durationMonths': plan.durationMonths,
      }),
    );

    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> deactivatePlan(String planId) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }
    if (!await _featureGate.isCurrentUserAdmin()) {
      return const Left(AuthFailure('غير مصرح: تعطيل خطط التقسيط متاح للمدير فقط'));
    }

    final existing = await (_db.select(_db.installmentPlans)
      ..where((t) => t.id.equals(planId) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (existing == null) {
      return const Left(ServerFailure('الخطة غير موجودة'));
    }

    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'admin';
    final now = DateTime.now();

    await _txWriter.write(
      writeFn: () async {
        await (_db.update(_db.installmentPlans)..where((t) => t.id.equals(planId))).write(
          InstallmentPlansCompanion(
            isActive: const Value(false),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'installment_plans',
      entityId: planId,
      operation: 'update',
      userId: userId,
      oldValue: 'active',
      newValue: 'inactive',
      auditAction: 'installment_plan_deactivated',
      payload: jsonEncode({'id': planId, 'isActive': false}),
    );

    return const Right(unit);
  }

  // ---------------------------------------------------------------------------
  // Contracts
  // ---------------------------------------------------------------------------

  @override
  Future<Either<Failure, CustomerInstallmentEntity>> createContract({
    required String saleId,
    required String customerId,
    String? planId,
    required int totalPiasters,
    required int downPaymentPiasters,
    required int interestBp,
    required InstallmentInterestModel interestModel,
    required int durationMonths,
    required DateTime startDate,
    required String pin,
    List<PaymentSplit>? downPaymentSplits,
  }) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }

    // PIN Verification
    final pinResult = await _pinService.verifyPin(pin: pin, operation: 'create_contract');
    if (!pinResult.ok) {
      return Left(AuthFailure(pinResult.error ?? 'الرقم السري للمدير غير صحيح'));
    }

    if (totalPiasters <= 0) {
      return const Left(ServerFailure('إجمالي المبلغ يجب أن يكون أكبر من صفر'));
    }
    if (downPaymentPiasters < 0) {
      return const Left(ServerFailure('الدفعة المقدمة لا يمكن أن تكون سالبة'));
    }
    if (downPaymentPiasters >= totalPiasters) {
      return const Left(ServerFailure('الدفعة المقدمة يجب أن تكون أقل من إجمالي المبلغ'));
    }
    if (durationMonths < 1 || durationMonths > 120) {
      return const Left(ServerFailure('مدة العقد يجب أن تكون بين شهر و 120 شهراً'));
    }
    if (interestBp < 0 || interestBp > 10000) {
      return const Left(ServerFailure('نسبة الفائدة غير صالحة'));
    }

    // Verify Sale exists
    final sale = await (_db.select(_db.sales)
      ..where((t) => t.id.equals(saleId) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (sale == null) {
      return const Left(ServerFailure('الفاتورة غير موجودة'));
    }

    // Double-installment prevention (sale already has a contract)
    final existingContract = await (_db.select(_db.customerInstallments)
          ..where((t) => t.saleId.equals(saleId) & t.deletedAt.isNull()))
        .getSingleOrNull();

    if (existingContract != null) {
      return const Left(ValidationFailure('sale_already_has_contract'));
    }

    // Verify Customer exists
    final customer = await (_db.select(_db.customers)
      ..where((t) => t.id.equals(customerId) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (customer == null) {
      return const Left(ServerFailure('العميل غير موجود'));
    }

    // If planId provided, verify it exists and is active
    if (planId != null) {
      final plan = await (_db.select(_db.installmentPlans)
        ..where((t) => t.id.equals(planId) & t.deletedAt.isNull()))
        .getSingleOrNull();
      if (plan == null || !plan.isActive) {
        return const Left(ServerFailure('خطة التقسيط غير صالحة أو غير مفعّلة'));
      }
    }

    // Calculate Schedule & Financials
    final scheduleResult = InstallmentCalculator.calculateSchedule(
      principalPiasters: totalPiasters,
      durationMonths: durationMonths,
      interestModel: interestModel,
      interestValue: interestBp,
      downPaymentPiasters: downPaymentPiasters,
      startDate: startDate,
    );
    if (scheduleResult.isLeft()) {
      return Left(scheduleResult.fold((f) => f, (_) => const ServerFailure('خطأ في حساب جدول الأقساط')));
    }
    final entries = scheduleResult.fold((_) => <InstallmentScheduleEntry>[], (e) => e);

    final financedPrincipal = totalPiasters - downPaymentPiasters;
    final totalInterest = entries.fold<int>(0, (s, e) => s + e.interestComponentPiasters);
    final monthlyAmount = entries.isNotEmpty ? entries.first.amountPiasters : (financedPrincipal ~/ durationMonths);
    final initialRemaining = financedPrincipal + totalInterest;
    final endDate = DateTime(startDate.year, startDate.month + durationMonths, startDate.day);

    final contractId = const Uuid().v4();
    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'unknown';
    final now = DateTime.now();

    final contract = CustomerInstallmentEntity(
      id: contractId,
      branchId: branchId,
      saleId: saleId,
      customerId: customerId,
      planId: planId,
      totalPiasters: totalPiasters,
      downPaymentPiasters: downPaymentPiasters,
      principalPiasters: financedPrincipal,
      interestBp: interestBp,
      monthlyAmountPiasters: monthlyAmount,
      remainingPiasters: initialRemaining,
      durationMonths: durationMonths,
      startDate: startDate,
      endDate: endDate,
      status: 'active',
      createdBy: userId,
      createdAt: now,
      updatedAt: now,
    );

    // Atomic transaction: contract + optional down payment
    try {
      await _txWriter.write(
        writeFn: () async {
          await _db.into(_db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: contractId,
              branchId: branchId,
              saleId: saleId,
              customerId: customerId,
              planId: Value(planId),
              totalPiasters: totalPiasters,
              downPaymentPiasters: Value(downPaymentPiasters),
              principalPiasters: financedPrincipal,
              interestBp: interestBp,
              monthlyAmountPiasters: monthlyAmount,
              remainingPiasters: initialRemaining,
              durationMonths: durationMonths,
              startDate: startDate,
              endDate: endDate,
              status: const Value('active'),
              createdBy: userId,
              createdAt: now,
              updatedAt: now,
            ),
          );

          if (downPaymentPiasters > 0) {
            final nowSec = now.millisecondsSinceEpoch ~/ 1000;
            final activeShift = await (_db.select(_db.shifts)
                  ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
                  ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
                  ..limit(1))
                .getSingleOrNull();

            final splits = (downPaymentSplits != null && downPaymentSplits.isNotEmpty)
                ? downPaymentSplits
                : [PaymentSplit(method: 'cash', amountPiasters: downPaymentPiasters)];

            for (final split in splits) {
              final spId = const Uuid().v4();
              await _db.into(_db.salePayments).insert(
                SalePaymentsCompanion.insert(
                  id: spId,
                  branchId: branchId,
                  saleId: saleId,
                  method: split.method,
                  amountPiasters: split.amountPiasters,
                  shiftId: Value(activeShift?.id),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );

              await _db.into(_db.cashMovements).insert(
                CashMovementsCompanion.insert(
                  id: const Uuid().v4(),
                  branchId: branchId,
                  shiftId: Value(activeShift?.id),
                  type: 'installment_down',
                  method: split.method,
                  direction: 'in',
                  amountPiasters: split.amountPiasters,
                  referenceId: Value(contractId),
                  notes: Value('مقدم عقد تقسيط (${split.method})'),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );
            }

            if (downPaymentSplits == null) {
              final paymentId = const Uuid().v4();
              await _db.into(_db.installmentPayments).insert(
                InstallmentPaymentsCompanion.insert(
                  id: paymentId,
                  branchId: branchId,
                  customerInstallmentId: contractId,
                  amountPiasters: downPaymentPiasters,
                  paymentMethod: 'cash',
                  paidAt: now,
                  receiptNumber: const Value('DOWN_PAYMENT'),
                  notes: const Value('دفعة مقدمة عند إنشاء العقد'),
                  recordedBy: userId,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
            }
          }
        },
        branchId: branchId,
        entity: 'customer_installments',
        entityId: contractId,
        operation: 'create',
        userId: userId,
        oldValue: null,
        newValue: 'active',
        auditAction: 'installment_contract_created',
        payload: jsonEncode({
          'contractId': contractId,
          'saleId': saleId,
          'customerId': customerId,
          'totalPiasters': totalPiasters,
          'downPaymentPiasters': downPaymentPiasters,
          'principalPiasters': financedPrincipal,
          'interestBp': interestBp,
          'interestModel': interestModel.name,
          'totalInterest': totalInterest,
          'remainingPiasters': initialRemaining,
          'durationMonths': durationMonths,
        }),
      );
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }

    return Right(contract);
  }

  @override
  Future<Either<Failure, CustomerInstallmentEntity>> getContract(String id) async {
    final row = await (_db.select(_db.customerInstallments)
      ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (row == null) {
      return const Left(ServerFailure('العقد غير موجود'));
    }
    return Right(_mapContract(row));
  }

  @override
  Future<Either<Failure, List<CustomerInstallmentEntity>>> listContracts({
    String? customerId,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var query = _db.select(_db.customerInstallments)..where((t) => t.deletedAt.isNull());
    if (customerId != null) {
      query = query..where((t) => t.customerId.equals(customerId));
    }
    if (status != null) {
      query = query..where((t) => t.status.equals(status));
    }
    if (fromDate != null) {
      query = query..where((t) => t.startDate.isBiggerOrEqualValue(fromDate));
    }
    if (toDate != null) {
      query = query..where((t) => t.startDate.isSmallerOrEqualValue(toDate));
    }
    final rows = await (query..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    return Right(rows.map(_mapContract).toList());
  }

  @override
  Future<Either<Failure, List<CustomerInstallmentEntity>>> listOverdueContracts() async {
    final rows = await (_db.select(_db.customerInstallments)
      ..where((t) => t.deletedAt.isNull() & t.status.isNotIn(['completed', 'cancelled']) & t.remainingPiasters.isBiggerThanValue(0)))
      .get();
    final now = DateTime.now();
    final overdue = rows
      .map(_mapContract)
      .where((c) => c.statusAt(now) == 'overdue')
      .toList();
    return Right(overdue);
  }

  @override
  Future<Either<Failure, Unit>> cancelContract({
    required String contractId,
    required String pin,
  }) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }
    if (!await _featureGate.isCurrentUserAdmin()) {
      return const Left(AuthFailure('غير مصرح: إلغاء عقد التقسيط متاح للمدير فقط'));
    }

    final pinResult = await _pinService.verifyPin(pin: pin, operation: 'cancel_contract');
    if (!pinResult.ok) {
      return Left(AuthFailure(pinResult.error ?? 'الرقم السري للمدير غير صحيح'));
    }

    final contract = await (_db.select(_db.customerInstallments)
      ..where((t) => t.id.equals(contractId) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (contract == null) {
      return const Left(ServerFailure('العقد غير موجود'));
    }
    if (contract.status == 'completed') {
      return const Left(ServerFailure('لا يمكن إلغاء عقد مكتمل'));
    }
    if (contract.status == 'cancelled') {
      return const Left(ServerFailure('العقد ملغى بالفعل'));
    }

    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'admin';
    final now = DateTime.now();

    await _txWriter.write(
      writeFn: () async {
        await (_db.update(_db.customerInstallments)..where((t) => t.id.equals(contractId))).write(
          CustomerInstallmentsCompanion(
            status: const Value('cancelled'),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'customer_installments',
      entityId: contractId,
      operation: 'cancel',
      userId: userId,
      oldValue: contract.status,
      newValue: 'cancelled',
      auditAction: 'installment_contract_cancelled',
      payload: jsonEncode({'contractId': contractId}),
    );

    return const Right(unit);
  }

  // ---------------------------------------------------------------------------
  // Payments
  // ---------------------------------------------------------------------------

  @override
  Future<Either<Failure, InstallmentPaymentEntity>> recordPayment({
    required String contractId,
    required int amountPiasters,
    required String paymentMethod,
    String? receiptNumber,
    String? notes,
    required String pin,
  }) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }

    final pinResult = await _pinService.verifyPin(pin: pin, operation: 'record_payment');
    if (!pinResult.ok) {
      return Left(AuthFailure(pinResult.error ?? 'الرقم السري للمدير غير صحيح'));
    }

    if (amountPiasters <= 0) {
      return const Left(ServerFailure('مبلغ الدفعة يجب أن يكون أكبر من صفر'));
    }
    if (paymentMethod != 'cash' && paymentMethod != 'card') {
      return const Left(ServerFailure('طريقة الدفع غير صالحة'));
    }

    final contract = await (_db.select(_db.customerInstallments)
      ..where((t) => t.id.equals(contractId) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (contract == null) {
      return const Left(ServerFailure('العقد غير موجود'));
    }
    if (contract.status == 'cancelled') {
      return const Left(ServerFailure('لا يمكن تسجيل دفعة على عقد ملغى'));
    }
    if (contract.status == 'completed' || contract.remainingPiasters <= 0) {
      return const Left(ServerFailure('العقد مكتمل بالكامل بالفعل'));
    }
    if (amountPiasters > contract.remainingPiasters) {
      return Left(ServerFailure('مبلغ الدفعة ($amountPiasters) يتجاوز المبلغ المتبقي ($contract.remainingPiasters)'));
    }

    final paymentId = const Uuid().v4();
    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'unknown';
    final now = DateTime.now();

    final newRemaining = contract.remainingPiasters - amountPiasters;
    final newStatus = newRemaining == 0 ? 'completed' : contract.status;

    final payment = InstallmentPaymentEntity(
      id: paymentId,
      branchId: branchId,
      customerInstallmentId: contractId,
      amountPiasters: amountPiasters,
      paymentMethod: paymentMethod,
      paidAt: now,
      receiptNumber: receiptNumber,
      notes: notes,
      recordedBy: userId,
      createdAt: now,
      updatedAt: now,
    );

    await _txWriter.write(
      writeFn: () async {
        await _db.into(_db.installmentPayments).insert(
          InstallmentPaymentsCompanion.insert(
            id: paymentId,
            branchId: branchId,
            customerInstallmentId: contractId,
            amountPiasters: amountPiasters,
            paymentMethod: paymentMethod,
            paidAt: now,
            receiptNumber: Value(receiptNumber),
            notes: Value(notes),
            recordedBy: userId,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await (_db.update(_db.customerInstallments)..where((t) => t.id.equals(contractId))).write(
          CustomerInstallmentsCompanion(
            remainingPiasters: Value(newRemaining),
            status: Value(newStatus),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'installment_payments',
      entityId: paymentId,
      operation: 'create',
      userId: userId,
      oldValue: null,
      newValue: '$amountPiasters',
      auditAction: 'installment_payment_recorded',
      payload: jsonEncode({
        'contractId': contractId,
        'amountPiasters': amountPiasters,
        'newRemaining': newRemaining,
        'newStatus': newStatus,
      }),
    );

    return Right(payment);
  }

  @override
  Future<Either<Failure, List<InstallmentPaymentEntity>>> listPayments(String contractId) async {
    final rows = await (_db.select(_db.installmentPayments)
      ..where((t) => t.customerInstallmentId.equals(contractId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
      .get();
    return Right(rows.map(_mapPayment).toList());
  }

  @override
  Future<Either<Failure, InstallmentSummary>> getSummary({DateTime? now}) async {
    try {
      final current = now ?? DateTime.now();
      final activeContracts = await (_db.select(_db.customerInstallments)
        ..where((t) => t.deletedAt.isNull() & t.status.equals('active')))
        .get();
      final totalOutstanding = activeContracts.fold<int>(0, (sum, c) => sum + c.remainingPiasters);

      final startOfMonth = DateTime(current.year, current.month, 1);
      final nextMonth = DateTime(current.year, current.month + 1, 1);
      final paymentsThisMonth = await (_db.select(_db.installmentPayments)
        ..where((t) => t.deletedAt.isNull() & t.paidAt.isBiggerOrEqualValue(startOfMonth) & t.paidAt.isSmallerThanValue(nextMonth)))
        .get();
      final monthlyCollected = paymentsThisMonth.fold<int>(0, (sum, p) => sum + p.amountPiasters);

      final rows = await (_db.select(_db.customerInstallments)
        ..where((t) => t.deletedAt.isNull() & t.status.isNotIn(['completed', 'cancelled']) & t.remainingPiasters.isBiggerThanValue(0)))
        .get();
      final overdueContracts = rows
        .map(_mapContract)
        .where((c) => c.statusAt(current) == 'overdue')
        .toList();
      final overdueTotal = overdueContracts.fold<int>(0, (sum, c) => sum + c.remainingPiasters);
      final overdueCount = overdueContracts.length;

      return Right(InstallmentSummary(
        totalOutstanding: totalOutstanding,
        monthlyCollected: monthlyCollected,
        overdueTotal: overdueTotal,
        overdueCount: overdueCount,
      ));
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Either<Failure, List<InstallmentScheduleEntry>> calculateSchedule({
    required int principalPiasters,
    required int durationMonths,
    required InstallmentInterestModel interestModel,
    required int interestValue,
    required int downPaymentPiasters,
    required DateTime startDate,
  }) {
    return InstallmentCalculator.calculateSchedule(
      principalPiasters: principalPiasters,
      durationMonths: durationMonths,
      interestModel: interestModel,
      interestValue: interestValue,
      downPaymentPiasters: downPaymentPiasters,
      startDate: startDate,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  InstallmentPlanEntity _mapPlan(InstallmentPlan row) => InstallmentPlanEntity(
        id: row.id,
        branchId: row.branchId,
        name: row.name,
        description: row.description,
        durationMonths: row.durationMonths,
        downPaymentPiasters: row.downPaymentPiasters,
        interestBp: row.interestBp,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  CustomerInstallmentEntity _mapContract(CustomerInstallment row) => CustomerInstallmentEntity(
        id: row.id,
        branchId: row.branchId,
        saleId: row.saleId,
        customerId: row.customerId,
        planId: row.planId,
        totalPiasters: row.totalPiasters,
        downPaymentPiasters: row.downPaymentPiasters,
        principalPiasters: row.principalPiasters,
        interestBp: row.interestBp,
        monthlyAmountPiasters: row.monthlyAmountPiasters,
        remainingPiasters: row.remainingPiasters,
        durationMonths: row.durationMonths,
        startDate: row.startDate,
        endDate: row.endDate,
        status: row.status,
        createdBy: row.createdBy,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );

  InstallmentPaymentEntity _mapPayment(InstallmentPayment row) => InstallmentPaymentEntity(
        id: row.id,
        branchId: row.branchId,
        customerInstallmentId: row.customerInstallmentId,
        amountPiasters: row.amountPiasters,
        paymentMethod: row.paymentMethod,
        paidAt: row.paidAt,
        receiptNumber: row.receiptNumber,
        notes: row.notes,
        recordedBy: row.recordedBy,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      );
}
