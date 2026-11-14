import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/installment_plan_entity.dart';
import '../../domain/facades/installments_facade.dart';

enum InstallmentPlansStatus { initial, loading, success, error }

class InstallmentPlansState extends Equatable {
  final InstallmentPlansStatus status;
  final List<InstallmentPlanEntity> plans;
  final bool isSubmitting;
  final String? errorMessage;

  const InstallmentPlansState({
    this.status = InstallmentPlansStatus.initial,
    this.plans = const [],
    this.isSubmitting = false,
    this.errorMessage,
  });

  InstallmentPlansState copyWith({
    InstallmentPlansStatus? status,
    List<InstallmentPlanEntity>? plans,
    bool? isSubmitting,
    String? errorMessage,
  }) {
    return InstallmentPlansState(
      status: status ?? this.status,
      plans: plans ?? this.plans,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, plans, isSubmitting, errorMessage];
}

@injectable
class InstallmentPlansCubit extends Cubit<InstallmentPlansState> {
  final InstallmentsFacade _facade;

  InstallmentPlansCubit(this._facade) : super(const InstallmentPlansState()) {
    loadPlans();
  }

  Future<void> loadPlans() async {
    emit(state.copyWith(status: InstallmentPlansStatus.loading));
    final res = await _facade.listPlans();
    res.fold(
      (failure) => emit(state.copyWith(
        status: InstallmentPlansStatus.error,
        errorMessage: failure.message,
      )),
      (plans) => emit(state.copyWith(
        status: InstallmentPlansStatus.success,
        plans: plans,
      )),
    );
  }

  Future<bool> createPlan({
    required String name,
    String? description,
    required int durationMonths,
    required int downPaymentPiasters,
    required int interestBp,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    final res = await _facade.createPlan(
      name: name,
      description: description,
      durationMonths: durationMonths,
      downPaymentPiasters: downPaymentPiasters,
      interestBp: interestBp,
    );

    return res.fold(
      (failure) {
        emit(state.copyWith(isSubmitting: false, errorMessage: failure.message));
        return false;
      },
      (_) {
        emit(state.copyWith(isSubmitting: false));
        loadPlans();
        return true;
      },
    );
  }

  Future<bool> updatePlan(InstallmentPlanEntity plan) async {
    emit(state.copyWith(isSubmitting: true));
    final res = await _facade.updatePlan(plan);
    return res.fold(
      (failure) {
        emit(state.copyWith(isSubmitting: false, errorMessage: failure.message));
        return false;
      },
      (_) {
        emit(state.copyWith(isSubmitting: false));
        loadPlans();
        return true;
      },
    );
  }

  Future<bool> deactivatePlan(String planId) async {
    emit(state.copyWith(isSubmitting: true));
    final res = await _facade.deactivatePlan(planId);
    return res.fold(
      (failure) {
        emit(state.copyWith(isSubmitting: false, errorMessage: failure.message));
        return false;
      },
      (_) {
        emit(state.copyWith(isSubmitting: false));
        loadPlans();
        return true;
      },
    );
  }
}

