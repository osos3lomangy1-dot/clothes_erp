import 'package:equatable/equatable.dart';

class VariantEntity extends Equatable {
  final String id;
  final String productId;
  final String productCode;
  final String color;
  final String size;
  final int quantity;
  final double costPrice;
  final double salePrice;
  final int minStock;
  final DateTime createdAt;

  const VariantEntity({
    required this.id,
    required this.productId,
    required this.productCode,
    required this.color,
    required this.size,
    required this.quantity,
    required this.costPrice,
    required this.salePrice,
    required this.minStock,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id,
        productId,
        productCode,
        color,
        size,
        quantity,
        costPrice,
        salePrice,
        minStock,
        createdAt,
      ];
}
