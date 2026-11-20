import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/smart_inventory_entities.dart';
import '../../domain/repositories/smart_inventory_repository.dart';

enum SmartInventoryStatus { initial, loading, success, error }

class SmartInventoryState extends Equatable {
  final SmartInventoryStatus reorderStatus;
  final List<ReorderSuggestionEntity> reorderSuggestions;
  final int reorderDays;

  final SmartInventoryStatus deadStockStatus;
  final List<DeadStockItemEntity> deadStockItems;
  final int deadStockDormantDays;

  final SmartInventoryStatus cardStatus;
  final String? selectedVariantId;
  final List<StockMovementCardItemEntity> movementCardItems;
  final List<({String id, String label, String sku})> variantsList;

  final String? errorMessage;

  const SmartInventoryState({
    this.reorderStatus = SmartInventoryStatus.initial,
    this.reorderSuggestions = const [],
    this.reorderDays = 30,
    this.deadStockStatus = SmartInventoryStatus.initial,
    this.deadStockItems = const [],
    this.deadStockDormantDays = 60,
    this.cardStatus = SmartInventoryStatus.initial,
    this.selectedVariantId,
    this.movementCardItems = const [],
    this.variantsList = const [],
    this.errorMessage,
  });

  SmartInventoryState copyWith({
    SmartInventoryStatus? reorderStatus,
    List<ReorderSuggestionEntity>? reorderSuggestions,
    int? reorderDays,
    SmartInventoryStatus? deadStockStatus,
    List<DeadStockItemEntity>? deadStockItems,
    int? deadStockDormantDays,
    SmartInventoryStatus? cardStatus,
    String? selectedVariantId,
    List<StockMovementCardItemEntity>? movementCardItems,
    List<({String id, String label, String sku})>? variantsList,
    String? errorMessage,
  }) {
    return SmartInventoryState(
      reorderStatus: reorderStatus ?? this.reorderStatus,
      reorderSuggestions: reorderSuggestions ?? this.reorderSuggestions,
      reorderDays: reorderDays ?? this.reorderDays,
      deadStockStatus: deadStockStatus ?? this.deadStockStatus,
      deadStockItems: deadStockItems ?? this.deadStockItems,
      deadStockDormantDays: deadStockDormantDays ?? this.deadStockDormantDays,
      cardStatus: cardStatus ?? this.cardStatus,
      selectedVariantId: selectedVariantId ?? this.selectedVariantId,
      movementCardItems: movementCardItems ?? this.movementCardItems,
      variantsList: variantsList ?? this.variantsList,
      errorMessage: errorMessage,
    );
  }

  int get totalReorderCostPiasters => reorderSuggestions.fold(
        0,
        (sum, item) => sum + item.totalEstimatedCostPiasters,
      );

  int get totalFrozenCapitalPiasters => deadStockItems.fold(
        0,
        (sum, item) => sum + item.frozenCapitalPiasters,
      );

  int get totalLostRevenuePotentialPiasters => deadStockItems.fold(
        0,
        (sum, item) => sum + item.lostRevenuePotentialPiasters,
      );

  int get totalDeadUnits => deadStockItems.fold(
        0,
        (sum, item) => sum + item.currentStock,
      );

  @override
  List<Object?> get props => [
        reorderStatus,
        reorderSuggestions,
        reorderDays,
        deadStockStatus,
        deadStockItems,
        deadStockDormantDays,
        cardStatus,
        selectedVariantId,
        movementCardItems,
        variantsList,
        errorMessage,
      ];
}

@injectable
class SmartInventoryCubit extends Cubit<SmartInventoryState> {
  final SmartInventoryRepository _repo;

  SmartInventoryCubit(this._repo) : super(const SmartInventoryState()) {
    init();
  }

  Future<void> init() async {
    await Future.wait([
      loadReorderSuggestions(),
      loadDeadStock(),
      loadVariantsForPicker(),
    ]);
  }

  Future<void> loadReorderSuggestions({int? days}) async {
    final d = days ?? state.reorderDays;
    emit(state.copyWith(
      reorderStatus: SmartInventoryStatus.loading,
      reorderDays: d,
    ));

    final res = await _repo.getReorderSuggestions(days: d);
    res.fold(
      (failure) => emit(state.copyWith(
        reorderStatus: SmartInventoryStatus.error,
        errorMessage: failure.message,
      )),
      (suggestions) => emit(state.copyWith(
        reorderStatus: SmartInventoryStatus.success,
        reorderSuggestions: suggestions,
      )),
    );
  }

  Future<void> loadDeadStock({int? dormantDays}) async {
    final d = dormantDays ?? state.deadStockDormantDays;
    emit(state.copyWith(
      deadStockStatus: SmartInventoryStatus.loading,
      deadStockDormantDays: d,
    ));

    final res = await _repo.getDeadStock(dormantDays: d);
    res.fold(
      (failure) => emit(state.copyWith(
        deadStockStatus: SmartInventoryStatus.error,
        errorMessage: failure.message,
      )),
      (items) => emit(state.copyWith(
        deadStockStatus: SmartInventoryStatus.success,
        deadStockItems: items,
      )),
    );
  }

  Future<void> loadVariantsForPicker() async {
    final res = await _repo.getVariantsForCardPicker();
    res.fold(
      (_) => null,
      (variants) {
        emit(state.copyWith(variantsList: variants));
        if (state.selectedVariantId == null && variants.isNotEmpty) {
          loadStockMovementCard(variants.first.id);
        }
      },
    );
  }

  Future<void> loadStockMovementCard(String variantId) async {
    emit(state.copyWith(
      cardStatus: SmartInventoryStatus.loading,
      selectedVariantId: variantId,
    ));

    final res = await _repo.getStockMovementCard(variantId);
    res.fold(
      (failure) => emit(state.copyWith(
        cardStatus: SmartInventoryStatus.error,
        errorMessage: failure.message,
      )),
      (items) => emit(state.copyWith(
        cardStatus: SmartInventoryStatus.success,
        movementCardItems: items,
      )),
    );
  }
}

