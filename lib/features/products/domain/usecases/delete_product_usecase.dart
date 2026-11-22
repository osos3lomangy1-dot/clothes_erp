import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/product_repository.dart';

@lazySingleton
class DeleteProductUseCase {
  final ProductRepository repository;

  DeleteProductUseCase(this.repository);

  Future<Either<Failure, void>> call(
    String id, {
    bool forceDeleteForAdmin = false,
    String? userId,
  }) {
    return repository.deleteProduct(
      id,
      forceDeleteForAdmin: forceDeleteForAdmin,
      userId: userId,
    );
  }
}
