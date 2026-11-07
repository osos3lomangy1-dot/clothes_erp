import 'package:equatable/equatable.dart';

class VariantEntity extends Equatable {
  final String id;
  final String productId;
  final String productCode;
  final String color;
  final String size;
  final int quantity;
  final int costPrice;
  final int salePrice;
  final int minStock;
  final DateTime createdAt;

  final String? _productName;

  String get sku => productCode;
  String get productName {
    final name = _productName;
    return (name != null && name.isNotEmpty) ? name : productCode;
  }

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
    String? productName,
  }) : _productName = productName;

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
        _productName,
      ];
}
