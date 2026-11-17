import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/inventory_log_entity.dart';
import '../../domain/repositories/inventory_log_repository.dart';

enum InventoryLogStatus { initial, loading, success, error }

class InventoryLogState extends Equatable {
  final InventoryLogStatus status;
  final List<InventoryLogEntity> allLogs;
  final List<InventoryLogEntity> logs;
  final String searchQuery;
  final String selectedType; // 'all', 'in', 'out', 'receive', 'sale', 'return', 'adjustment'
  final String? errorMessage;

  const InventoryLogState({
    this.status = InventoryLogStatus.initial,
    this.allLogs = const [],
    this.logs = const [],
    this.searchQuery = '',
    this.selectedType = 'all',
    this.errorMessage,
  });

  InventoryLogState copyWith({
    InventoryLogStatus? status,
    List<InventoryLogEntity>? allLogs,
    List<InventoryLogEntity>? logs,
    String? searchQuery,
    String? selectedType,
    String? errorMessage,
  }) {
    return InventoryLogState(
      status: status ?? this.status,
      allLogs: allLogs ?? this.allLogs,
      logs: logs ?? this.logs,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedType: selectedType ?? this.selectedType,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, allLogs, logs, searchQuery, selectedType, errorMessage];
}

@injectable
class InventoryLogCubit extends Cubit<InventoryLogState> {
  final InventoryLogRepository _repository;
  Timer? _debounceTimer;

  InventoryLogCubit(this._repository) : super(const InventoryLogState()) {
    loadLogs();
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }

  Future<void> loadLogs() async {
    emit(state.copyWith(status: InventoryLogStatus.loading));
    final result = await _repository.getLogs();
    result.fold(
      (failure) => emit(state.copyWith(status: InventoryLogStatus.error, errorMessage: failure.message)),
      (logs) {
        final filtered = _applyFilters(logs, state.searchQuery, state.selectedType);
        emit(state.copyWith(
          status: InventoryLogStatus.success,
          allLogs: logs,
          logs: filtered,
        ));
      },
    );
  }

  void onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final filtered = _applyFilters(state.allLogs, query, state.selectedType);
      emit(state.copyWith(searchQuery: query, logs: filtered));
    });
  }

  void onTypeFilterChanged(String type) {
    final filtered = _applyFilters(state.allLogs, state.searchQuery, type);
    emit(state.copyWith(selectedType: type, logs: filtered));
  }

  List<InventoryLogEntity> _applyFilters(
    List<InventoryLogEntity> list,
    String query,
    String typeFilter,
  ) {
    var result = list;

    // Type filter
    if (typeFilter != 'all') {
      if (typeFilter == 'in') {
        result = result
            .where((l) =>
                l.type == 'in' ||
                l.type == 'receive' ||
                l.type == 'return' ||
                l.type == 'return_')
            .toList();
      } else if (typeFilter == 'out') {
        result = result
            .where((l) =>
                l.type == 'out' ||
                l.type == 'sale' ||
                l.type == 'purchase_return')
            .toList();
      } else if (typeFilter == 'return') {
        result = result
            .where((l) =>
                l.type == 'return' ||
                l.type == 'return_' ||
                l.type == 'purchase_return')
            .toList();
      } else {
        result = result.where((l) => l.type == typeFilter).toList();
      }
    }

    // Search query filter (search by product name, variant size, user name, or ID)
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((l) {
        final pName = (l.productName ?? '').toLowerCase();
        final size = (l.variantSize ?? '').toLowerCase();
        final color = (l.variantColor ?? '').toLowerCase();
        final uName = (l.userName ?? '').toLowerCase();
        final pId = l.productId.toLowerCase();
        final vId = (l.variantId ?? '').toLowerCase();

        return pName.contains(q) ||
            size.contains(q) ||
            color.contains(q) ||
            uName.contains(q) ||
            pId.contains(q) ||
            vId.contains(q);
      }).toList();
    }

    return result;
  }
}
