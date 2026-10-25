import 'package:equatable/equatable.dart';

class SaleItemEntity extends Equatable {
  final String variantId;
  final String productName;
  final String size;
  final String color;
  final double price;
  final int quantity;

  const SaleItemEntity({
    required this.variantId,
    required this.productName,
    required this.size,
    required this.color,
    required this.price,
    required this.quantity,
  });

  SaleItemEntity copyWith({
    String? variantId,
    String? productName,
    String? size,
    String? color,
    double? price,
    int? quantity,
  }) {
    return SaleItemEntity(
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
    );
  }

  double get total => price * quantity;

  @override
  List<Object?> get props => [variantId, productName, size, color, price, quantity];
}
