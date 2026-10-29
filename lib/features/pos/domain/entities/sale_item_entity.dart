import 'package:equatable/equatable.dart';

class SaleItemEntity extends Equatable {
  final String variantId;
  final String productName;
  final String size;
  final String color;
  final int price;
  final int quantity;
  final int discount;
  final bool isReturn;

  const SaleItemEntity({
    required this.variantId,
    required this.productName,
    required this.size,
    required this.color,
    required this.price,
    required this.quantity,
    this.discount = 0,
    this.isReturn = false,
  });

  SaleItemEntity copyWith({
    String? variantId,
    String? productName,
    String? size,
    String? color,
    int? price,
    int? quantity,
    int? discount,
    bool? isReturn,
  }) {
    return SaleItemEntity(
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      isReturn: isReturn ?? this.isReturn,
    );
  }

  int get total => isReturn ? -((price * quantity) - discount) : (price * quantity) - discount;

  @override
  List<Object?> get props => [variantId, productName, size, color, price, quantity, discount, isReturn];
}
