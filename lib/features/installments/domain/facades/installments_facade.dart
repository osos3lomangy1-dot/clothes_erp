import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../pos/domain/entities/payment_split.dart';
import '../entities/customer_installment_entity.dart';
import '../entities/customer_installments_summary.dart';
import '../entities/bulk_installment_payment_result.dart';
import '../entities/early_settlement_outcome.dart';
import '../entities/installment_payment_entity.dart';
import '../entities/installment_plan_entity.dart';
import '../entities/installment_schedule_entry.dart';
import '../entities/installment_summary.dart';
import '../services/installment_calculator.dart';

abstract class InstallmentsFacade {
  // Plans
  Future<Either<Failure, InstallmentPlanEntity>> createPlan({
    required String name,
    String? description,
    required int durationMonths,
    required int downPaymentPiasters,
    required int interestBp,
  });
  Future<Either<Failure, List<InstallmentPlanEntity>>> listPlans();
  Future<Either<Failure, Unit>> updatePlan(InstallmentPlanEntity plan);
  Future<Either<Failure, Unit>> deactivatePlan(String planId);

  // Contracts
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
  });
  Future<Either<Failure, CustomerInstallmentEntity>> getContract(String id);
  Future<Either<Failure, List<CustomerInstallmentEntity>>> listContracts({
    String? customerId,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  });
  Future<Either<Failure, List<CustomerInstallmentsSummary>>> getGroupedByCustomer({
    required DateTime now,
  });
  Future<Either<Failure, List<CustomerInstallmentEntity>>> listOverdueContracts();
  Future<Either<Failure, Unit>> cancelContract({
    required String contractId,
    required String pin,
  });

  // Payments
  Future<Either<Failure, InstallmentPaymentEntity>> recordPayment({
    required String contractId,
    required int amountPiasters,
    required String paymentMethod, // 'cash' | 'card'
    String? receiptNumber,
    String? notes,
    required String pin,
    DateTime? paidAt,
  });
  Future<Either<Failure, BulkInstallmentPaymentResult>> recordBulkCustomerPayment({
    required String customerId,
    required int amountPiasters,
    required String paymentMethod, // 'cash' | 'card'
    String? receiptNumber,
    String? notes,
    required String pin,
  });
  Future<Either<Failure, EarlySettlementOutcome>> settleContractEarly({
    required String contractId,
    required int waivedInterestPiasters,
    required String paymentMethod, // 'cash' | 'card'
    String? notes,
    required String pin,
    DateTime? settledAt,
  });
  Future<Either<Failure, List<InstallmentPaymentEntity>>> listPayments(String contractId);

  // Summary (2C-2B)
  Future<Either<Failure, InstallmentSummary>> getSummary({DateTime? now});

  // Calculation (2B)
  Either<Failure, List<InstallmentScheduleEntry>> calculateSchedule({
    required int principalPiasters,
    required int durationMonths,
    required InstallmentInterestModel interestModel,
    required int interestValue,
    required int downPaymentPiasters,
    required DateTime startDate,
  });
}
