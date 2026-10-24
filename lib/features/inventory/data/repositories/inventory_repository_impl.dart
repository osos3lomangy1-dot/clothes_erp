import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_data_source.dart';

@LazySingleton(as: InventoryRepository)
class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryRemoteDataSource _remoteDataSource;

  InventoryRepositoryImpl(this._remoteDataSource);

  @override
  Future<Either<Failure, List<VariantEntity>>> getAllInventory() async {
    try {
      final result = await _remoteDataSource.getAllInventory();
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<VariantEntity>>> getLowStockInventory() async {
    try {
      final result = await _remoteDataSource.getLowStockInventory();
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
