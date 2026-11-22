import '../../domain/entities/product_entity.dart';

class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.name,
    required super.description,
    required super.categoryId,
    required super.categoryName,
    super.images,
    required super.createdAt,
    super.updatedAt,
    super.minStock,
    super.isActive,
    super.activityType,
    super.warrantyPeriod,
    super.brandOrModel,
    super.isInstallmentEligible,
    super.sellMode,
    super.unit,
    super.rollWidth,
  });

  @override
  ProductModel copyWith({
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
    return ProductModel(
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

  factory ProductModel.fromEntity(ProductEntity entity) {
    return ProductModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      categoryId: entity.categoryId,
      categoryName: entity.categoryName,
      images: entity.images,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      minStock: entity.minStock,
      isActive: entity.isActive,
      activityType: entity.activityType,
      warrantyPeriod: entity.warrantyPeriod,
      brandOrModel: entity.brandOrModel,
      isInstallmentEligible: entity.isInstallmentEligible,
      sellMode: entity.sellMode,
      unit: entity.unit,
      rollWidth: entity.rollWidth,
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
      minStock: json['minStock'] ?? 5,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
      activityType: json['activityType'] ?? 'clothing',
      warrantyPeriod: json['warrantyPeriod'],
      brandOrModel: json['brandOrModel'],
      isInstallmentEligible: json['isInstallmentEligible'] ?? true,
      sellMode: json['sellMode'] ?? 'piece',
      unit: json['unit'] ?? 'piece',
      rollWidth: json['rollWidth'],
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
      'minStock': minStock,
      'isActive': isActive,
      'activityType': activityType,
      'warrantyPeriod': warrantyPeriod,
      'brandOrModel': brandOrModel,
      'isInstallmentEligible': isInstallmentEligible,
      'sellMode': sellMode,
      'unit': unit,
      'rollWidth': rollWidth,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
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
      minStock: data['minStock'] ?? 5,
      isActive: data['isActive'] ?? true,
      activityType: data['activityType'] ?? 'clothing',
      warrantyPeriod: data['warrantyPeriod'],
      brandOrModel: data['brandOrModel'],
      isInstallmentEligible: data['isInstallmentEligible'] ?? true,
      sellMode: data['sellMode'] ?? 'piece',
      unit: data['unit'] ?? 'piece',
      rollWidth: data['rollWidth'],
      createdAt: data['createdAt'] is DateTime
          ? data['createdAt'] as DateTime
          : (data['createdAt'] is String
              ? DateTime.tryParse(data['createdAt']) ?? DateTime.now()
              : DateTime.now()),
      updatedAt: data['updatedAt'] is DateTime
          ? data['updatedAt'] as DateTime
          : (data['updatedAt'] is String
              ? DateTime.tryParse(data['updatedAt'])
              : null),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'images': images,
      'minStock': minStock,
      'isActive': isActive,
      'activityType': activityType,
      'warrantyPeriod': warrantyPeriod,
      'brandOrModel': brandOrModel,
      'isInstallmentEligible': isInstallmentEligible,
      'sellMode': sellMode,
      'unit': unit,
      'rollWidth': rollWidth,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
