import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../../domain/repositories/invoices_repository.dart';
import '../datasources/invoices_local_data_source.dart';

@LazySingleton(as: InvoicesRepository)
class InvoicesRepositoryImpl implements InvoicesRepository {
  final InvoicesLocalDataSource _localDataSource;

  InvoicesRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<InvoiceDetailsEntity>>> getInvoices({
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? cashierId,
    String? paymentMethod,
    int limit = 100,
  }) async {
    try {
      final list = await _localDataSource.getInvoices(
        search: search,
        fromDate: fromDate,
        toDate: toDate,
        cashierId: cashierId,
        paymentMethod: paymentMethod,
        limit: limit,
      );
      return Right(list);
    } catch (e) {
      return Left(CacheFailure('فشل جلب فواتير المبيعات: $e'));
    }
  }

  @override
  Future<Either<Failure, InvoiceDetailsEntity?>> getInvoiceById(String id) async {
    try {
      final invoice = await _localDataSource.getInvoiceById(id);
      return Right(invoice);
    } catch (e) {
      return Left(CacheFailure('فشل جلب تفاصيل الفاتورة: $e'));
    }
  }

  @override
  Future<Either<Failure, InvoiceDetailsEntity?>> getInvoiceByShortRef(String shortRef) async {
    try {
      final invoice = await _localDataSource.getInvoiceByShortRef(shortRef);
      return Right(invoice);
    } catch (e) {
      return Left(CacheFailure('فشل جلب الفاتورة برقمها: $e'));
    }
  }
}

