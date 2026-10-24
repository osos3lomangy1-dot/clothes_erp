import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../repositories/inventory_repository.dart';

@lazySingleton
class GetAllInventoryUseCase {
  final InventoryRepository repository;

  GetAllInventoryUseCase(this.repository);

  Future<Either<Failure, List<VariantEntity>>> call() {
    return repository.getAllInventory();
  }
}
