import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../data/datasources/purchases_local_data_source.dart';
import '../entities/purchase_entity.dart';
import '../entities/supplier_entity.dart';
import '../entities/supplier_payment_entity.dart';

abstract class PurchasesRepository {
  // Suppliers
  Future<Either<Failure, List<SupplierEntity>>> getSuppliers();
  Future<Either<Failure, SupplierEntity>> addSupplier({
    required String name,
    String? phone,
    String? companyName,
    String? address,
  });
  Future<Either<Failure, SupplierEntity>> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? companyName,
    String? address,
  });
  Future<Either<Failure, void>> deleteSupplier(String id);

  // Purchases
  Future<Either<Failure, List<PurchaseEntity>>> getPurchases({
    String? supplierId,
    String? paymentStatus,
  });
  Future<Either<Failure, PurchaseEntity>> createPurchaseInvoice({
    required String supplierId,
    String? invoiceNumber,
    required DateTime purchaseDate,
    required int paidAmount,
    String? notes,
    required List<PurchaseItemDraft> items,
    required String userId,
  });

  // Supplier Payments
  Future<Either<Failure, SupplierPaymentEntity>> addSupplierPayment({
    required String supplierId,
    String? purchaseId,
    required int amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? referenceNumber,
    String? notes,
    required String userId,
  });
  Future<Either<Failure, List<SupplierPaymentEntity>>> getSupplierPayments({
    String? supplierId,
    String? purchaseId,
  });
}

