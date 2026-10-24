import 'package:equatable/equatable.dart';

class SaleItemEntity extends Equatable {
  final String variantId;
  final String productCode;
  final double price;
  final int quantity;

  const SaleItemEntity({
    required this.variantId,
    required this.productCode,
    required this.price,
    required this.quantity,
  });

  double get total => price * quantity;

  @override
  List<Object?> get props => [variantId, productCode, price, quantity];
}
