import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/di/injection.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/usecases/get_dashboard_stats_usecase.dart';
import 'dashboard_state.dart';

@injectable
class DashboardCubit extends Cubit<DashboardState> {
  final GetDashboardStatsUseCase _getDashboardStatsUseCase;
  final DashboardRepository? _dashboardRepository;
  StreamSubscription? _updateSub;
  Timer? _debounceTimer;

  DashboardCubit(
    this._getDashboardStatsUseCase, {
    @ignoreParam DashboardRepository? dashboardRepository,
  })  : _dashboardRepository = dashboardRepository,
        super(const DashboardState()) {
    loadStats();
    _initAutoRefresh();
  }

  void _initAutoRefresh() {
    try {
      final repo = _dashboardRepository ??
          (getIt.isRegistered<DashboardRepository>()
              ? getIt<DashboardRepository>()
              : null);
      if (repo != null) {
        _updateSub = repo.watchDashboardUpdates().listen((_) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 350), () {
            if (!isClosed) {
              loadStats(silent: true);
            }
          });
        });
      }
    } catch (_) {}
  }

  Future<void> loadStats({bool silent = false}) async {
    if (!silent || state.stats == null) {
      emit(state.copyWith(status: DashboardStatus.loading));
    }
    final result = await _getDashboardStatsUseCase();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(
        status: DashboardStatus.failure,
        errorMessage: failure.message,
      )),
      (stats) => emit(state.copyWith(
        status: DashboardStatus.success,
        stats: stats,
      )),
    );
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _updateSub?.cancel();
    return super.close();
  }
}
