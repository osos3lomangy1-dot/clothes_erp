import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../pos/domain/entities/sale_entity.dart';
import '../../domain/entities/return_item_entity.dart';
import '../../domain/repositories/returns_repository.dart';
import '../datasources/returns_local_data_source.dart';

@LazySingleton(as: ReturnsRepository)
class ReturnsRepositoryImpl implements ReturnsRepository {
  final ReturnsLocalDataSource _localDataSource;

  ReturnsRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, void>> processReturn({
    required String saleId,
    required List<ReturnItemEntity> items,
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  }) async {
    try {
      await _localDataSource.processReturn(
        saleId: saleId,
        items: items,
        reason: reason,
        userId: userId,
        paymentMethod: paymentMethod,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<SaleEntity>>> getRecentSales({int limit = 20}) async {
    try {
      final rows = await _localDataSource.getRecentSales(limit: limit);
      final entities = rows
          .map((s) => SaleEntity(
                id: s.id,
                date: s.date,
                cashierId: s.cashierId,
                subtotal: s.subtotal.toDouble(),
                discount: s.discountAmount.toDouble(),
                total: s.total.toDouble(),
                paymentMethod: s.paymentMethod,
                items: const [],
              ))
          .toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ReturnItemEntity>>> getSaleItems(String saleId) async {
    try {
      final rows = await _localDataSource.getSaleItems(saleId);
      final entities = rows
          .map((si) => ReturnItemEntity(
                id: si.id,
                saleItemId: si.id,
                variantId: si.variantId,
                productName: si.productName,
                color: si.color,
                size: si.size,
                maxQty: si.qty,
                qty: si.qty,
                refundUnitPrice: si.priceSnapshot,
              ))
          .toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, SaleEntity?>> getSaleByIdOrRef(String query) async {
    try {
      final s = await _localDataSource.getSaleByIdOrRef(query);
      if (s == null) return const Right(null);
      return Right(SaleEntity(
        id: s.id,
        date: s.date,
        cashierId: s.cashierId,
        subtotal: s.subtotal.toDouble(),
        discount: s.discountAmount.toDouble(),
        total: s.total.toDouble(),
        paymentMethod: s.paymentMethod,
        items: const [],
      ));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}

