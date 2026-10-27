import '../../domain/entities/sale_item_entity.dart';

class SaleItemModel extends SaleItemEntity {
  const SaleItemModel({
    required super.variantId,
    required super.productName,
    required super.size,
    required super.color,
    required super.price,
    required super.quantity,
  });

  @override
  SaleItemModel copyWith({
    String? variantId,
    String? productName,
    String? size,
    String? color,
    double? price,
    int? quantity,
  }) {
    return SaleItemModel(
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
    );
  }

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      variantId: json['variantId'] ?? '',
      productName: json['productName'] ?? '',
      size: json['size'] ?? '',
      color: json['color'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'variantId': variantId,
      'productName': productName,
      'size': size,
      'color': color,
      'price': price,
      'quantity': quantity,
    };
  }

  factory SaleItemModel.fromEntity(SaleItemEntity entity) {
    return SaleItemModel(
      variantId: entity.variantId,
      productName: entity.productName,
      size: entity.size,
      color: entity.color,
      price: entity.price,
      quantity: entity.quantity,
    );
  }
}
