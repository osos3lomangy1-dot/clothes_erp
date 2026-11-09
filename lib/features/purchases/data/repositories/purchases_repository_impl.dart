import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/supplier_entity.dart';
import '../../domain/entities/supplier_payment_entity.dart';
import '../../domain/repositories/purchases_repository.dart';
import '../datasources/purchases_local_data_source.dart';

@LazySingleton(as: PurchasesRepository)
class PurchasesRepositoryImpl implements PurchasesRepository {
  final PurchasesLocalDataSource _localDataSource;

  PurchasesRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<SupplierEntity>>> getSuppliers() async {
    try {
      final list = await _localDataSource.getSuppliers();
      return Right(list);
    } catch (e) {
      return Left(CacheFailure('فشل جلب قائمة الموردين: $e'));
    }
  }

  @override
  Future<Either<Failure, SupplierEntity>> addSupplier({
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) async {
    try {
      final supplier = await _localDataSource.addSupplier(
        name: name,
        phone: phone,
        companyName: companyName,
        address: address,
      );
      return Right(supplier);
    } catch (e) {
      return Left(CacheFailure('فشل إضافة المورد: $e'));
    }
  }

  @override
  Future<Either<Failure, SupplierEntity>> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) async {
    try {
      final supplier = await _localDataSource.updateSupplier(
        id: id,
        name: name,
        phone: phone,
        companyName: companyName,
        address: address,
      );
      return Right(supplier);
    } catch (e) {
      return Left(CacheFailure('فشل تعديل بيانات المورد: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteSupplier(String id) async {
    try {
      await _localDataSource.deleteSupplier(id);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('فشل حذف المورد: $e'));
    }
  }

  @override
  Future<Either<Failure, List<PurchaseEntity>>> getPurchases({
    String? supplierId,
    String? paymentStatus,
  }) async {
    try {
      final list = await _localDataSource.getPurchases(
        supplierId: supplierId,
        paymentStatus: paymentStatus,
      );
      return Right(list);
    } catch (e) {
      return Left(CacheFailure('فشل جلب فواتير المشتريات: $e'));
    }
  }

  @override
  Future<Either<Failure, PurchaseEntity>> createPurchaseInvoice({
    required String supplierId,
    String? invoiceNumber,
    required DateTime purchaseDate,
    required int paidAmount,
    String? notes,
    required List<PurchaseItemDraft> items,
    required String userId,
  }) async {
    try {
      final purchase = await _localDataSource.createPurchaseInvoice(
        supplierId: supplierId,
        invoiceNumber: invoiceNumber,
        purchaseDate: purchaseDate,
        paidAmount: paidAmount,
        notes: notes,
        items: items,
        userId: userId,
      );
      return Right(purchase);
    } catch (e) {
      return Left(CacheFailure('فشل إنشاء فاتورة المشتريات: $e'));
    }
  }

  @override
  Future<Either<Failure, SupplierPaymentEntity>> addSupplierPayment({
    required String supplierId,
    String? purchaseId,
    required int amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? referenceNumber,
    String? notes,
    required String userId,
  }) async {
    try {
      final payment = await _localDataSource.addSupplierPayment(
        supplierId: supplierId,
        purchaseId: purchaseId,
        amount: amount,
        paymentDate: paymentDate,
        paymentMethod: paymentMethod,
        referenceNumber: referenceNumber,
        notes: notes,
        userId: userId,
      );
      return Right(payment);
    } catch (e) {
      return Left(CacheFailure('فشل تسجيل دفعة المورد: $e'));
    }
  }

  @override
  Future<Either<Failure, List<SupplierPaymentEntity>>> getSupplierPayments({
    String? supplierId,
    String? purchaseId,
  }) async {
    try {
      final list = await _localDataSource.getSupplierPayments(
        supplierId: supplierId,
        purchaseId: purchaseId,
      );
      return Right(list);
    } catch (e) {
      return Left(CacheFailure('فشل جلب دفعات المورد: $e'));
    }
  }
}

