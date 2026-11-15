import '../../domain/entities/sale_item_entity.dart';

class SaleItemModel extends SaleItemEntity {
  const SaleItemModel({
    required super.variantId,
    super.productId,
    super.categoryId,
    required super.productName,
    required super.size,
    required super.color,
    required super.price,
    required super.quantity,
    super.discount,
    super.promotionDiscount,
    super.isReturn,
  });

  @override
  SaleItemModel copyWith({
    String? variantId,
    String? productId,
    String? categoryId,
    String? productName,
    String? size,
    String? color,
    int? price,
    int? quantity,
    int? discount,
    int? promotionDiscount,
    bool? isReturn,
  }) {
    return SaleItemModel(
      variantId: variantId ?? this.variantId,
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      promotionDiscount: promotionDiscount ?? this.promotionDiscount,
      isReturn: isReturn ?? this.isReturn,
    );
  }

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      variantId: json['variantId'] ?? '',
      productId: json['productId'],
      categoryId: json['categoryId'],
      productName: json['productName'] ?? '',
      size: json['size'] ?? '',
      color: json['color'] ?? '',
      price: (json['price'] as num?)?.toInt() ?? 0,
      quantity: json['quantity'] ?? 0,
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      promotionDiscount: (json['promotionDiscount'] as num?)?.toInt() ?? 0,
      isReturn: json['isReturn'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'variantId': variantId,
      'productId': productId,
      'categoryId': categoryId,
      'productName': productName,
      'size': size,
      'color': color,
      'price': price,
      'quantity': quantity,
      'discount': discount,
      'promotionDiscount': promotionDiscount,
      'isReturn': isReturn,
    };
  }

  factory SaleItemModel.fromEntity(SaleItemEntity entity) {
    return SaleItemModel(
      variantId: entity.variantId,
      productId: entity.productId,
      categoryId: entity.categoryId,
      productName: entity.productName,
      size: entity.size,
      color: entity.color,
      price: entity.price,
      quantity: entity.quantity,
      discount: entity.discount,
      promotionDiscount: entity.promotionDiscount,
      isReturn: entity.isReturn,
    );
  }
}
