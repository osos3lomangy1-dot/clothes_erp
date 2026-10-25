import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/sale_entity.dart';

abstract class PosRepository {
  Future<Either<Failure, SaleEntity>> createSale(SaleEntity sale);
}
