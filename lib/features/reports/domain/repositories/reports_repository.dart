import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/sales_report_entity.dart';

abstract class ReportsRepository {
  Future<Either<Failure, SalesReportEntity>> getSalesReport({
    required DateTime startDate,
    required DateTime endDate,
  });
}

