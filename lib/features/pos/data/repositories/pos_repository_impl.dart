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
        'discount': i.discount,
        'promotionDiscount': i.promotionDiscount,
      }).toList();
      final createdId = await _localDataSource.checkout(
        items: items,
        total: sale.total,
        cashierId: sale.cashierId,
        customerId: sale.customerId,
        paymentMethod: sale.paymentMethod,
        splits: sale.splits,
        saleId: sale.id.isNotEmpty ? sale.id : null,
        promotionResult: sale.promotionResult,
      );
      return Right(SaleEntity(
        id: createdId,
        date: sale.date,
        cashierId: sale.cashierId,
        cashierName: sale.cashierName,
        items: sale.items,
        subtotal: sale.subtotal,
        discount: sale.discount,
        total: sale.total,
        paymentMethod: sale.paymentMethod,
        customerId: sale.customerId,
        syncStatus: sale.syncStatus,
        splits: sale.splits,
        promotionResult: sale.promotionResult,
        promotionDiscount: sale.promotionDiscount,
      ));
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
