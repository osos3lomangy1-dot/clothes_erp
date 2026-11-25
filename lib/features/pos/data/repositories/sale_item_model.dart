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
    super.decimalQuantity,
    super.unit,
    super.discount,
    super.promotionDiscount,
    super.isReturn,
    super.kitchenNotes,
    super.modifiers,
    super.imei,
    super.deviceCondition,
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
    double? decimalQuantity,
    String? unit,
    bool clearDecimalQuantity = false,
    int? discount,
    int? promotionDiscount,
    bool? isReturn,
    String? kitchenNotes,
    bool clearKitchenNotes = false,
    List<String>? modifiers,
    String? imei,
    String? deviceCondition,
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
      decimalQuantity: clearDecimalQuantity
          ? null
          : (decimalQuantity ?? this.decimalQuantity),
      unit: unit ?? this.unit,
      discount: discount ?? this.discount,
      promotionDiscount: promotionDiscount ?? this.promotionDiscount,
      isReturn: isReturn ?? this.isReturn,
      kitchenNotes: clearKitchenNotes
          ? null
          : (kitchenNotes ?? this.kitchenNotes),
      modifiers: modifiers ?? this.modifiers,
      imei: imei ?? this.imei,
      deviceCondition: deviceCondition ?? this.deviceCondition,
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
      decimalQuantity: (json['decimalQuantity'] as num?)?.toDouble(),
      unit: json['unit'],
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      promotionDiscount: (json['promotionDiscount'] as num?)?.toInt() ?? 0,
      isReturn: json['isReturn'] ?? false,
      kitchenNotes: json['kitchenNotes'],
      modifiers: (json['modifiers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
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
      'decimalQuantity': decimalQuantity,
      'unit': unit,
      'discount': discount,
      'promotionDiscount': promotionDiscount,
      'isReturn': isReturn,
      if (kitchenNotes != null) 'kitchenNotes': kitchenNotes,
      if (modifiers.isNotEmpty) 'modifiers': modifiers,
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
      decimalQuantity: entity.decimalQuantity,
      unit: entity.unit,
      discount: entity.discount,
      promotionDiscount: entity.promotionDiscount,
      isReturn: entity.isReturn,
      kitchenNotes: entity.kitchenNotes,
      modifiers: entity.modifiers,
    );
  }
}
