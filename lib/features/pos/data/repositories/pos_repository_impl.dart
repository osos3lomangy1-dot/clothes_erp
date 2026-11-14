import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/features/feature_gate.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/pos_repository.dart';
import '../datasources/pos_local_data_source.dart';

@LazySingleton(as: PosRepository)
class PosRepositoryImpl implements PosRepository {
  final PosLocalDataSource _localDataSource;
  final FeatureGate _featureGate;

  PosRepositoryImpl(this._localDataSource, this._featureGate);

  @override
  Future<Either<Failure, SaleEntity>> createSale(SaleEntity sale) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.pos)) {
        return const Left(CacheFailure('ميزة نقطة البيع غير مفعّلة'));
      }
      final items = sale.items.map((i) => {
        'variantId': i.variantId,
        'name': i.productName,
        'color': i.color,
        'size': i.size,
        'qty': i.quantity,
        'price': i.price,
        'cost': 0,
      }).toList();
      await _localDataSource.checkout(
        items: items,
        total: sale.total.toInt(),
        cashierId: sale.cashierId,
        customerId: sale.customerId,
      );
      return Right(sale);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> getActiveCashierId() async {
    try {
      final cashierId = await _localDataSource.getActiveCashierId();
      return Right(cashierId);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
