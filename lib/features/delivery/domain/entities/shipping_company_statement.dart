import 'package:equatable/equatable.dart';
import 'delivery_order_entity.dart';
import 'shipping_company_payout_entity.dart';

class ShippingCompanyStatement extends Equatable {
  final String courierId;
  final String courierName;
  final String? accountNumber;
  final int totalAssignedOrders;
  final int deliveredOrdersCount;
  final int pendingOrdersCount;
  final int returnedOrdersCount;
  final int totalCodDeliveredPiasters;
  final int totalShippingFeesPiasters;
  final int totalNetDueToStorePiasters;
  final int totalPayoutsReceivedPiasters;
  final int remainingBalancePiasters;
  final List<DeliveryOrderEntity> orders;
  final List<ShippingCompanyPayoutEntity> payouts;

  const ShippingCompanyStatement({
    required this.courierId,
    required this.courierName,
    this.accountNumber,
    required this.totalAssignedOrders,
    required this.deliveredOrdersCount,
    required this.pendingOrdersCount,
    required this.returnedOrdersCount,
    required this.totalCodDeliveredPiasters,
    required this.totalShippingFeesPiasters,
    required this.totalNetDueToStorePiasters,
    required this.totalPayoutsReceivedPiasters,
    required this.remainingBalancePiasters,
    this.orders = const [],
    this.payouts = const [],
  });

  double get totalCodDelivered => totalCodDeliveredPiasters / 100.0;
  double get totalShippingFees => totalShippingFeesPiasters / 100.0;
  double get totalNetDueToStore => totalNetDueToStorePiasters / 100.0;
  double get totalPayoutsReceived => totalPayoutsReceivedPiasters / 100.0;
  double get remainingBalance => remainingBalancePiasters / 100.0;

  @override
  List<Object?> get props => [
        courierId,
        courierName,
        accountNumber,
        totalAssignedOrders,
        deliveredOrdersCount,
        pendingOrdersCount,
        returnedOrdersCount,
        totalCodDeliveredPiasters,
        totalShippingFeesPiasters,
        totalNetDueToStorePiasters,
        totalPayoutsReceivedPiasters,
        remainingBalancePiasters,
        orders,
        payouts,
      ];
}
