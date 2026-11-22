import 'package:equatable/equatable.dart';
import '../../domain/entities/courier_settlement_summary.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';
import '../../domain/entities/shipping_company_payout_entity.dart';
import '../../domain/entities/shipping_company_statement.dart';

enum DeliveryStatus { initial, loading, success, error }

class DeliveryState extends Equatable {
  final DeliveryStatus status;
  final List<DeliveryOrderEntity> orders;
  final List<DeliveryCourierEntity> couriers;
  final String statusFilter; // 'all', 'preparing', 'out_for_delivery', 'delivered', 'returned'
  final String providerTypeFilter; // 'all', 'in_house', 'shipping_company'
  final String? selectedCourierId;
  final CourierSettlementSummary? settlementSummary;
  final ShippingCompanyStatement? shippingStatement;
  final List<ShippingCompanyPayoutEntity> shippingPayouts;
  final String searchQuery;
  final String? errorMessage;

  const DeliveryState({
    this.status = DeliveryStatus.initial,
    this.orders = const [],
    this.couriers = const [],
    this.statusFilter = 'all',
    this.providerTypeFilter = 'all',
    this.selectedCourierId,
    this.settlementSummary,
    this.shippingStatement,
    this.shippingPayouts = const [],
    this.searchQuery = '',
    this.errorMessage,
  });

  DeliveryState copyWith({
    DeliveryStatus? status,
    List<DeliveryOrderEntity>? orders,
    List<DeliveryCourierEntity>? couriers,
    String? statusFilter,
    String? providerTypeFilter,
    String? selectedCourierId,
    CourierSettlementSummary? settlementSummary,
    ShippingCompanyStatement? shippingStatement,
    List<ShippingCompanyPayoutEntity>? shippingPayouts,
    String? searchQuery,
    String? errorMessage,
  }) {
    return DeliveryState(
      status: status ?? this.status,
      orders: orders ?? this.orders,
      couriers: couriers ?? this.couriers,
      statusFilter: statusFilter ?? this.statusFilter,
      providerTypeFilter: providerTypeFilter ?? this.providerTypeFilter,
      selectedCourierId: selectedCourierId ?? this.selectedCourierId,
      settlementSummary: settlementSummary ?? this.settlementSummary,
      shippingStatement: shippingStatement ?? this.shippingStatement,
      shippingPayouts: shippingPayouts ?? this.shippingPayouts,
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

  List<DeliveryCourierEntity> get inHouseCouriers =>
      couriers.where((c) => c.isInHouse).toList();

  List<DeliveryCourierEntity> get shippingCompanies =>
      couriers.where((c) => c.isShippingCompany).toList();

  @override
  List<Object?> get props => [
        status,
        orders,
        couriers,
        statusFilter,
        providerTypeFilter,
        selectedCourierId,
        settlementSummary,
        shippingStatement,
        shippingPayouts,
        searchQuery,
        errorMessage,
      ];
}
