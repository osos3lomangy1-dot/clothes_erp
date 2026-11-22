import 'package:equatable/equatable.dart';
import 'activity_type.dart';

export 'activity_type.dart';

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
  final DateTime? updatedAt;
  final int minStock;
  final bool isActive;
  final List<VariantSummary> variants;

  // --- محرك تعدد الأنشطة والخصائص التكيفية (Task 8.6 & Task 18) ---
  final String activityType; // clothing, footwearBags, accessoriesBeauty, homeLiving, general
  final String? warrantyPeriod;
  final String? brandOrModel;
  final bool isInstallmentEligible;
  final String sellMode; // 'piece', 'meter'
  final String unit; // 'piece', 'meter', 'cm', 'kg'
  final String? rollWidth;

  const ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    this.images,
    required this.createdAt,
    this.updatedAt,
    this.minStock = 5,
    this.isActive = true,
    this.variants = const [],
    this.activityType = 'clothing',
    this.warrantyPeriod,
    this.brandOrModel,
    this.isInstallmentEligible = true,
    this.sellMode = 'piece',
    this.unit = 'piece',
    this.rollWidth,
  });

  ActivityType get activityTypeEnum => ActivityType.fromString(activityType);

  ProductEntity copyWith({
    String? id,
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    List<String>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? minStock,
    bool? isActive,
    List<VariantSummary>? variants,
    String? activityType,
    String? warrantyPeriod,
    String? brandOrModel,
    bool? isInstallmentEligible,
    String? sellMode,
    String? unit,
    String? rollWidth,
  }) {
    return ProductEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      minStock: minStock ?? this.minStock,
      isActive: isActive ?? this.isActive,
      variants: variants ?? this.variants,
      activityType: activityType ?? this.activityType,
      warrantyPeriod: warrantyPeriod ?? this.warrantyPeriod,
      brandOrModel: brandOrModel ?? this.brandOrModel,
      isInstallmentEligible:
          isInstallmentEligible ?? this.isInstallmentEligible,
      sellMode: sellMode ?? this.sellMode,
      unit: unit ?? this.unit,
      rollWidth: rollWidth ?? this.rollWidth,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        categoryId,
        categoryName,
        images,
        createdAt,
        updatedAt,
        minStock,
        isActive,
        variants,
        activityType,
        warrantyPeriod,
        brandOrModel,
        isInstallmentEligible,
        sellMode,
        unit,
        rollWidth,
      ];
}
