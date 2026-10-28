import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/pos_repository.dart';
import '../datasources/pos_local_data_source.dart';

@LazySingleton(as: PosRepository)
class PosRepositoryImpl implements PosRepository {
  final PosLocalDataSource _localDataSource;

  PosRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, SaleEntity>> createSale(SaleEntity sale) async {
    try {
      final items = sale.items.map((i) => {
        'variantId': i.variantId,
        'name': i.productName,
        'color': i.color,
        'size': i.size,
        'qty': i.quantity,
        'price': i.price,
        'cost': 0,
      }).toList();
      await _localDataSource.checkout(items: items, total: sale.total.toInt(), cashierId: sale.cashierId);
      return Right(sale);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
