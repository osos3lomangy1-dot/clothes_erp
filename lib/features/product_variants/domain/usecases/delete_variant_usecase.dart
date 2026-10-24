import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/variant_repository.dart';

@lazySingleton
class DeleteVariantUseCase {
  final VariantRepository repository;

  DeleteVariantUseCase(this.repository);

  Future<Either<Failure, void>> call(String id) {
    return repository.deleteVariant(id);
  }
}
