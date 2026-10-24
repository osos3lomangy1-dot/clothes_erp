import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/variant_entity.dart';
import '../repositories/variant_repository.dart';

@lazySingleton
class GetVariantsUseCase {
  final VariantRepository repository;

  GetVariantsUseCase(this.repository);

  Future<Either<Failure, List<VariantEntity>>> call(String productId) {
    return repository.getVariants(productId);
  }
}
