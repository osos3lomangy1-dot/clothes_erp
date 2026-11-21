import 'pre_order_item_entity.dart';
import 'pre_order_payment_entity.dart';

class PreOrderStatuses {
  static const String pendingProcessing = 'pendingProcessing';
  static const String arrivedAtStore = 'arrivedAtStore';
  static const String delivered = 'delivered';
  static const String defaultedForfeited = 'defaultedForfeited';
  static const String refundedCancelled = 'refundedCancelled';

  static String getLabel(String status) {
    switch (status) {
      case pendingProcessing:
        return 'قيد التجهيز والشحن';
      case arrivedAtStore:
        return 'وصل للمحل جاهز للتسليم';
      case delivered:
        return 'تم التسليم ومكتمل';
      case defaultedForfeited:
        return 'رفض استلام ومصادرة';
      case refundedCancelled:
        return 'ملغي ومسترد';
      default:
        return status;
    }
  }
}

class PreOrderEntity {
  final String id;
  final String branchId;
  final String orderNumber;
  final String? batchId; // ربط بالشحنة المجمعة إن وُجدت
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final String? agentName; // اسم المندوب أو وسيط الشحن
  final String? trackingNumber; // رقم بوليصة الشحن / كود التتبع
  final String? notes;
  final DateTime? expectedDeliveryDate;
  final int totalPiasters;
  final int allocatedShippingPiasters; // نصيب العميل المحسوب من الشحن العام
  final int depositPiasters;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? arrivedAt;
  final DateTime? deliveredAt;
  final String? saleId;
  final DateTime? forfeitedAt;
  final int? forfeitedRevenuePiasters;
  final DateTime? refundedAt;
  final int? refundedPiasters;
  final List<PreOrderItemEntity> items;
  final List<PreOrderPaymentEntity> payments;

  const PreOrderEntity({
    required this.id,
    required this.branchId,
    required this.orderNumber,
    this.batchId,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.agentName,
    this.trackingNumber,
    this.notes,
    this.expectedDeliveryDate,
    required this.totalPiasters,
    this.allocatedShippingPiasters = 0,
    this.depositPiasters = 0,
    this.status = PreOrderStatuses.pendingProcessing,
    required this.createdAt,
    required this.updatedAt,
    this.arrivedAt,
    this.deliveredAt,
    this.saleId,
    this.forfeitedAt,
    this.forfeitedRevenuePiasters,
    this.refundedAt,
    this.refundedPiasters,
    this.items = const [],
    this.payments = const [],
  });

  /// إجمالي المبلغ المطلوب من العميل شامل نصيبه من الشحن
  int get totalWithShippingPiasters => totalPiasters + allocatedShippingPiasters;

  /// المبلغ المتبقي على العميل عند الاستلام شامل الشحن
  int get remainingWithShippingPiasters =>
      (totalWithShippingPiasters - depositPiasters)
          .clamp(0, totalWithShippingPiasters);

  int get remainingPiasters =>
      (totalPiasters - depositPiasters).clamp(0, totalPiasters);

  bool get isFullyPaid => depositPiasters >= totalWithShippingPiasters;

  /// إجمالي تكلفة المندوب للأوردر بالكامل
  int get totalCostPiasters =>
      items.fold(0, (sum, it) => sum + it.totalCostPiasters);

  /// إجمالي عمولة التاجر (صافي الربح المتوقع للأوردر)
  int get totalProfitPiasters =>
      (totalPiasters - totalCostPiasters).clamp(0, totalPiasters);

  bool get canAddPayment =>
      status == PreOrderStatuses.pendingProcessing ||
      status == PreOrderStatuses.arrivedAtStore;

  bool get canDeliver =>
      status == PreOrderStatuses.pendingProcessing ||
      status == PreOrderStatuses.arrivedAtStore;

  bool get canForfeit =>
      status == PreOrderStatuses.pendingProcessing ||
      status == PreOrderStatuses.arrivedAtStore;

  bool get canCancel =>
      status == PreOrderStatuses.pendingProcessing ||
      status == PreOrderStatuses.arrivedAtStore;

  PreOrderEntity copyWith({
    String? id,
    String? branchId,
    String? orderNumber,
    String? batchId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? agentName,
    String? trackingNumber,
    String? notes,
    DateTime? expectedDeliveryDate,
    int? totalPiasters,
    int? allocatedShippingPiasters,
    int? depositPiasters,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? arrivedAt,
    DateTime? deliveredAt,
    String? saleId,
    DateTime? forfeitedAt,
    int? forfeitedRevenuePiasters,
    DateTime? refundedAt,
    int? refundedPiasters,
    List<PreOrderItemEntity>? items,
    List<PreOrderPaymentEntity>? payments,
  }) {
    return PreOrderEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      orderNumber: orderNumber ?? this.orderNumber,
      batchId: batchId ?? this.batchId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      agentName: agentName ?? this.agentName,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      notes: notes ?? this.notes,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      totalPiasters: totalPiasters ?? this.totalPiasters,
      allocatedShippingPiasters:
          allocatedShippingPiasters ?? this.allocatedShippingPiasters,
      depositPiasters: depositPiasters ?? this.depositPiasters,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      saleId: saleId ?? this.saleId,
      forfeitedAt: forfeitedAt ?? this.forfeitedAt,
      forfeitedRevenuePiasters:
          forfeitedRevenuePiasters ?? this.forfeitedRevenuePiasters,
      refundedAt: refundedAt ?? this.refundedAt,
      refundedPiasters: refundedPiasters ?? this.refundedPiasters,
      items: items ?? this.items,
      payments: payments ?? this.payments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'branch_id': branchId,
      'order_number': orderNumber,
      'batch_id': batchId,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'agent_name': agentName,
      'tracking_number': trackingNumber,
      'notes': notes,
      'expected_delivery_date': expectedDeliveryDate != null
          ? expectedDeliveryDate!.millisecondsSinceEpoch ~/ 1000
          : null,
      'total_piasters': totalPiasters,
      'allocated_shipping_piasters': allocatedShippingPiasters,
      'deposit_piasters': depositPiasters,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'arrived_at': arrivedAt != null
          ? arrivedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
      'delivered_at': deliveredAt != null
          ? deliveredAt!.millisecondsSinceEpoch ~/ 1000
          : null,
      'sale_id': saleId,
      'forfeited_at': forfeitedAt != null
          ? forfeitedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
      'forfeited_revenue_piasters': forfeitedRevenuePiasters,
      'refunded_at': refundedAt != null
          ? refundedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
      'refunded_piasters': refundedPiasters,
      'deleted_at': null,
    };
  }

  factory PreOrderEntity.fromMap(
    Map<String, dynamic> map, {
    List<PreOrderItemEntity> items = const [],
    List<PreOrderPaymentEntity> payments = const [],
  }) {
    return PreOrderEntity(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      orderNumber: map['order_number'] as String,
      batchId: map['batch_id'] as String?,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String,
      customerPhone: map['customer_phone'] as String,
      agentName: map['agent_name'] as String?,
      trackingNumber: map['tracking_number'] as String?,
      notes: map['notes'] as String?,
      expectedDeliveryDate: map['expected_delivery_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((map['expected_delivery_date'] as num).toInt()) * 1000,
            )
          : null,
      totalPiasters: (map['total_piasters'] as num?)?.toInt() ?? 0,
      allocatedShippingPiasters:
          (map['allocated_shipping_piasters'] as num?)?.toInt() ?? 0,
      depositPiasters: (map['deposit_piasters'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? PreOrderStatuses.pendingProcessing,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['created_at'] as num?)?.toInt() ?? 0) * 1000,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['updated_at'] as num?)?.toInt() ?? 0) * 1000,
      ),
      arrivedAt: map['arrived_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((map['arrived_at'] as num).toInt()) * 1000,
            )
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((map['delivered_at'] as num).toInt()) * 1000,
            )
          : null,
      saleId: map['sale_id'] as String?,
      forfeitedAt: map['forfeited_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((map['forfeited_at'] as num).toInt()) * 1000,
            )
          : null,
      forfeitedRevenuePiasters:
          (map['forfeited_revenue_piasters'] as num?)?.toInt(),
      refundedAt: map['refunded_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              ((map['refunded_at'] as num).toInt()) * 1000,
            )
          : null,
      refundedPiasters: (map['refunded_piasters'] as num?)?.toInt(),
      items: items,
      payments: payments,
    );
  }
}
