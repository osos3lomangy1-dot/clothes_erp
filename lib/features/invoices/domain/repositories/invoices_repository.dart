import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/invoice_details_entity.dart';

abstract class InvoicesRepository {
  Future<Either<Failure, List<InvoiceDetailsEntity>>> getInvoices({
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? cashierId,
    String? paymentMethod,
    int limit = 100,
  });

  Future<Either<Failure, InvoiceDetailsEntity?>> getInvoiceById(String id);
  Future<Either<Failure, InvoiceDetailsEntity?>> getInvoiceByShortRef(String shortRef);
}

