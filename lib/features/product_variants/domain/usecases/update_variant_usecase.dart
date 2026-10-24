import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/variant_entity.dart';
import '../repositories/variant_repository.dart';

@lazySingleton
class UpdateVariantUseCase {
  final VariantRepository repository;

  UpdateVariantUseCase(this.repository);

  Future<Either<Failure, void>> call(VariantEntity variant) {
    return repository.updateVariant(variant);
  }
}
