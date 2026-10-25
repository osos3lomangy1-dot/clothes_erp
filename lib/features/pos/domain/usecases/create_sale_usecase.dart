import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/sale_entity.dart';
import '../repositories/pos_repository.dart';

@lazySingleton
class CreateSaleUseCase {
  final PosRepository repository;

  CreateSaleUseCase(this.repository);

  Future<Either<Failure, SaleEntity>> call(SaleEntity sale) {
    return repository.createSale(sale);
  }
}
