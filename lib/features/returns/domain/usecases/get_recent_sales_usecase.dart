import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../pos/domain/entities/sale_entity.dart';
import '../entities/return_item_entity.dart';
import '../repositories/returns_repository.dart';

@lazySingleton
class GetRecentSalesUseCase {
  final ReturnsRepository _repository;

  GetRecentSalesUseCase(this._repository);

  Future<Either<Failure, List<SaleEntity>>> getRecentSales({int limit = 20}) {
    return _repository.getRecentSales(limit: limit);
  }

  Future<Either<Failure, List<ReturnItemEntity>>> getSaleItems(String saleId) {
    return _repository.getSaleItems(saleId);
  }

  Future<Either<Failure, SaleEntity?>> getSaleByIdOrRef(String query) {
    return _repository.getSaleByIdOrRef(query);
  }
}

