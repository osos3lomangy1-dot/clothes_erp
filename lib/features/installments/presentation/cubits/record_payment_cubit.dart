import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/features/feature_gate.dart';
import '../../domain/facades/installments_facade.dart';
import '../../domain/services/installment_calculator.dart';

enum RecordPaymentStatus { initial, loading, success, error }

class RecordPaymentState extends Equatable {
  final RecordPaymentStatus status;
  final int remainingPiasters;
  final int monthlyAmountPiasters;
  final int nextInstallmentRemainingPiasters;
  final int? nextInstallmentNumber;
  final DateTime? nextDueDate;
  final bool isPinRequired;
  final bool isSubmitting;
  final String? errorMessage;

  const RecordPaymentState({
    this.status = RecordPaymentStatus.initial,
    this.remainingPiasters = 0,
    this.monthlyAmountPiasters = 0,
    this.nextInstallmentRemainingPiasters = 0,
    this.nextInstallmentNumber,
    this.nextDueDate,
    this.isPinRequired = true,
    this.isSubmitting = false,
    this.errorMessage,
  });

  RecordPaymentState copyWith({
    RecordPaymentStatus? status,
    int? remainingPiasters,
    int? monthlyAmountPiasters,
    int? nextInstallmentRemainingPiasters,
    int? nextInstallmentNumber,
    DateTime? nextDueDate,
    bool? isPinRequired,
    bool? isSubmitting,
    String? errorMessage,
  }) {
    return RecordPaymentState(
      status: status ?? this.status,
      remainingPiasters: remainingPiasters ?? this.remainingPiasters,
      monthlyAmountPiasters: monthlyAmountPiasters ?? this.monthlyAmountPiasters,
      nextInstallmentRemainingPiasters:
          nextInstallmentRemainingPiasters ?? this.nextInstallmentRemainingPiasters,
      nextInstallmentNumber: nextInstallmentNumber ?? this.nextInstallmentNumber,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      isPinRequired: isPinRequired ?? this.isPinRequired,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        remainingPiasters,
        monthlyAmountPiasters,
        nextInstallmentRemainingPiasters,
        nextInstallmentNumber,
        nextDueDate,
        isPinRequired,
        isSubmitting,
        errorMessage,
      ];
}

class RecordPaymentCubit extends Cubit<RecordPaymentState> {
  final String contractId;
  final InstallmentsFacade _facade;
  final FeatureGate _featureGate;

  RecordPaymentCubit({
    required this.contractId,
    required InstallmentsFacade facade,
    required FeatureGate featureGate,
  })  : _facade = facade,
        _featureGate = featureGate,
        super(const RecordPaymentState()) {
    load();
  }

  Future<void> load() async {
    emit(state.copyWith(status: RecordPaymentStatus.loading));

    final contractRes = await _facade.getContract(contractId);
    if (contractRes.isLeft()) {
      emit(state.copyWith(
        status: RecordPaymentStatus.error,
        errorMessage: contractRes.fold((f) => f.message, (_) => ''),
      ));
      return;
    }

    final contract = contractRes.getOrElse(() => throw Exception());

    // Reconstruct schedule & find the actual next unpaid installment
    final paymentsRes = await _facade.listPayments(contractId);
    final payments = paymentsRes.getOrElse(() => []);
    final nonDownPaymentsTotal = payments
        .where((p) => p.receiptNumber != 'DOWN_PAYMENT')
        .fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final totalScheduled = contract.remainingPiasters + nonDownPaymentsTotal;
    final exactTotalInterest =
        (totalScheduled - contract.principalPiasters).clamp(0, totalScheduled);
    final schedule = _facade
        .calculateSchedule(
          principalPiasters: contract.totalPiasters,
          durationMonths: contract.durationMonths,
          interestModel: InstallmentInterestModel.fixed,
          interestValue: exactTotalInterest,
          downPaymentPiasters: contract.downPaymentPiasters,
          startDate: contract.startDate,
        )
        .getOrElse(() => []);
    final allocations = InstallmentCalculator.allocatePaymentsToSchedule(
      schedule: schedule,
      payments: payments,
    );
    final nextUnpaid = allocations.where((a) => !a.isPaid).firstOrNull;

    // Check PIN requirement setting (defaults to true)
    final pinSetting = await _featureGate.getMeta('installments.pin.require');
    final isPinRequired = pinSetting != '0';

    emit(state.copyWith(
      status: RecordPaymentStatus.success,
      remainingPiasters: contract.remainingPiasters,
      monthlyAmountPiasters: contract.monthlyAmountPiasters,
      nextInstallmentRemainingPiasters:
          nextUnpaid?.remainingPiasters ?? contract.monthlyAmountPiasters,
      nextInstallmentNumber: nextUnpaid?.entry.installmentNumber,
      nextDueDate: nextUnpaid?.entry.dueDate ?? contract.endDate,
      isPinRequired: isPinRequired,
    ));
  }

  Future<bool> submit({
    required int amountPiasters,
    required String paymentMethod,
    String? notes,
    required String pin,
    String? receiptNumber,
    DateTime? paidAt,
  }) async {
    if (amountPiasters <= 0) {
      emit(state.copyWith(errorMessage: 'المبلغ يجب أن يكون أكبر من صفر'));
      return false;
    }
    if (amountPiasters > state.remainingPiasters) {
      emit(state.copyWith(errorMessage: 'المبلغ المدخل يتجاوز الرصيد المتبقي'));
      return false;
    }

    emit(state.copyWith(isSubmitting: true, errorMessage: null));

    final res = await _facade.recordPayment(
      contractId: contractId,
      amountPiasters: amountPiasters,
      paymentMethod: paymentMethod,
      notes: notes,
      pin: pin,
      receiptNumber: receiptNumber,
      paidAt: paidAt,
    );

    return res.fold(
      (failure) {
        emit(state.copyWith(isSubmitting: false, errorMessage: failure.message));
        return false;
      },
      (_) {
        emit(state.copyWith(isSubmitting: false));
        return true;
      },
    );
  }
}
