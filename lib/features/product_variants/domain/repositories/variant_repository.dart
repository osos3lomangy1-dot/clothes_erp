import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/variant_entity.dart';

abstract class VariantRepository {
  Future<Either<Failure, List<VariantEntity>>> getVariants(String productId);
  Future<Either<Failure, void>> addVariant(VariantEntity variant);
  Future<Either<Failure, void>> updateVariant(VariantEntity variant);
  Future<Either<Failure, void>> deleteVariant(String id);
  Future<Either<Failure, List<VariantEntity>>> searchVariants(String query);
  Future<Either<Failure, List<VariantEntity>>> getAllVariants();
}


