import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/utils/logging.dart';
import '../../domain/usecases/get_dashboard_stats_usecase.dart';
import 'dashboard_state.dart';

@injectable
class DashboardCubit extends Cubit<DashboardState> {
  final GetDashboardStatsUseCase _getDashboardStatsUseCase;

  DashboardCubit(this._getDashboardStatsUseCase) : super(const DashboardState()) {
    loadStats();
  }

  Future<void> loadStats() async {
    emit(state.copyWith(status: DashboardStatus.loading));
    final result = await _getDashboardStatsUseCase();
    result.fold(
      (failure) => emit(state.copyWith(status: DashboardStatus.failure, errorMessage: failure.message)),
      (stats) => emit(state.copyWith(status: DashboardStatus.success, stats: stats)),
    );
  }
}
