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
  final List<InstallmentPaymentEntity> payments;
  final bool isCancelling;
  final String? errorMessage;

  const InstallmentDetailState({
    this.status = InstallmentDetailStatus.initial,
    this.contract,
    this.customerName,
    this.schedule = const [],
    this.payments = const [],
    this.isCancelling = false,
    this.errorMessage,
  });

  InstallmentDetailState copyWith({
    InstallmentDetailStatus? status,
    CustomerInstallmentEntity? contract,
    String? customerName,
    List<InstallmentScheduleEntry>? schedule,
    List<InstallmentPaymentEntity>? payments,
    bool? isCancelling,
    String? errorMessage,
  }) {
    return InstallmentDetailState(
      status: status ?? this.status,
      contract: contract ?? this.contract,
      customerName: customerName ?? this.customerName,
      schedule: schedule ?? this.schedule,
      payments: payments ?? this.payments,
      isCancelling: isCancelling ?? this.isCancelling,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        contract,
        customerName,
        schedule,
        payments,
        isCancelling,
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

    // Calculate schedule
    final scheduleRes = _facade.calculateSchedule(
      principalPiasters: contract.totalPiasters,
      durationMonths: contract.durationMonths,
      interestModel: InstallmentInterestModel.fixed, // standard baseline calculation
      interestValue: contract.interestBp,
      downPaymentPiasters: contract.downPaymentPiasters,
      startDate: contract.startDate,
    );
    final schedule = scheduleRes.getOrElse(() => []);

    emit(state.copyWith(
      status: InstallmentDetailStatus.success,
      contract: contract,
      customerName: customerName,
      schedule: schedule,
      payments: payments,
    ));
  }

  Future<void> refresh() => load();

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

