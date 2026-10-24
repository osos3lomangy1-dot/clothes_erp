import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/variant_entity.dart';
import '../../domain/repositories/variant_repository.dart';
import '../datasources/variant_remote_data_source.dart';
import '../models/variant_model.dart';

@LazySingleton(as: VariantRepository)
class VariantRepositoryImpl implements VariantRepository {
  final VariantRemoteDataSource _remoteDataSource;

  VariantRepositoryImpl(this._remoteDataSource);

  @override
  Future<Either<Failure, List<VariantEntity>>> getVariants(String productId) async {
    try {
      final result = await _remoteDataSource.getVariants(productId);
      return Right(result);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addVariant(VariantEntity variant) async {
    try {
      final model = VariantModel(
        id: variant.id,
        productId: variant.productId,
        productCode: variant.productCode,
        color: variant.color,
        size: variant.size,
        quantity: variant.quantity,
        costPrice: variant.costPrice,
        salePrice: variant.salePrice,
        minStock: variant.minStock,
        createdAt: variant.createdAt,
      );
      await _remoteDataSource.addVariant(model);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateVariant(VariantEntity variant) async {
    try {
      final model = VariantModel(
        id: variant.id,
        productId: variant.productId,
        productCode: variant.productCode,
        color: variant.color,
        size: variant.size,
        quantity: variant.quantity,
        costPrice: variant.costPrice,
        salePrice: variant.salePrice,
        minStock: variant.minStock,
        createdAt: variant.createdAt,
      );
      await _remoteDataSource.updateVariant(model);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteVariant(String id) async {
    try {
      await _remoteDataSource.deleteVariant(id);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<VariantEntity>>> searchVariants(String query) {
    // TODO: implement searchVariants
    throw UnimplementedError();
  }
}
