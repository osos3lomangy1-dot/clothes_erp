import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../product_variants/domain/repositories/variant_repository.dart';
import '../datasources/variant_local_data_source.dart';

@LazySingleton(as: VariantRepository)
class VariantRepositoryImpl implements VariantRepository {
  final VariantLocalDataSource _localDataSource;

  VariantRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<VariantEntity>>> getVariants(String productId) async {
    try {
      final rows = await _localDataSource.getVariants(productId);
      final entities = rows.map((r) => VariantEntity(
        id: r.id,
        productId: r.productId,
        productCode: r.sku,
        color: r.color,
        size: r.size,
        quantity: r.quantity,
        costPrice: r.costPrice,
        salePrice: r.sellPrice,
        minStock: 5,
        
        createdAt: r.createdAt,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addVariant(VariantEntity variant) async {
    try {
      await _localDataSource.createVariant(
        productId: variant.productId,
        sku: variant.productCode,
        color: variant.color,
        size: variant.size,
        costPrice: variant.costPrice,
        sellPrice: variant.salePrice,
        
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateVariant(VariantEntity variant) async {
    try {
      await _localDataSource.updateVariant(variant.id,
        costPrice: variant.costPrice,
        sellPrice: variant.salePrice,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteVariant(String id) async {
    try {
      await _localDataSource.softDeleteVariant(id);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  @override
  Future<Either<Failure, List<VariantEntity>>> searchVariants(String query) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, List<VariantEntity>>> getAllVariants() async {
    try {
      final rows = await _localDataSource.getAllVariants();
      final entities = rows.map((r) => VariantEntity(
        id: r.id,
        productId: r.productId,
        productCode: r.sku,
        color: r.color,
        size: r.size,
        quantity: r.quantity,
        costPrice: r.costPrice,
        salePrice: r.sellPrice,
        minStock: 5,
        createdAt: r.createdAt,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}






