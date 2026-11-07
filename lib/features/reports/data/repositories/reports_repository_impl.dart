import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/sales_report_entity.dart';
import '../../domain/repositories/reports_repository.dart';
import '../datasources/reports_local_data_source.dart';

@LazySingleton(as: ReportsRepository)
class ReportsRepositoryImpl implements ReportsRepository {
  final ReportsLocalDataSource _localDataSource;

  ReportsRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, SalesReportEntity>> getSalesReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final report = await _localDataSource.getSalesReport(
        startDate: startDate,
        endDate: endDate,
      );
      return Right(report);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}

