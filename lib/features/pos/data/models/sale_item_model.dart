import '../../domain/entities/sale_item_entity.dart';

class SaleItemModel extends SaleItemEntity {
  const SaleItemModel({
    required super.variantId,
    required super.productCode,
    required super.price,
    required super.quantity,
  });

  SaleItemModel copyWith({
    String? variantId,
    String? productCode,
    double? price,
    int? quantity,
  }) {
    return SaleItemModel(
      variantId: variantId ?? this.variantId,
      productCode: productCode ?? this.productCode,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
    );
  }

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      variantId: json['variantId'] ?? '',
      productCode: json['productCode'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'variantId': variantId,
      'productCode': productCode,
      'price': price,
      'quantity': quantity,
    };
  }

  factory SaleItemModel.fromEntity(SaleItemEntity entity) {
    return SaleItemModel(
      variantId: entity.variantId,
      productCode: entity.productCode,
      price: entity.price,
      quantity: entity.quantity,
    );
  }
}
