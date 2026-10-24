import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

abstract class InventoryRepository {
  Future<Either<Failure, List<VariantEntity>>> getAllInventory();
  Future<Either<Failure, List<VariantEntity>>> getLowStockInventory();
}
