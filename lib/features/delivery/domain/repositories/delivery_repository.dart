import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/courier_settlement_summary.dart';
import '../entities/delivery_courier_entity.dart';
import '../entities/delivery_order_entity.dart';

abstract class DeliveryRepository {
  Future<Either<Failure, DeliveryOrderEntity>> createDeliveryOrder(
    DeliveryOrderEntity order,
  );

  Future<Either<Failure, Unit>> updateDeliveryStatus(
    String orderId,
    String newStatus, {
    DateTime? deliveredAt,
  });

  Future<Either<Failure, Unit>> assignCourier(
    String orderId,
    String courierId,
    String courierName,
  );

  Future<Either<Failure, List<DeliveryOrderEntity>>> getDeliveryOrders({
    String? status,
    String? courierId,
    DateTime? from,
    DateTime? to,
  });

  Future<Either<Failure, List<DeliveryCourierEntity>>> getCouriers();

  Future<Either<Failure, DeliveryCourierEntity>> addCourier(
    DeliveryCourierEntity courier,
  );

  Future<Either<Failure, Unit>> updateCourier(
    DeliveryCourierEntity courier,
  );

  Future<Either<Failure, CourierSettlementSummary>> getCourierSettlement(
    String courierId,
  );

  Future<Either<Failure, Unit>> settleCourierOrders(
    String courierId,
    List<String> orderIds, {
    String? notes,
  });
}

