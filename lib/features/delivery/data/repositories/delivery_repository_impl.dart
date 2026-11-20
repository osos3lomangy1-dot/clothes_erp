import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/courier_settlement_summary.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';
import '../../domain/repositories/delivery_repository.dart';
import '../datasources/delivery_local_data_source.dart';

@LazySingleton(as: DeliveryRepository)
class DeliveryRepositoryImpl implements DeliveryRepository {
  final DeliveryLocalDataSource _localDataSource;

  DeliveryRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, DeliveryOrderEntity>> createDeliveryOrder(
    DeliveryOrderEntity order,
  ) async {
    try {
      await _localDataSource.insertDeliveryOrder(order);
      return Right(order);
    } catch (e) {
      return Left(ServerFailure('تعذر إنشاء طلب التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateDeliveryStatus(
    String orderId,
    String newStatus, {
    DateTime? deliveredAt,
  }) async {
    try {
      await _localDataSource.updateDeliveryStatus(
        orderId,
        newStatus,
        deliveredAt: deliveredAt,
      );
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure('تعذر تحديث حالة التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> assignCourier(
    String orderId,
    String courierId,
    String courierName,
  ) async {
    try {
      await _localDataSource.assignCourier(orderId, courierId, courierName);
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure('تعذر تعيين مندوب التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, List<DeliveryOrderEntity>>> getDeliveryOrders({
    String? status,
    String? courierId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final orders = await _localDataSource.getDeliveryOrders(
        status: status,
        courierId: courierId,
        from: from,
        to: to,
      );
      return Right(orders);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل طلبات التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, List<DeliveryCourierEntity>>> getCouriers() async {
    try {
      final couriers = await _localDataSource.getCouriers();
      return Right(couriers);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل مناديب التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, DeliveryCourierEntity>> addCourier(
    DeliveryCourierEntity courier,
  ) async {
    try {
      await _localDataSource.insertCourier(courier);
      return Right(courier);
    } catch (e) {
      return Left(ServerFailure('تعذر إضافة مندوب التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateCourier(
    DeliveryCourierEntity courier,
  ) async {
    try {
      await _localDataSource.updateCourier(courier);
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure('تعذر تعديل مندوب التوصيل: $e'));
    }
  }

  @override
  Future<Either<Failure, CourierSettlementSummary>> getCourierSettlement(
    String courierId,
  ) async {
    try {
      final allCourierOrders = await _localDataSource.getDeliveryOrders(
        courierId: courierId,
      );
      final couriers = await _localDataSource.getCouriers();
      final courier = couriers.firstWhere(
        (c) => c.id == courierId,
        orElse: () => DeliveryCourierEntity(
          id: courierId,
          branchId: 'default',
          name: 'طيار غير معروف',
          phone: '',
          createdAt: DateTime.now(),
        ),
      );

      var deliveredCount = 0;
      var pendingCount = 0;
      var returnedCount = 0;
      var totalCashToCollect = 0;
      var totalFees = 0;
      final unsettledOrders = <DeliveryOrderEntity>[];

      for (final o in allCourierOrders) {
        if (o.status == 'delivered') {
          deliveredCount++;
          totalFees += o.deliveryFeePiasters;
          if (!o.courierSettled && o.paymentMethod == 'cod') {
            totalCashToCollect += o.grandTotalPiasters;
            unsettledOrders.add(o);
          }
        } else if (o.status == 'returned' || o.status == 'cancelled') {
          returnedCount++;
        } else {
          pendingCount++;
        }
      }

      final summary = CourierSettlementSummary(
        courierId: courier.id,
        courierName: courier.name,
        courierPhone: courier.phone,
        totalAssignedOrders: allCourierOrders.length,
        deliveredOrdersCount: deliveredCount,
        pendingOrdersCount: pendingCount,
        returnedOrdersCount: returnedCount,
        totalCashToCollectPiasters: totalCashToCollect,
        totalDeliveryFeesPiasters: totalFees,
        unsettledOrders: unsettledOrders,
      );

      return Right(summary);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل تصفية حساب الطيار: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> settleCourierOrders(
    String courierId,
    List<String> orderIds, {
    String? notes,
  }) async {
    try {
      await _localDataSource.settleCourierOrders(courierId, orderIds);
      return const Right(unit);
    } catch (e) {
      return Left(ServerFailure('تعذر تسوية عهدة الطيار: $e'));
    }
  }
}

