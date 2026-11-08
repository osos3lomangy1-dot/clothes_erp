import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/variant_entity.dart';

class VariantModel extends VariantEntity {
  const VariantModel({
    required super.id,
    required super.productId,
    required super.productCode,
    required super.color,
    required super.size,
    required super.quantity,
    required super.costPrice,
    required super.salePrice,
    super.wholesalePrice = 0,
    required super.minStock,
    required super.createdAt,
    super.productName,
  });

  @override
  VariantModel copyWith({
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
    return VariantModel(
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
      productName: productName,
    );
  }

  factory VariantModel.fromEntity(VariantEntity entity) {
    return VariantModel(
      id: entity.id,
      productId: entity.productId,
      productCode: entity.productCode,
      color: entity.color,
      size: entity.size,
      quantity: entity.quantity,
      costPrice: entity.costPrice,
      salePrice: entity.salePrice,
      wholesalePrice: entity.wholesalePrice,
      minStock: entity.minStock,
      createdAt: entity.createdAt,
      productName: entity.productName,
    );
  }

  factory VariantModel.fromJson(Map<String, dynamic> json) {
    return VariantModel(
      id: json['id'] ?? '',
      productId: json['productId'] ?? '',
      productCode: json['productCode'] ?? '',
      color: json['color'] ?? '',
      size: json['size'] ?? '',
      quantity: json['quantity'] ?? 0,
      costPrice: (json['costPrice'] as num?)?.toInt() ?? 0,
      salePrice: (json['salePrice'] as num?)?.toInt() ?? 0,
      minStock: json['minStock'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productCode': productCode,
      'color': color,
      'size': size,
      'quantity': quantity,
      'costPrice': costPrice,
      'salePrice': salePrice,
      'minStock': minStock,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VariantModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return VariantModel(
      id: documentId,
      productId: data['productId'] ?? '',
      productCode: data['productCode'] ?? '',
      color: data['color'] ?? '',
      size: data['size'] ?? '',
      quantity: data['quantity'] ?? 0,
      costPrice: (data['costPrice'] as num?)?.toInt() ?? 0,
      salePrice: (data['salePrice'] as num?)?.toInt() ?? 0,
      minStock: data['minStock'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productId': productId,
      'productCode': productCode,
      'color': color,
      'size': size,
      'quantity': quantity,
      'costPrice': costPrice,
      'salePrice': salePrice,
      'minStock': minStock,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

