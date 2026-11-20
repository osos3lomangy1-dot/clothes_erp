import 'package:equatable/equatable.dart';
import 'delivery_order_entity.dart';

class CourierSettlementSummary extends Equatable {
  final String courierId;
  final String courierName;
  final String courierPhone;
  final int totalAssignedOrders;
  final int deliveredOrdersCount;
  final int pendingOrdersCount;
  final int returnedOrdersCount;
  final int totalCashToCollectPiasters;
  final int totalDeliveryFeesPiasters;
  final List<DeliveryOrderEntity> unsettledOrders;

  const CourierSettlementSummary({
    required this.courierId,
    required this.courierName,
    required this.courierPhone,
    required this.totalAssignedOrders,
    required this.deliveredOrdersCount,
    required this.pendingOrdersCount,
    required this.returnedOrdersCount,
    required this.totalCashToCollectPiasters,
    required this.totalDeliveryFeesPiasters,
    required this.unsettledOrders,
  });

  double get totalCashToCollect => totalCashToCollectPiasters / 100.0;
  double get totalDeliveryFees => totalDeliveryFeesPiasters / 100.0;
  double get netCashHandoverRequired =>
      (totalCashToCollectPiasters - totalDeliveryFeesPiasters) / 100.0;

  @override
  List<Object?> get props => [
        courierId,
        courierName,
        courierPhone,
        totalAssignedOrders,
        deliveredOrdersCount,
        pendingOrdersCount,
        returnedOrdersCount,
        totalCashToCollectPiasters,
        totalDeliveryFeesPiasters,
        unsettledOrders,
      ];
}
