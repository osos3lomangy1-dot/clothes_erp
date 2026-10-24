import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/variant_entity.dart';
import '../repositories/variant_repository.dart';

@lazySingleton
class AddVariantUseCase {
  final VariantRepository repository;

  AddVariantUseCase(this.repository);

  Future<Either<Failure, void>> call(VariantEntity variant) {
    return repository.addVariant(variant);
  }
}
