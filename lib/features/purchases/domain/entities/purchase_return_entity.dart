import 'package:equatable/equatable.dart';

class PurchaseReturnEntity extends Equatable {
  final String id;
  final String branchId;
  final String? purchaseId;
  final String? purchaseInvoiceNumber;
  final String supplierId;
  final String? supplierName;
  final int totalAmount; // in piasters
  final String refundType; // 'credit' (خصم من رصيد المورد) or 'cash' (استرداد نقدي بالخزينة)
  final String? reason;
  final String createdBy;
  final DateTime createdAt;
  final List<PurchaseReturnItemEntity> items;

  const PurchaseReturnEntity({
    required this.id,
    required this.branchId,
    this.purchaseId,
    this.purchaseInvoiceNumber,
    required this.supplierId,
    this.supplierName,
    required this.totalAmount,
    required this.refundType,
    this.reason,
    required this.createdBy,
    required this.createdAt,
    this.items = const [],
  });

  String get formattedTotalAmount => '${(totalAmount / 100).toStringAsFixed(2)} ج.م';
  bool get isCashRefund => refundType == 'cash';
  bool get isCreditRefund => refundType == 'credit';

  PurchaseReturnEntity copyWith({
    String? id,
    String? branchId,
    String? purchaseId,
    String? purchaseInvoiceNumber,
    String? supplierId,
    String? supplierName,
    int? totalAmount,
    String? refundType,
    String? reason,
    String? createdBy,
    DateTime? createdAt,
    List<PurchaseReturnItemEntity>? items,
  }) {
    return PurchaseReturnEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      purchaseId: purchaseId ?? this.purchaseId,
      purchaseInvoiceNumber: purchaseInvoiceNumber ?? this.purchaseInvoiceNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      totalAmount: totalAmount ?? this.totalAmount,
      refundType: refundType ?? this.refundType,
      reason: reason ?? this.reason,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        purchaseId,
        purchaseInvoiceNumber,
        supplierId,
        supplierName,
        totalAmount,
        refundType,
        reason,
        createdBy,
        createdAt,
        items,
      ];
}

class PurchaseReturnItemEntity extends Equatable {
  final String id;
  final String returnId;
  final String variantId;
  final String productName;
  final String variantInfo;
  final String sku;
  final int qty;
  final int costPrice; // in piasters
  final int totalCost; // in piasters (qty * costPrice)
  final DateTime createdAt;

  const PurchaseReturnItemEntity({
    required this.id,
    required this.returnId,
    required this.variantId,
    required this.productName,
    required this.variantInfo,
    required this.sku,
    required this.qty,
    required this.costPrice,
    required this.totalCost,
    required this.createdAt,
  });

  String get formattedCostPrice => '${(costPrice / 100).toStringAsFixed(2)} ج.م';
  String get formattedTotalCost => '${(totalCost / 100).toStringAsFixed(2)} ج.م';

  @override
  List<Object?> get props => [
        id,
        returnId,
        variantId,
        productName,
        variantInfo,
        sku,
        qty,
        costPrice,
        totalCost,
        createdAt,
      ];
}

