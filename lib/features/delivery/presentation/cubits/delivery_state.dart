import 'package:equatable/equatable.dart';
import '../../domain/entities/courier_settlement_summary.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';

enum DeliveryStatus { initial, loading, success, error }

class DeliveryState extends Equatable {
  final DeliveryStatus status;
  final List<DeliveryOrderEntity> orders;
  final List<DeliveryCourierEntity> couriers;
  final String statusFilter; // 'all', 'preparing', 'out_for_delivery', 'delivered', 'returned'
  final String? selectedCourierId;
  final CourierSettlementSummary? settlementSummary;
  final String searchQuery;
  final String? errorMessage;

  const DeliveryState({
    this.status = DeliveryStatus.initial,
    this.orders = const [],
    this.couriers = const [],
    this.statusFilter = 'all',
    this.selectedCourierId,
    this.settlementSummary,
    this.searchQuery = '',
    this.errorMessage,
  });

  DeliveryState copyWith({
    DeliveryStatus? status,
    List<DeliveryOrderEntity>? orders,
    List<DeliveryCourierEntity>? couriers,
    String? statusFilter,
    String? selectedCourierId,
    CourierSettlementSummary? settlementSummary,
    String? searchQuery,
    String? errorMessage,
  }) {
    return DeliveryState(
      status: status ?? this.status,
      orders: orders ?? this.orders,
      couriers: couriers ?? this.couriers,
      statusFilter: statusFilter ?? this.statusFilter,
      selectedCourierId: selectedCourierId ?? this.selectedCourierId,
      settlementSummary: settlementSummary ?? this.settlementSummary,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
    );
  }

  int get preparingCount => orders.where((o) => o.status == 'preparing').length;
  int get outForDeliveryCount =>
      orders.where((o) => o.status == 'out_for_delivery').length;
  int get deliveredCount => orders.where((o) => o.status == 'delivered').length;
  int get returnedCount =>
      orders.where((o) => o.status == 'returned' || o.status == 'cancelled').length;

  int get activeCashInTransitPiasters => orders
      .where((o) => o.status == 'out_for_delivery' && o.paymentMethod == 'cod')
      .fold(0, (sum, o) => sum + o.grandTotalPiasters);

  int get deliveredUnsettledCashPiasters => orders
      .where((o) =>
          o.status == 'delivered' &&
          o.paymentMethod == 'cod' &&
          !o.courierSettled)
      .fold(0, (sum, o) => sum + o.grandTotalPiasters);

  double get activeCashInTransit => activeCashInTransitPiasters / 100.0;
  double get deliveredUnsettledCash => deliveredUnsettledCashPiasters / 100.0;

  @override
  List<Object?> get props => [
        status,
        orders,
        couriers,
        statusFilter,
        selectedCourierId,
        settlementSummary,
        searchQuery,
        errorMessage,
      ];
}
