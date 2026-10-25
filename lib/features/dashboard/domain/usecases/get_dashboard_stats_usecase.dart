import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/dashboard_stats_entity.dart';
import '../repositories/dashboard_repository.dart';

@lazySingleton
class GetDashboardStatsUseCase {
  final DashboardRepository _repository;

  GetDashboardStatsUseCase(this._repository);

  Future<Either<Failure, DashboardStatsEntity>> call() {
    return _repository.getDashboardStats();
  }
}
