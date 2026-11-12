import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../entities/product_entity.dart';

abstract class ProductRepository {
  Future<Either<Failure, List<ProductEntity>>> getProducts();
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts();
  Future<Either<Failure, void>> addProduct(ProductEntity product);
  Future<Either<Failure, String>> addProductWithVariants(ProductEntity product, List<VariantInput> variants);
  Future<Either<Failure, void>> updateProduct(ProductEntity product);
  Future<Either<Failure, void>> deleteProduct(String id);
}
