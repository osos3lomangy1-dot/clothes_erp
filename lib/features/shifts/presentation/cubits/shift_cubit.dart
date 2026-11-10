import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/shift_entity.dart';
import '../../domain/repositories/shift_repository.dart';
import 'shift_state.dart';

@injectable
class ShiftCubit extends Cubit<ShiftState> {
  final ShiftRepository _repository;

  ShiftCubit(this._repository) : super(const ShiftState());

  Future<void> loadShiftData() async {
    emit(state.copyWith(status: ShiftStatus.loading));

    final enabledRes = await _repository.isShiftsEnabled();
    final isEnabled = enabledRes.getOrElse(() => true);

    final activeRes = await _repository.getActiveShift();
    ShiftEntity? activeShift;
    activeRes.fold((_) {}, (s) => activeShift = s);

    final historyRes = await _repository.getShiftHistory();
    final history = historyRes.getOrElse(() => []);

    if (activeShift != null) {
      final summaryRes = await _repository.getShiftSummary(activeShift!.id);
      summaryRes.fold(
        (failure) {
          emit(state.copyWith(
            status: ShiftStatus.loaded,
            activeShift: activeShift,
            history: history,
            shiftsEnabled: isEnabled,
          ));
        },
        (summary) {
          emit(state.copyWith(
            status: ShiftStatus.loaded,
            activeShift: activeShift,
            activeSummary: summary,
            history: history,
            shiftsEnabled: isEnabled,
          ));
        },
      );
    } else {
      emit(state.copyWith(
        status: ShiftStatus.loaded,
        clearActiveShift: true,
        clearActiveSummary: true,
        history: history,
        shiftsEnabled: isEnabled,
      ));
    }
  }

  Future<bool> openShift({
    required int openingBalance,
    required String cashierId,
    String? cashierName,
  }) async {
    emit(state.copyWith(isOperating: true, clearErrorMessage: true));
    final result = await _repository.openShift(
      openingBalance: openingBalance,
      cashierId: cashierId,
      cashierName: cashierName,
    );

    return result.fold(
      (failure) {
        emit(state.copyWith(
          isOperating: false,
          errorMessage: failure.message,
        ));
        return false;
      },
      (shift) async {
        emit(state.copyWith(isOperating: false));
        await loadShiftData();
        return true;
      },
    );
  }

  Future<bool> closeShift({
    required int countedBalance,
    required String userId,
  }) async {
    emit(state.copyWith(isOperating: true, clearErrorMessage: true));
    final result = await _repository.closeShift(
      countedBalance: countedBalance,
      shiftId: state.activeShift?.id,
      userId: userId,
    );

    return result.fold(
      (failure) {
        emit(state.copyWith(
          isOperating: false,
          errorMessage: failure.message,
        ));
        return false;
      },
      (closedShift) async {
        emit(state.copyWith(isOperating: false));
        await loadShiftData();
        return true;
      },
    );
  }

  Future<void> toggleShiftsEnabled(bool enabled) async {
    final result = await _repository.setShiftsEnabled(enabled);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => emit(state.copyWith(shiftsEnabled: enabled)),
    );
  }
}

