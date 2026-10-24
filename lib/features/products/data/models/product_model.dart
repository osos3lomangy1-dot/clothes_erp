import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/product_entity.dart';

class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.name,
    required super.description,
    required super.categoryId,
    required super.categoryName,
    super.images,
    super.barcode,
    required super.createdAt,
  });

  ProductModel copyWith({
    String? id,
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    List<String>? images,
    String? barcode,
    DateTime? createdAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      images: images ?? this.images,
      barcode: barcode ?? this.barcode,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ProductModel.fromEntity(ProductEntity entity) {
    return ProductModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      categoryId: entity.categoryId,
      categoryName: entity.categoryName,
      images: entity.images,
      barcode: entity.barcode,
      createdAt: entity.createdAt,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      categoryId: json['categoryId'] ?? '',
      categoryName: json['categoryName'] ?? '',
      images: (json['images'] as List?)?.map((e) => e.toString()).toList(),
      barcode: json['barcode'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'images': images,
      'barcode': barcode,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ProductModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return ProductModel(
      id: documentId,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      categoryId: data['categoryId'] ?? '',
      categoryName: data['categoryName'] ?? '',
      images: (data['images'] as List?)?.map((e) => e.toString()).toList(),
      barcode: data['barcode'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'images': images,
      'barcode': barcode,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
