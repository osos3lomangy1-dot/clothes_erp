import 'package:equatable/equatable.dart';
import '../../domain/entities/shift_entity.dart';
import '../../domain/entities/shift_summary_entity.dart';

enum ShiftStatus { initial, loading, loaded, error }

class ShiftState extends Equatable {
  final ShiftStatus status;
  final ShiftEntity? activeShift;
  final ShiftSummaryEntity? activeSummary;
  final List<ShiftEntity> history;
  final bool shiftsEnabled;
  final String? errorMessage;
  final bool isOperating; // for open/close button spinner

  const ShiftState({
    this.status = ShiftStatus.initial,
    this.activeShift,
    this.activeSummary,
    this.history = const [],
    this.shiftsEnabled = true,
    this.errorMessage,
    this.isOperating = false,
  });

  bool get hasActiveShift => activeShift != null;

  ShiftState copyWith({
    ShiftStatus? status,
    ShiftEntity? activeShift,
    bool clearActiveShift = false,
    ShiftSummaryEntity? activeSummary,
    bool clearActiveSummary = false,
    List<ShiftEntity>? history,
    bool? shiftsEnabled,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isOperating,
  }) {
    return ShiftState(
      status: status ?? this.status,
      activeShift: clearActiveShift ? null : (activeShift ?? this.activeShift),
      activeSummary: clearActiveSummary ? null : (activeSummary ?? this.activeSummary),
      history: history ?? this.history,
      shiftsEnabled: shiftsEnabled ?? this.shiftsEnabled,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isOperating: isOperating ?? this.isOperating,
    );
  }

  @override
  List<Object?> get props => [
        status,
        activeShift,
        activeSummary,
        history,
        shiftsEnabled,
        errorMessage,
        isOperating,
      ];
}

