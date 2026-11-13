import 'package:equatable/equatable.dart';

class GoodsReceiptItemEntity extends Equatable {
  final String id;
  final String receiptId;
  final String variantId;
  final String? productName;
  final String? sku;
  final String? color;
  final String? size;
  final int quantity;
  final DateTime createdAt;

  const GoodsReceiptItemEntity({
    required this.id,
    required this.receiptId,
    required this.variantId,
    this.productName,
    this.sku,
    this.color,
    this.size,
    required this.quantity,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        receiptId,
        variantId,
        productName,
        sku,
        color,
        size,
        quantity,
        createdAt,
      ];
}

class GoodsReceiptEntity extends Equatable {
  final String id;
  final String branchId;
  final String cashierId;
  final DateTime receivedAt;
  final String status; // pending, invoiced, cancelled
  final int totalItems;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GoodsReceiptItemEntity> items;

  const GoodsReceiptEntity({
    required this.id,
    required this.branchId,
    required this.cashierId,
    required this.receivedAt,
    required this.status,
    required this.totalItems,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  bool get isPending => status == 'pending';
  bool get isInvoiced => status == 'invoiced';

  @override
  List<Object?> get props => [
        id,
        branchId,
        cashierId,
        receivedAt,
        status,
        totalItems,
        notes,
        createdAt,
        updatedAt,
        items,
      ];
}

