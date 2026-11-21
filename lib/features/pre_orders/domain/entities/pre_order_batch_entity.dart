import 'pre_order_entity.dart';

class ShippingSplitMethods {
  static const String perItem = 'perItem'; // حسب عدد القطع
  static const String equalPerCustomer = 'equalPerCustomer'; // بالتساوي بين العملاء
  static const String customFixed = 'customFixed'; // تحديد يدوي مخصص
  static const String freeShipping = 'freeShipping'; // شحن مجاني يتحمله التاجر

  static String getLabel(String method) {
    switch (method) {
      case perItem:
        return 'حسب عدد القطع (موصى به)';
      case equalPerCustomer:
        return 'بالتساوي بين العملاء';
      case customFixed:
        return 'تحديد يدوي لكل عميل';
      case freeShipping:
        return 'شحن مجاني للعملاء';
      default:
        return method;
    }
  }
}

class PreOrderBatchEntity {
  final String id;
  final String branchId;
  final String batchNumber; // مثل: شحنة 20 نوفمبر
  final String? agentName;
  final String? trackingNumber;
  final int totalShippingPiasters; // إجمالي مصاريف الشحن العام بالقرش
  final String shippingSplitMethod;
  final String status; // pendingProcessing, arrivedAtStore, completed
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? arrivedAt;
  final List<PreOrderEntity> orders;

  const PreOrderBatchEntity({
    required this.id,
    required this.branchId,
    required this.batchNumber,
    this.agentName,
    this.trackingNumber,
    this.totalShippingPiasters = 0,
    this.shippingSplitMethod = ShippingSplitMethods.perItem,
    this.status = PreOrderStatuses.pendingProcessing,
    required this.createdAt,
    required this.updatedAt,
    this.arrivedAt,
    this.orders = const [],
  });

  int get totalOrdersCount => orders.length;

  int get totalPiecesCount => orders.fold(
        0,
        (sum, o) => sum + o.items.fold(0, (s, it) => s + it.quantity),
      );

  int get totalRetailPiasters =>
      orders.fold(0, (sum, o) => sum + o.totalPiasters);

  int get totalCostPiasters =>
      orders.fold(0, (sum, o) => sum + o.totalCostPiasters);

  int get totalDepositsPiasters =>
      orders.fold(0, (sum, o) => sum + o.depositPiasters);

  /// صافي ربح التاجر من الشحنة (مع خصم الشحن العام في حال الشحن المجاني)
  int get totalProfitPiasters {
    final baseProfit = totalRetailPiasters - totalCostPiasters;
    if (shippingSplitMethod == ShippingSplitMethods.freeShipping) {
      return (baseProfit - totalShippingPiasters).clamp(0, totalRetailPiasters);
    }
    return baseProfit.clamp(0, totalRetailPiasters);
  }

  int get totalAllocatedShippingPiasters =>
      orders.fold(0, (sum, o) => sum + o.allocatedShippingPiasters);

  int get totalRemainingWithShippingPiasters =>
      orders.fold(0, (sum, o) => sum + o.remainingWithShippingPiasters);

  PreOrderBatchEntity copyWith({
    String? id,
    String? branchId,
    String? batchNumber,
    String? agentName,
    String? trackingNumber,
    int? totalShippingPiasters,
    String? shippingSplitMethod,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? arrivedAt,
    List<PreOrderEntity>? orders,
  }) {
    return PreOrderBatchEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      batchNumber: batchNumber ?? this.batchNumber,
      agentName: agentName ?? this.agentName,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      totalShippingPiasters:
          totalShippingPiasters ?? this.totalShippingPiasters,
      shippingSplitMethod: shippingSplitMethod ?? this.shippingSplitMethod,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      orders: orders ?? this.orders,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'branch_id': branchId,
      'batch_number': batchNumber,
      'agent_name': agentName,
      'tracking_number': trackingNumber,
      'total_shipping_piasters': totalShippingPiasters,
      'shipping_split_method': shippingSplitMethod,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'arrived_at': arrivedAt != null
          ? arrivedAt!.millisecondsSinceEpoch ~/ 1000
          : null,
      'deleted_at': null,
    };
  }

  factory PreOrderBatchEntity.fromMap(
    Map<String, dynamic> map, {
    List<PreOrderEntity> orders = const [],
  }) {
    return PreOrderBatchEntity(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      batchNumber: map['batch_number'] as String,
      agentName: map['agent_name'] as String?,
      trackingNumber: map['tracking_number'] as String?,
      totalShippingPiasters:
          (map['total_shipping_piasters'] as num?)?.toInt() ?? 0,
      shippingSplitMethod: map['shipping_split_method'] as String? ??
          ShippingSplitMethods.perItem,
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
      orders: orders,
    );
  }
}
