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
  final int wholesalePrice;
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
    this.wholesalePrice = 0,
    required this.minStock,
    required this.createdAt,
    String? productName,
  }) : _productName = productName;

  VariantEntity copyWith({
    String? id,
    String? productId,
    String? productCode,
    String? color,
    String? size,
    int? quantity,
    int? costPrice,
    int? salePrice,
    int? wholesalePrice,
    int? minStock,
    DateTime? createdAt,
    String? productName,
  }) {
    return VariantEntity(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productCode: productCode ?? this.productCode,
      color: color ?? this.color,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      costPrice: costPrice ?? this.costPrice,
      salePrice: salePrice ?? this.salePrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      minStock: minStock ?? this.minStock,
      createdAt: createdAt ?? this.createdAt,
      productName: productName ?? _productName,
    );
  }

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
        wholesalePrice,
        minStock,
        createdAt,
        _productName,
      ];
}
