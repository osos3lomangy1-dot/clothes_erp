import 'package:equatable/equatable.dart';
import '../../domain/entities/dashboard_stats_entity.dart';

enum DashboardStatus { initial, loading, success, failure }

class DashboardState extends Equatable {
  final DashboardStatus status;
  final DashboardStatsEntity? stats;
  final String? errorMessage;

  const DashboardState({
    this.status = DashboardStatus.initial,
    this.stats,
    this.errorMessage,
  });

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardStatsEntity? stats,
    String? errorMessage,
  }) {
    return DashboardState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, stats, errorMessage];
}
