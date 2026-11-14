import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../installments/domain/entities/installment_summary.dart';
import '../../../installments/domain/facades/installments_facade.dart';

enum InstallmentsReportStatus { initial, loading, success, error }

class MonthlyTrendPoint extends Equatable {
  final DateTime month;
  final int collected;
  const MonthlyTrendPoint({required this.month, required this.collected});

  @override
  List<Object?> get props => [month, collected];
}

class InstallmentsReportState extends Equatable {
  final InstallmentsReportStatus status;
  final InstallmentSummary? summary;
  final List<MonthlyTrendPoint> monthlyTrend;
  final String? errorMessage;

  const InstallmentsReportState({
    this.status = InstallmentsReportStatus.initial,
    this.summary,
    this.monthlyTrend = const [],
    this.errorMessage,
  });

  InstallmentsReportState copyWith({
    InstallmentsReportStatus? status,
    InstallmentSummary? summary,
    List<MonthlyTrendPoint>? monthlyTrend,
    String? errorMessage,
  }) =>
      InstallmentsReportState(
        status: status ?? this.status,
        summary: summary ?? this.summary,
        monthlyTrend: monthlyTrend ?? this.monthlyTrend,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [status, summary, monthlyTrend, errorMessage];
}

@injectable
class InstallmentsReportCubit extends Cubit<InstallmentsReportState> {
  final InstallmentsFacade _facade;
  InstallmentsReportCubit(this._facade) : super(const InstallmentsReportState());

  Future<void> load({required DateTime now}) async {
    emit(state.copyWith(status: InstallmentsReportStatus.loading));

    final summaryResult = await _facade.getSummary(now: now);
    if (summaryResult.isLeft()) {
      summaryResult.fold(
        (f) => emit(state.copyWith(
          status: InstallmentsReportStatus.error,
          errorMessage: f.message,
        )),
        (_) {},
      );
      return;
    }

    final summary = summaryResult.getOrElse(() => const InstallmentSummary.empty());

    // Last 6 months trend
    final trend = <MonthlyTrendPoint>[];
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final r = await _facade.getSummary(now: month);
      r.fold(
        (_) {},
        (s) => trend.add(MonthlyTrendPoint(month: month, collected: s.monthlyCollected)),
      );
    }

    emit(state.copyWith(
      status: InstallmentsReportStatus.success,
      summary: summary,
      monthlyTrend: trend,
    ));
  }
}

