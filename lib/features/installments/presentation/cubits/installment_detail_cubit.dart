import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../customers/domain/repositories/customer_repository.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/installment_payment_entity.dart';
import '../../domain/entities/installment_schedule_entry.dart';
import '../../domain/facades/installments_facade.dart';
import '../../domain/services/installment_calculator.dart';

enum InstallmentDetailStatus { initial, loading, success, error }

class InstallmentDetailState extends Equatable {
  final InstallmentDetailStatus status;
  final CustomerInstallmentEntity? contract;
  final String? customerName;
  final List<InstallmentScheduleEntry> schedule;
  final List<InstallmentScheduleAllocation> allocations;
  final List<InstallmentPaymentEntity> payments;
  final int totalContractInterestPiasters;
  final int paidTowardsScheduleCashPiasters;
  final bool isCancelling;
  final bool isSettling;
  final String? errorMessage;

  const InstallmentDetailState({
    this.status = InstallmentDetailStatus.initial,
    this.contract,
    this.customerName,
    this.schedule = const [],
    this.allocations = const [],
    this.payments = const [],
    this.totalContractInterestPiasters = 0,
    this.paidTowardsScheduleCashPiasters = 0,
    this.isCancelling = false,
    this.isSettling = false,
    this.errorMessage,
  });

  InstallmentDetailState copyWith({
    InstallmentDetailStatus? status,
    CustomerInstallmentEntity? contract,
    String? customerName,
    List<InstallmentScheduleEntry>? schedule,
    List<InstallmentScheduleAllocation>? allocations,
    List<InstallmentPaymentEntity>? payments,
    int? totalContractInterestPiasters,
    int? paidTowardsScheduleCashPiasters,
    bool? isCancelling,
    bool? isSettling,
    String? errorMessage,
  }) {
    return InstallmentDetailState(
      status: status ?? this.status,
      contract: contract ?? this.contract,
      customerName: customerName ?? this.customerName,
      schedule: schedule ?? this.schedule,
      allocations: allocations ?? this.allocations,
      payments: payments ?? this.payments,
      totalContractInterestPiasters:
          totalContractInterestPiasters ?? this.totalContractInterestPiasters,
      paidTowardsScheduleCashPiasters:
          paidTowardsScheduleCashPiasters ?? this.paidTowardsScheduleCashPiasters,
      isCancelling: isCancelling ?? this.isCancelling,
      isSettling: isSettling ?? this.isSettling,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        contract,
        customerName,
        schedule,
        allocations,
        payments,
        totalContractInterestPiasters,
        paidTowardsScheduleCashPiasters,
        isCancelling,
        isSettling,
        errorMessage,
      ];
}

class InstallmentDetailCubit extends Cubit<InstallmentDetailState> {
  final String contractId;
  final InstallmentsFacade _facade;
  final CustomerRepository _customerRepo;

  InstallmentDetailCubit({
    required this.contractId,
    required InstallmentsFacade facade,
    required CustomerRepository customerRepo,
  })  : _facade = facade,
        _customerRepo = customerRepo,
        super(const InstallmentDetailState()) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(status: InstallmentDetailStatus.loading));

    final contractRes = await _facade.getContract(contractId);
    if (contractRes.isLeft()) {
      emit(state.copyWith(
        status: InstallmentDetailStatus.error,
        errorMessage: contractRes.fold((f) => f.message, (_) => ''),
      ));
      return;
    }

    final contract = contractRes.getOrElse(() => throw Exception());

    // Fetch customer name
    String? customerName;
    final customerRes = await _customerRepo.getCustomerById(contract.customerId);
    customerRes.fold(
      (_) => null,
      (cust) => customerName = cust?.name,
    );

    // Fetch payments
    final paymentsRes = await _facade.listPayments(contractId);
    final payments = paymentsRes.getOrElse(() => []);

    // Derive the exact contract total interest from remaining + non-down payments - principal.
    // This faithfully reproduces the original schedule regardless of whether the contract
    // was created with percentTotal, percentMonthly, or fixed interest.
    final nonDownPaymentsTotal = payments
        .where((p) => p.receiptNumber != 'DOWN_PAYMENT')
        .fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final paidTowardsScheduleCash = payments
        .where((p) =>
            p.receiptNumber != 'DOWN_PAYMENT' &&
            p.receiptNumber != 'INTEREST_WAIVER' &&
            p.paymentMethod != 'waiver')
        .fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final totalScheduledObligation = contract.remainingPiasters + nonDownPaymentsTotal;
    final exactTotalInterest = (totalScheduledObligation - contract.principalPiasters)
        .clamp(0, totalScheduledObligation);

    // Calculate schedule (first installment due next month after startDate)
    final scheduleRes = _facade.calculateSchedule(
      principalPiasters: contract.totalPiasters,
      durationMonths: contract.durationMonths,
      interestModel: InstallmentInterestModel.fixed,
      interestValue: exactTotalInterest,
      downPaymentPiasters: contract.downPaymentPiasters,
      startDate: contract.startDate,
    );
    final schedule = scheduleRes.getOrElse(() => []);
    final allocations = InstallmentCalculator.allocatePaymentsToSchedule(
      schedule: schedule,
      payments: payments,
    );

    emit(state.copyWith(
      status: InstallmentDetailStatus.success,
      contract: contract,
      customerName: customerName,
      schedule: schedule,
      allocations: allocations,
      payments: payments,
      totalContractInterestPiasters: exactTotalInterest,
      paidTowardsScheduleCashPiasters: paidTowardsScheduleCash,
    ));
  }

  Future<void> refresh() => load();

  Future<bool> settleEarly({
    required int waivedInterestPiasters,
    required String paymentMethod,
    required String pin,
    String? notes,
    DateTime? settledAt,
  }) async {
    emit(state.copyWith(isSettling: true, errorMessage: null));
    final res = await _facade.settleContractEarly(
      contractId: contractId,
      waivedInterestPiasters: waivedInterestPiasters,
      paymentMethod: paymentMethod,
      pin: pin,
      notes: notes,
      settledAt: settledAt,
    );
    return res.fold(
      (failure) {
        emit(state.copyWith(isSettling: false, errorMessage: failure.message));
        return false;
      },
      (_) {
        emit(state.copyWith(isSettling: false));
        load();
        return true;
      },
    );
  }

  Future<bool> cancelContract(String pin) async {
    emit(state.copyWith(isCancelling: true));
    final res = await _facade.cancelContract(contractId: contractId, pin: pin);
    return res.fold(
      (failure) {
        emit(state.copyWith(isCancelling: false, errorMessage: failure.message));
        return false;
      },
      (_) {
        emit(state.copyWith(isCancelling: false));
        load();
        return true;
      },
    );
  }
}

