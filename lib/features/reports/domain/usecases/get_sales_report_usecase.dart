import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/sales_report_entity.dart';
import '../repositories/reports_repository.dart';

@lazySingleton
class GetSalesReportUseCase {
  final ReportsRepository _repository;

  GetSalesReportUseCase(this._repository);

  Future<Either<Failure, SalesReportEntity>> call({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _repository.getSalesReport(startDate: startDate, endDate: endDate);
  }
}

