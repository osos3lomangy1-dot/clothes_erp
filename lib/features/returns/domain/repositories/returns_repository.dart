import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../pos/domain/entities/sale_entity.dart';
import '../entities/return_entity.dart';
import '../entities/return_item_entity.dart';

abstract class ReturnsRepository {
  Future<Either<Failure, void>> processReturn({
    required String saleId,
    required List<ReturnItemEntity> items,
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  });
  Future<Either<Failure, List<SaleEntity>>> getRecentSales({int limit = 20});
  Future<Either<Failure, List<ReturnItemEntity>>> getSaleItems(String saleId);
  Future<Either<Failure, SaleEntity?>> getSaleByIdOrRef(String query);
  Future<Either<Failure, List<ReturnEntity>>> getReturnsHistory({int limit = 50});
}
