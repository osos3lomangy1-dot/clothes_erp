import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_local_data_source.dart';

@LazySingleton(as: InventoryRepository)
class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryLocalDataSource _localDataSource;

  InventoryRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<VariantEntity>>> getAllInventory() async {
    try {
      final items = await _localDataSource.getInventoryDetails();
      final entities = items.map((item) => VariantEntity(
        id: item.variantId,
        productId: item.productId,
        productCode: item.sku,
        color: item.color,
        size: item.size,
        quantity: item.quantity,
        costPrice: item.costPrice,
        salePrice: item.sellPrice,
        minStock: 5,
        createdAt: DateTime.now(),
        productName: item.productName,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<VariantEntity>>> getLowStockInventory() async {
    try {
      final items = await _localDataSource.getInventoryDetails(lowStockOnly: true);
      final entities = items.map((item) => VariantEntity(
        id: item.variantId,
        productId: item.productId,
        productCode: item.sku,
        color: item.color,
        size: item.size,
        quantity: item.quantity,
        costPrice: item.costPrice,
        salePrice: item.sellPrice,
        minStock: 5,
        createdAt: DateTime.now(),
        productName: item.productName,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
