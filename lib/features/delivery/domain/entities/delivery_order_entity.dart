import 'package:equatable/equatable.dart';

class DeliveryOrderEntity extends Equatable {
  final String id;
  final String branchId;
  final String? saleId;
  final String orderRef;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String? courierId;
  final String? courierName;
  final int deliveryFeePiasters;
  final int orderTotalPiasters;
  final String paymentMethod; // 'cod' (الدفع عند الاستلام), 'card', 'transfer', 'paid'
  final String paymentStatus; // 'pending', 'collected', 'paid_online'
  final String status; // 'preparing', 'out_for_delivery', 'delivered', 'returned', 'cancelled'
  final bool courierSettled; // تم توريد الكاش من الطيار للخزينة
  final String? notes;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime updatedAt;

  const DeliveryOrderEntity({
    required this.id,
    required this.branchId,
    this.saleId,
    required this.orderRef,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    this.courierId,
    this.courierName,
    this.deliveryFeePiasters = 0,
    required this.orderTotalPiasters,
    this.paymentMethod = 'cod',
    this.paymentStatus = 'pending',
    this.status = 'preparing',
    this.courierSettled = false,
    this.notes,
    required this.createdAt,
    this.deliveredAt,
    required this.updatedAt,
  });

  bool get isPreparing => status == 'preparing';
  bool get isOutForDelivery => status == 'out_for_delivery';
  bool get isDelivered => status == 'delivered';
  bool get isReturned => status == 'returned';
  bool get isCancelled => status == 'cancelled';

  int get grandTotalPiasters => orderTotalPiasters + deliveryFeePiasters;
  double get deliveryFee => deliveryFeePiasters / 100.0;
  double get orderTotal => orderTotalPiasters / 100.0;
  double get grandTotal => grandTotalPiasters / 100.0;

  DeliveryOrderEntity copyWith({
    String? id,
    String? branchId,
    String? saleId,
    String? orderRef,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
    String? courierId,
    String? courierName,
    int? deliveryFeePiasters,
    int? orderTotalPiasters,
    String? paymentMethod,
    String? paymentStatus,
    String? status,
    bool? courierSettled,
    String? notes,
    DateTime? createdAt,
    DateTime? deliveredAt,
    DateTime? updatedAt,
  }) {
    return DeliveryOrderEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      saleId: saleId ?? this.saleId,
      orderRef: orderRef ?? this.orderRef,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      courierId: courierId ?? this.courierId,
      courierName: courierName ?? this.courierName,
      deliveryFeePiasters: deliveryFeePiasters ?? this.deliveryFeePiasters,
      orderTotalPiasters: orderTotalPiasters ?? this.orderTotalPiasters,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      courierSettled: courierSettled ?? this.courierSettled,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        saleId,
        orderRef,
        customerId,
        customerName,
        customerPhone,
        deliveryAddress,
        courierId,
        courierName,
        deliveryFeePiasters,
        orderTotalPiasters,
        paymentMethod,
        paymentStatus,
        status,
        courierSettled,
        notes,
        createdAt,
        deliveredAt,
        updatedAt,
      ];
}
