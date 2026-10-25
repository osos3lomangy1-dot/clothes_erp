import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/inventory_log_entity.dart';
import '../../domain/repositories/inventory_log_repository.dart';

enum InventoryLogStatus { initial, loading, success, error }

class InventoryLogState extends Equatable {
  final InventoryLogStatus status;
  final List<InventoryLogEntity> logs;
  final String? errorMessage;

  const InventoryLogState({
    this.status = InventoryLogStatus.initial,
    this.logs = const [],
    this.errorMessage,
  });

  InventoryLogState copyWith({
    InventoryLogStatus? status,
    List<InventoryLogEntity>? logs,
    String? errorMessage,
  }) {
    return InventoryLogState(
      status: status ?? this.status,
      logs: logs ?? this.logs,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, logs, errorMessage];
}

@injectable
class InventoryLogCubit extends Cubit<InventoryLogState> {
  final InventoryLogRepository _repository;

  InventoryLogCubit(this._repository) : super(const InventoryLogState()) {
    loadLogs();
  }

  Future<void> loadLogs() async {
    emit(state.copyWith(status: InventoryLogStatus.loading));
    final result = await _repository.getLogs();
    result.fold(
      (failure) => emit(state.copyWith(status: InventoryLogStatus.error, errorMessage: failure.message)),
      (logs) => emit(state.copyWith(status: InventoryLogStatus.success, logs: logs)),
    );
  }
}
