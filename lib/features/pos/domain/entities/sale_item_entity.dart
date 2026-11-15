import 'package:equatable/equatable.dart';

class SaleItemEntity extends Equatable {
  final String variantId;
  final String? productId;
  final String? categoryId;
  final String productName;
  final String size;
  final String color;
  final int price;
  final int quantity;
  final int discount;
  final int promotionDiscount;
  final bool isReturn;

  const SaleItemEntity({
    required this.variantId,
    this.productId,
    this.categoryId,
    required this.productName,
    required this.size,
    required this.color,
    required this.price,
    required this.quantity,
    this.discount = 0,
    this.promotionDiscount = 0,
    this.isReturn = false,
  });

  SaleItemEntity copyWith({
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
    return SaleItemEntity(
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

  int get total => isReturn
      ? -((price * quantity) - discount - promotionDiscount)
      : (price * quantity) - discount - promotionDiscount;

  @override
  List<Object?> get props => [
        variantId,
        productId,
        categoryId,
        productName,
        size,
        color,
        price,
        quantity,
        discount,
        promotionDiscount,
        isReturn,
      ];
}
