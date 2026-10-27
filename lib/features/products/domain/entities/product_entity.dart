import 'package:equatable/equatable.dart';

class ProductEntity extends Equatable {
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final List<String>? images;
  final String? barcode;
  final DateTime createdAt;
  final int minStock;
  final bool isActive;

  const ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    this.images,
    this.barcode,
    required this.createdAt,
    this.minStock = 5,
    this.isActive = true,
  });

  @override
  List<Object?> get props => [id, name, description, categoryId, categoryName, images, barcode, createdAt, minStock, isActive];
}
