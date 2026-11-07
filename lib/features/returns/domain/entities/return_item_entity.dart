import 'package:equatable/equatable.dart';

class ReturnItemEntity extends Equatable {
  final String id;
  final String? saleItemId;
  final String variantId;
  final String productName;
  final String color;
  final String size;
  final int maxQty; // original sale quantity
  final int qty; // quantity to return
  final int refundUnitPrice; // in piasters

  const ReturnItemEntity({
    this.id = '',
    this.saleItemId,
    required this.variantId,
    this.productName = '',
    this.color = '',
    this.size = '',
    this.maxQty = 1,
    required this.qty,
    required this.refundUnitPrice,
  });

  int get lineTotal => qty * refundUnitPrice;

  ReturnItemEntity copyWith({
    String? id,
    String? saleItemId,
    String? variantId,
    String? productName,
    String? color,
    String? size,
    int? maxQty,
    int? qty,
    int? refundUnitPrice,
  }) {
    return ReturnItemEntity(
      id: id ?? this.id,
      saleItemId: saleItemId ?? this.saleItemId,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      color: color ?? this.color,
      size: size ?? this.size,
      maxQty: maxQty ?? this.maxQty,
      qty: qty ?? this.qty,
      refundUnitPrice: refundUnitPrice ?? this.refundUnitPrice,
    );
  }

  @override
  List<Object?> get props => [
        id,
        saleItemId,
        variantId,
        productName,
        color,
        size,
        maxQty,
        qty,
        refundUnitPrice,
      ];
}

