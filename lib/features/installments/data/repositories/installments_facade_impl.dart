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
import '../../domain/entities/bulk_installment_payment_result.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/customer_installments_summary.dart';
import '../../domain/entities/early_settlement_outcome.dart';
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
    final endDate = InstallmentCalculator.addMonths(startDate, durationMonths);

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
            final activeShift = await _getActiveShift();

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

  static const String _promissoryNotesStorageKey = 'installment_promissory_notes';

  Future<Map<String, Map<String, dynamic>>> _loadPromissoryNotes() async {
    final row = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals(_promissoryNotesStorageKey)))
        .getSingleOrNull();
    if (row == null || row.value.isEmpty) return {};
    try {
      final decoded = jsonDecode(row.value) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePromissoryNote(
    String contractId,
    bool delivered,
    DateTime? deliveredAt, {
    bool hasNote = true,
  }) async {
    final notes = await _loadPromissoryNotes();
    notes[contractId] = {
      'delivered': delivered,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'hasNote': hasNote,
    };
    final now = DateTime.now();
    await _db.into(_db.appMeta).insertOnConflictUpdate(
      AppMetaCompanion.insert(
        key: _promissoryNotesStorageKey,
        value: jsonEncode(notes),
        updatedAt: now,
      ),
    );
  }

  @override
  Future<Either<Failure, CustomerInstallmentEntity>> getContract(String id) async {
    final row = await (_db.select(_db.customerInstallments)
      ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
      .getSingleOrNull();
    if (row == null) {
      return const Left(ServerFailure('العقد غير موجود'));
    }
    final notes = await _loadPromissoryNotes();
    return Right(_mapContract(row, notes));
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
    final notes = await _loadPromissoryNotes();
    return Right(rows.map((r) => _mapContract(r, notes)).toList());
  }

  @override
  Future<Either<Failure, List<CustomerInstallmentEntity>>> listOverdueContracts() async {
    final rows = await (_db.select(_db.customerInstallments)
      ..where((t) => t.deletedAt.isNull() & t.status.isNotIn(['completed', 'cancelled', 'legal_case']) & t.remainingPiasters.isBiggerThanValue(0)))
      .get();
    final now = DateTime.now();
    final notes = await _loadPromissoryNotes();
    final overdue = rows
      .map((r) => _mapContract(r, notes))
      .where((c) => c.statusAt(now) == 'overdue')
      .toList();
    return Right(overdue);
  }

  @override
  Future<Either<Failure, List<CustomerInstallmentsSummary>>> getGroupedByCustomer({
    required DateTime now,
    bool includeInactive = false,
  }) async {
    try {
      final allRows = await (_db.select(_db.customerInstallments)
            ..where((c) => c.deletedAt.isNull()))
          .get();

      final notes = await _loadPromissoryNotes();
      final allEntities = allRows.map((r) => _mapContract(r, notes)).toList();
      if (allEntities.isEmpty) return const Right([]);

      final targetEntities = allEntities.where((c) {
        if (includeInactive) return true;
        final status = c.statusAt(now);
        return status == 'active' || status == 'overdue' || status == 'legal_case';
      }).toList();
      if (targetEntities.isEmpty) return const Right([]);

      final byCustomer = <String, List<CustomerInstallmentEntity>>{};
      for (final c in targetEntities) {
        byCustomer.putIfAbsent(c.customerId, () => []).add(c);
      }

      final customerIds = byCustomer.keys.toList();
      final customerRows = await (_db.select(_db.customers)
            ..where((c) => c.id.isIn(customerIds)))
          .get();
      final nameMap = {for (final c in customerRows) c.id: c.name};

      final summaries = byCustomer.entries.map((entry) {
        final contracts = entry.value;
        final totalRemaining = contracts.fold<int>(0, (s, c) => s + c.remainingPiasters);
        final totalMonthly = contracts
            .where((c) {
              final st = c.statusAt(now);
              return st != 'completed' && st != 'cancelled' && st != 'written_off';
            })
            .fold<int>(0, (s, c) => s + c.monthlyAmountPiasters);
        final fallbackName = entry.key.length > 8
            ? 'عميل ${entry.key.substring(0, 8)}'
            : 'عميل ${entry.key}';

        return CustomerInstallmentsSummary(
          customerId: entry.key,
          customerName: nameMap[entry.key] ?? fallbackName,
          contractsCount: contracts.length,
          totalRemainingPiasters: totalRemaining,
          totalMonthlyAmountPiasters: totalMonthly,
          currentMonthDuePiasters: totalMonthly,
          contracts: contracts,
        );
      }).toList();

      return Right(summaries);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
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

  @override
  Future<Either<Failure, Unit>> updateLegalStatus({
    required String contractId,
    required bool isLegalCase,
  }) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
        return Left(FeatureDisabledFailure(FeatureKeys.installments));
      }
      final contract = await (_db.select(_db.customerInstallments)
        ..where((t) => t.id.equals(contractId) & t.deletedAt.isNull()))
        .getSingleOrNull();
      if (contract == null) {
        return const Left(ServerFailure('العقد غير موجود'));
      }
      if (contract.status == 'completed' || contract.status == 'cancelled' || contract.status == 'written_off') {
        return const Left(ServerFailure('لا يمكن تغيير حالة عقد مكتمل أو ملغي أو معدوم'));
      }

      final newStatus = isLegalCase ? 'legal_case' : 'active';
      final now = DateTime.now();
      final branchId = await _branchProvider.getBranchId();
      final user = await _auth.getCachedUser();
      final userId = user?.id ?? 'admin';

      await _txWriter.write(
        writeFn: () async {
          await (_db.update(_db.customerInstallments)..where((t) => t.id.equals(contractId))).write(
            CustomerInstallmentsCompanion(
              status: Value(newStatus),
              updatedAt: Value(now),
            ),
          );
        },
        branchId: branchId,
        entity: 'customer_installments',
        entityId: contractId,
        operation: isLegalCase ? 'mark_legal_case' : 'unmark_legal_case',
        userId: userId,
        oldValue: contract.status,
        newValue: newStatus,
        auditAction: isLegalCase ? 'installment_legal_case_opened' : 'installment_legal_case_closed',
        payload: jsonEncode({'contractId': contractId, 'isLegalCase': isLegalCase}),
      );

      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure('فشل تحديث حالة العقد القانونية: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> writeOffBadDebt({
    required String contractId,
    required String reason,
    required String pin,
  }) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
        return Left(FeatureDisabledFailure(FeatureKeys.installments));
      }
      if (!await _featureGate.isCurrentUserAdmin()) {
        return const Left(AuthFailure('غير مصرح: إعدام الديون متاح للمدير فقط'));
      }

      final pinResult = await _pinService.verifyPin(pin: pin, operation: 'write_off_bad_debt');
      if (!pinResult.ok) {
        return Left(AuthFailure(pinResult.error ?? 'الرقم السري للمدير غير صحيح'));
      }

      final contract = await (_db.select(_db.customerInstallments)
        ..where((t) => t.id.equals(contractId) & t.deletedAt.isNull()))
        .getSingleOrNull();
      if (contract == null) {
        return const Left(ServerFailure('العقد غير موجود'));
      }
      if (contract.status == 'completed' || contract.status == 'cancelled' || contract.status == 'written_off') {
        return const Left(ServerFailure('لا يمكن إعدام دين لعقد مكتمل أو ملغي أو معدوم بالفعل'));
      }

      final now = DateTime.now();
      final branchId = await _branchProvider.getBranchId();
      final user = await _auth.getCachedUser();
      final userId = user?.id ?? 'admin';

      await _txWriter.write(
        writeFn: () async {
          // 1. Mark contract as written off
          await (_db.update(_db.customerInstallments)..where((t) => t.id.equals(contractId))).write(
            CustomerInstallmentsCompanion(
              status: const Value('written_off'),
              updatedAt: Value(now),
            ),
          );

          // 2. Blacklist customer
          await (_db.update(_db.customers)..where((t) => t.id.equals(contract.customerId))).write(
            CustomersCompanion(
              customerType: const Value('blacklisted'),
              updatedAt: Value(now),
            ),
          );
        },
        branchId: branchId,
        entity: 'customer_installments',
        entityId: contractId,
        operation: 'write_off_bad_debt',
        userId: userId,
        oldValue: contract.status,
        newValue: 'written_off',
        auditAction: 'installment_bad_debt_write_off',
        payload: jsonEncode({
          'contractId': contractId,
          'customerId': contract.customerId,
          'remainingPiasters': contract.remainingPiasters,
          'reason': reason,
        }),
      );

      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure('فشل إعدام الدين: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> markPromissoryNoteDelivered({
    required String contractId,
    required bool delivered,
    DateTime? deliveredAt,
    bool hasNote = true,
  }) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }
    await _savePromissoryNote(contractId, delivered, deliveredAt, hasNote: hasNote);
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
    DateTime? paidAt,
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
    final effectivePaidAt = paidAt ?? now;
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final activeShift = await _getActiveShift();

    final newRemaining = contract.remainingPiasters - amountPiasters;
    final newStatus = newRemaining == 0 ? 'completed' : contract.status;

    final payment = InstallmentPaymentEntity(
      id: paymentId,
      branchId: branchId,
      customerInstallmentId: contractId,
      amountPiasters: amountPiasters,
      paymentMethod: paymentMethod,
      paidAt: effectivePaidAt,
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
            paidAt: effectivePaidAt,
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

        await _db.into(_db.cashMovements).insert(
          CashMovementsCompanion.insert(
            id: const Uuid().v4(),
            branchId: branchId,
            shiftId: Value(activeShift?.id),
            type: 'installment_payment',
            method: paymentMethod,
            direction: 'in',
            amountPiasters: amountPiasters,
            referenceId: Value(contractId),
            notes: Value(notes ?? 'سداد قسط ($paymentMethod)'),
            createdAt: nowSec,
            updatedAt: nowSec,
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
        'paymentMethod': paymentMethod,
        'shiftId': activeShift?.id,
      }),
    );

    return Right(payment);
  }

  @override
  Future<Either<Failure, BulkInstallmentPaymentResult>> recordBulkCustomerPayment({
    required String customerId,
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

    final contracts = await (_db.select(_db.customerInstallments)
          ..where((t) =>
              t.customerId.equals(customerId) &
              t.deletedAt.isNull() &
              t.status.isNotIn(['completed', 'cancelled']) &
              t.remainingPiasters.isBiggerThanValue(0))
          ..orderBy([
            (t) => OrderingTerm.asc(t.startDate),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();

    if (contracts.isEmpty) {
      return const Left(ServerFailure('لا توجد عقود تقسيط نشطة أو مستحقة لهذا العميل'));
    }

    final totalRemaining = contracts.fold<int>(0, (sum, c) => sum + c.remainingPiasters);
    if (amountPiasters > totalRemaining) {
      return Left(ServerFailure(
        'المبلغ المدخل (${amountPiasters ~/ 100} ج.م) يتجاوز إجمالي ديون وأقساط العميل (${totalRemaining ~/ 100} ج.م)',
      ));
    }

    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'unknown';
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final activeShift = await _getActiveShift();

    int remainingToAllocate = amountPiasters;
    final List<InstallmentPaymentEntity> createdPayments = [];

    await _txWriter.write(
      writeFn: () async {
        for (final contract in contracts) {
          if (remainingToAllocate <= 0) break;

          final payForThisContract = remainingToAllocate < contract.remainingPiasters
              ? remainingToAllocate
              : contract.remainingPiasters;
          remainingToAllocate -= payForThisContract;

          final paymentId = const Uuid().v4();
          final newContractRemaining = contract.remainingPiasters - payForThisContract;
          final newContractStatus = newContractRemaining == 0 ? 'completed' : contract.status;

          final payment = InstallmentPaymentEntity(
            id: paymentId,
            branchId: branchId,
            customerInstallmentId: contract.id,
            amountPiasters: payForThisContract,
            paymentMethod: paymentMethod,
            paidAt: now,
            receiptNumber: receiptNumber,
            notes: notes ?? 'سداد قسط مجمع للعميل',
            recordedBy: userId,
            createdAt: now,
            updatedAt: now,
          );
          createdPayments.add(payment);

          // 1. Insert installment payment
          await _db.into(_db.installmentPayments).insert(
            InstallmentPaymentsCompanion.insert(
              id: paymentId,
              branchId: branchId,
              customerInstallmentId: contract.id,
              amountPiasters: payForThisContract,
              paymentMethod: paymentMethod,
              paidAt: now,
              receiptNumber: Value(receiptNumber),
              notes: Value(notes ?? 'سداد قسط مجمع للعميل'),
              recordedBy: userId,
              createdAt: now,
              updatedAt: now,
            ),
          );

          // 2. Update contract
          await (_db.update(_db.customerInstallments)..where((t) => t.id.equals(contract.id))).write(
            CustomerInstallmentsCompanion(
              remainingPiasters: Value(newContractRemaining),
              status: Value(newContractStatus),
              updatedAt: Value(now),
            ),
          );

          // 3. Insert cash movement in drawer
          final shortContractId = contract.id.length > 8 ? contract.id.substring(0, 8) : contract.id;
          await _db.into(_db.cashMovements).insert(
            CashMovementsCompanion.insert(
              id: const Uuid().v4(),
              branchId: branchId,
              shiftId: Value(activeShift?.id),
              type: 'installment_payment',
              method: paymentMethod,
              direction: 'in',
              amountPiasters: payForThisContract,
              referenceId: Value(contract.id),
              notes: Value(notes ?? 'سداد قسط مجمع (عقد #$shortContractId)'),
              createdAt: nowSec,
              updatedAt: nowSec,
            ),
          );
        }
      },
      branchId: branchId,
      entity: 'installment_payments',
      entityId: customerId,
      operation: 'create_bulk',
      userId: userId,
      oldValue: null,
      newValue: '$amountPiasters',
      auditAction: 'installment_bulk_payment_recorded',
      payload: jsonEncode({
        'customerId': customerId,
        'totalAmountPiasters': amountPiasters,
        'affectedContracts': createdPayments.length,
        'shiftId': activeShift?.id,
      }),
    );

    return Right(BulkInstallmentPaymentResult(
      customerId: customerId,
      totalAmountPiasters: amountPiasters,
      affectedContractsCount: createdPayments.length,
      payments: createdPayments,
    ));
  }

  @override
  Future<Either<Failure, EarlySettlementOutcome>> settleContractEarly({
    required String contractId,
    required int waivedInterestPiasters,
    required String paymentMethod,
    String? notes,
    required String pin,
    DateTime? settledAt,
  }) async {
    if (!await _featureGate.isEnabled(FeatureKeys.installments)) {
      return Left(FeatureDisabledFailure(FeatureKeys.installments));
    }

    final pinResult = await _pinService.verifyPin(
      pin: pin,
      operation: 'early_settlement',
    );
    if (!pinResult.ok) {
      return Left(AuthFailure(pinResult.error ?? 'الرقم السري للمدير غير صحيح'));
    }

    if (paymentMethod != 'cash' && paymentMethod != 'card') {
      return const Left(ServerFailure('طريقة الدفع غير صالحة'));
    }
    if (waivedInterestPiasters < 0) {
      return const Left(ServerFailure('مبلغ إعفاء الفائدة لا يمكن أن يكون سالباً'));
    }

    final contract = await (_db.select(_db.customerInstallments)
          ..where((t) => t.id.equals(contractId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (contract == null) {
      return const Left(ServerFailure('العقد غير موجود'));
    }
    if (contract.status == 'cancelled') {
      return const Left(ServerFailure('لا يمكن تسوية عقد ملغي'));
    }
    if (contract.status == 'completed' || contract.remainingPiasters <= 0) {
      return const Left(ServerFailure('العقد مكتمل بالكامل بالفعل'));
    }

    // Calculate max waivable interest so total cash collected never drops below financed principal
    final existingPayments = await (_db.select(_db.installmentPayments)
          ..where((t) =>
              t.customerInstallmentId.equals(contractId) & t.deletedAt.isNull()))
        .get();
    final paidTowardsScheduleCash = existingPayments
        .where((p) =>
            p.receiptNumber != 'DOWN_PAYMENT' &&
            p.receiptNumber != 'INTEREST_WAIVER' &&
            p.paymentMethod != 'waiver')
        .fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final minCashForPrincipal =
        (contract.principalPiasters - paidTowardsScheduleCash)
            .clamp(0, contract.remainingPiasters);
    final maxWaivableInterest =
        (contract.remainingPiasters - minCashForPrincipal)
            .clamp(0, contract.remainingPiasters);

    if (waivedInterestPiasters > maxWaivableInterest) {
      return Left(ServerFailure(
        'مبلغ الإعفاء يتجاوز الفائدة المتبقية المسموح بإعفائها (${(maxWaivableInterest / 100).toStringAsFixed(2)} ج.م)',
      ));
    }

    final settlementAmountPiasters =
        contract.remainingPiasters - waivedInterestPiasters;
    final branchId = await _branchProvider.getBranchId();
    final user = await _auth.getCachedUser();
    final userId = user?.id ?? 'unknown';
    final now = DateTime.now();
    final effectiveSettledAt = settledAt ?? now;
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final activeShift = await _getActiveShift();

    InstallmentPaymentEntity? cashPayment;
    final cashPaymentId = const Uuid().v4();
    final waiverPaymentId = const Uuid().v4();
    final waiverNote = notes != null && notes.trim().isNotEmpty
        ? 'إعفاء فائدة سداد مبكر — ${notes.trim()}'
        : 'إعفاء فائدة سداد مبكر';
    final cashNote = notes != null && notes.trim().isNotEmpty
        ? 'سداد مبكر / تسوية نهائية — ${notes.trim()}'
        : 'سداد مبكر / تسوية نهائية للعقد';

    if (settlementAmountPiasters > 0) {
      cashPayment = InstallmentPaymentEntity(
        id: cashPaymentId,
        branchId: branchId,
        customerInstallmentId: contractId,
        amountPiasters: settlementAmountPiasters,
        paymentMethod: paymentMethod,
        paidAt: effectiveSettledAt,
        receiptNumber: 'EARLY_SETTLEMENT',
        notes: cashNote,
        recordedBy: userId,
        createdAt: now,
        updatedAt: now,
      );
    }

    await _txWriter.write(
      writeFn: () async {
        // 1. Record actual cash/card collected (and ONLY this amount enters cash_movements!)
        if (settlementAmountPiasters > 0) {
          await _db.into(_db.installmentPayments).insert(
            InstallmentPaymentsCompanion.insert(
              id: cashPaymentId,
              branchId: branchId,
              customerInstallmentId: contractId,
              amountPiasters: settlementAmountPiasters,
              paymentMethod: paymentMethod,
              paidAt: effectiveSettledAt,
              receiptNumber: const Value('EARLY_SETTLEMENT'),
              notes: Value(cashNote),
              recordedBy: userId,
              createdAt: now,
              updatedAt: now,
            ),
          );

          await _db.into(_db.cashMovements).insert(
            CashMovementsCompanion.insert(
              id: const Uuid().v4(),
              branchId: branchId,
              shiftId: Value(activeShift?.id),
              type: 'installment_payment',
              method: paymentMethod,
              direction: 'in',
              amountPiasters: settlementAmountPiasters,
              referenceId: Value(contractId),
              notes: Value(cashNote),
              createdAt: nowSec,
              updatedAt: nowSec,
            ),
          );
        }

        // 2. Document waived interest in installment_payments (NO cash_movements row!)
        if (waivedInterestPiasters > 0) {
          await _db.into(_db.installmentPayments).insert(
            InstallmentPaymentsCompanion.insert(
              id: waiverPaymentId,
              branchId: branchId,
              customerInstallmentId: contractId,
              amountPiasters: waivedInterestPiasters,
              paymentMethod: paymentMethod,
              paidAt: effectiveSettledAt,
              receiptNumber: const Value('INTEREST_WAIVER'),
              notes: Value(waiverNote),
              recordedBy: userId,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        // 3. Close contract atomically
        await (_db.update(_db.customerInstallments)
              ..where((t) => t.id.equals(contractId)))
            .write(
          CustomerInstallmentsCompanion(
            remainingPiasters: const Value(0),
            status: const Value('completed'),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'customer_installments',
      entityId: contractId,
      operation: 'early_settlement',
      userId: userId,
      oldValue: '${contract.remainingPiasters}',
      newValue: '0',
      auditAction: 'installment_early_settlement',
      payload: jsonEncode({
        'contractId': contractId,
        'previousRemaining': contract.remainingPiasters,
        'settlementAmountPiasters': settlementAmountPiasters,
        'waivedInterestPiasters': waivedInterestPiasters,
        'paymentMethod': paymentMethod,
        'settledAt': effectiveSettledAt.toIso8601String(),
        'shiftId': activeShift?.id,
      }),
    );

    return Right(EarlySettlementOutcome(
      contractId: contractId,
      settlementAmountPiasters: settlementAmountPiasters,
      waivedInterestPiasters: waivedInterestPiasters,
      paymentMethod: paymentMethod,
      settledAt: effectiveSettledAt,
      cashPayment: cashPayment,
    ));
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
        ..where((t) =>
            t.deletedAt.isNull() &
            t.paidAt.isBiggerOrEqualValue(startOfMonth) &
            t.paidAt.isSmallerThanValue(nextMonth)))
        .get();
      final monthlyCollected = paymentsThisMonth
          .where((p) => p.receiptNumber != 'INTEREST_WAIVER')
          .fold<int>(0, (sum, p) => sum + p.amountPiasters);

      final rows = await (_db.select(_db.customerInstallments)
        ..where((t) => t.deletedAt.isNull() & t.status.isNotIn(['completed', 'cancelled', 'legal_case']) & t.remainingPiasters.isBiggerThanValue(0)))
        .get();
      final notes = await _loadPromissoryNotes();
      final overdueContracts = rows
        .map((r) => _mapContract(r, notes))
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

  CustomerInstallmentEntity _mapContract(
    CustomerInstallment row, [
    Map<String, Map<String, dynamic>>? notesMap,
  ]) {
    final noteInfo = notesMap?[row.id];
    final bool hasNote = noteInfo?['hasNote'] != false;
    final bool noteDelivered = noteInfo?['delivered'] == true;
    final DateTime? noteDeliveredAt = noteInfo?['deliveredAt'] != null
        ? DateTime.tryParse(noteInfo!['deliveredAt'] as String)
        : null;

    return CustomerInstallmentEntity(
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
      promissoryNoteDelivered: noteDelivered,
      promissoryNoteDeliveredAt: noteDeliveredAt,
      hasPromissoryNote: hasNote,
    );
  }

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

  Future<Shift?> _getActiveShift() async {
    return await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();
  }
}
