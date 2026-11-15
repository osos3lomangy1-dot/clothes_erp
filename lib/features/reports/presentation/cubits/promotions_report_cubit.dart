import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../promotions/domain/entities/promotion_report_entity.dart';
import '../../../promotions/domain/repositories/promotions_repository.dart';

enum PromotionsReportStatus { initial, loading, success, error }

class PromotionsReportState extends Equatable {
  final PromotionsReportStatus status;
  final PromotionReportEntity? report;
  final String? errorMessage;

  const PromotionsReportState({
    this.status = PromotionsReportStatus.initial,
    this.report,
    this.errorMessage,
  });

  PromotionsReportState copyWith({
    PromotionsReportStatus? status,
    PromotionReportEntity? report,
    String? errorMessage,
  }) =>
      PromotionsReportState(
        status: status ?? this.status,
        report: report ?? this.report,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [status, report, errorMessage];
}

@injectable
class PromotionsReportCubit extends Cubit<PromotionsReportState> {
  final PromotionsRepository _repository;

  PromotionsReportCubit(this._repository)
      : super(const PromotionsReportState());

  Future<void> load({DateTime? startDate, DateTime? endDate}) async {
    emit(state.copyWith(status: PromotionsReportStatus.loading));
    final result = await _repository.getPromotionReport(
      startDate: startDate,
      endDate: endDate,
    );
    result.fold(
      (f) => emit(state.copyWith(
        status: PromotionsReportStatus.error,
        errorMessage: f.message,
      )),
      (report) => emit(state.copyWith(
        status: PromotionsReportStatus.success,
        report: report,
      )),
    );
  }
}

