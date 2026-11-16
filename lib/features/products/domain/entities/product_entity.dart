import 'package:equatable/equatable.dart';

class VariantSummary extends Equatable {
  final String id;
  final String sku; // serves as barcode/SKU/productCode
  final String color;
  final String size;
  final int quantity;

  const VariantSummary({
    required this.id,
    required this.sku,
    required this.color,
    required this.size,
    required this.quantity,
  });

  @override
  List<Object?> get props => [id, sku, color, size, quantity];
}

class ProductEntity extends Equatable {
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final List<String>? images;
  final DateTime createdAt;
  final int minStock;
  final bool isActive;
  final List<VariantSummary> variants;

  const ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    this.images,
    required this.createdAt,
    this.minStock = 5,
    this.isActive = true,
    this.variants = const [],
  });

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        categoryId,
        categoryName,
        images,
        createdAt,
        minStock,
        isActive,
        variants,
      ];
}
