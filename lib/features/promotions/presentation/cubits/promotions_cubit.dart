import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/promotion.dart';
import '../../domain/repositories/promotions_repository.dart';

enum PromotionsStatus { initial, loading, success, error }

class PromotionsState extends Equatable {
  final PromotionsStatus status;
  final List<Promotion> promotions;
  final String? errorMessage;

  const PromotionsState({
    this.status = PromotionsStatus.initial,
    this.promotions = const [],
    this.errorMessage,
  });

  PromotionsState copyWith({
    PromotionsStatus? status,
    List<Promotion>? promotions,
    String? errorMessage,
  }) =>
      PromotionsState(
        status: status ?? this.status,
        promotions: promotions ?? this.promotions,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [status, promotions, errorMessage];
}

@injectable
class PromotionsCubit extends Cubit<PromotionsState> {
  final PromotionsRepository _repository;

  PromotionsCubit(this._repository) : super(const PromotionsState());

  Future<void> loadAll() async {
    emit(state.copyWith(status: PromotionsStatus.loading));
    final result = await _repository.listPromotions(includeInactive: true);
    result.fold(
      (f) => emit(state.copyWith(
          status: PromotionsStatus.error, errorMessage: f.message)),
      (list) => emit(state.copyWith(
          status: PromotionsStatus.success, promotions: list)),
    );
  }

  Future<bool> createPromotion(Promotion p) async {
    final result = await _repository.createPromotion(p);
    return await result.fold(
      (f) async {
        emit(state.copyWith(errorMessage: f.message));
        return false;
      },
      (_) async {
        await loadAll();
        return true;
      },
    );
  }

  Future<bool> updatePromotion(Promotion p) async {
    final result = await _repository.updatePromotion(p);
    return await result.fold(
      (f) async {
        emit(state.copyWith(errorMessage: f.message));
        return false;
      },
      (_) async {
        await loadAll();
        return true;
      },
    );
  }

  Future<bool> deactivatePromotion(String id) async {
    final result = await _repository.deactivatePromotion(id);
    return await result.fold(
      (f) async {
        emit(state.copyWith(errorMessage: f.message));
        return false;
      },
      (_) async {
        await loadAll();
        return true;
      },
    );
  }

  Future<bool> deletePromotion(String id) async {
    final result = await _repository.deletePromotion(id);
    return await result.fold(
      (f) async {
        emit(state.copyWith(errorMessage: f.message));
        return false;
      },
      (_) async {
        await loadAll();
        return true;
      },
    );
  }
}

