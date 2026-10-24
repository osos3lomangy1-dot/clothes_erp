import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/product_entity.dart';
import '../repositories/product_repository.dart';

@lazySingleton
class AddProductUseCase {
  final ProductRepository repository;

  AddProductUseCase(this.repository);

  Future<Either<Failure, void>> call(ProductEntity product) {
    return repository.addProduct(product);
  }
}
