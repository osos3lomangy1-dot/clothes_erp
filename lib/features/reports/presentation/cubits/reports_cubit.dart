import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_sales_report_usecase.dart';
import 'reports_state.dart';

@injectable
class ReportsCubit extends Cubit<ReportsState> {
  final GetSalesReportUseCase _getSalesReportUseCase;

  ReportsCubit(this._getSalesReportUseCase) : super(ReportsInitial());

  Future<void> loadReport(DateTime startDate, DateTime endDate) async {
    emit(ReportsLoading());
    final result = await _getSalesReportUseCase(
      startDate: startDate,
      endDate: endDate,
    );
    result.fold(
      (failure) => emit(ReportsError(failure.message)),
      (report) => emit(ReportsLoaded(report)),
    );
  }
}

