import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_local_data_source.dart';

@LazySingleton(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  final ProductLocalDataSource _localDataSource;

  ProductRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async {
    try {
      final rows = await _localDataSource.getProducts();
      final entities = rows.map((r) => ProductEntity(
        id: r.id,
        name: r.name,
        description: r.description ?? '',
        categoryId: r.categoryId,
        categoryName: '',
        createdAt: r.createdAt,
        minStock: r.minStock,
        isActive: r.isActive,
      )).toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addProduct(ProductEntity product) async {
    try {
      await _localDataSource.createProduct(
        name: product.name,
        categoryId: product.categoryId,
        description: product.description,
        minStock: product.minStock,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> addProductWithVariants(ProductEntity product, List<VariantInput> variants) async {
    try {
      final id = await _localDataSource.createProductWithVariants(
        name: product.name,
        categoryId: product.categoryId,
        description: product.description,
        minStock: product.minStock,
        variants: variants,
      );
      return Right(id);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateProduct(ProductEntity product) async {
    try {
      await _localDataSource.updateProduct(product.id,
        name: product.name,
        description: product.description,
        minStock: product.minStock,
        isActive: product.isActive,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteProduct(String id) async {
    try {
      await _localDataSource.softDeleteProduct(id);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
