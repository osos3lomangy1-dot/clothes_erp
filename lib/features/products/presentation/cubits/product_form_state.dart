import 'package:equatable/equatable.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../domain/entities/product_entity.dart';

enum ProductFormStatus { initial, loading, success, error }

class ProductFormState extends Equatable {
  final String name;
  final String description;
  final String? categoryId;
  final String? categoryName;
  final int minStock;
  final List<CategoryEntity> categories;
  final ProductFormStatus status;
  final String? errorMessage;
  final bool isEdit;
  final String? editingProductId;
  final List<ProductEntity> existingProducts;
  final List<ProductEntity> similarProducts;
  final ProductEntity? exactDuplicateProduct;
  final Set<String> existingSkus;
  final String activityType;
  final String? warrantyPeriod;
  final String? brandOrModel;
  final bool isInstallmentEligible;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductFormState({
    this.name = '',
    this.description = '',
    this.categoryId,
    this.categoryName,
    this.minStock = 5,
    this.categories = const [],
    this.status = ProductFormStatus.initial,
    this.errorMessage,
    this.isEdit = false,
    this.editingProductId,
    this.existingProducts = const [],
    this.similarProducts = const [],
    this.exactDuplicateProduct,
    this.existingSkus = const {},
    this.activityType = 'clothing',
    this.warrantyPeriod,
    this.brandOrModel,
    this.isInstallmentEligible = true,
    this.createdAt,
    this.updatedAt,
  });

  ActivityType get activityTypeEnum => ActivityType.fromString(activityType);

  bool get hasDuplicate => exactDuplicateProduct != null;
  bool get hasSimilar => similarProducts.isNotEmpty;

  bool isSkuExisting(String sku) {
    final clean = sku.trim().toLowerCase();
    return clean.isNotEmpty && existingSkus.contains(clean);
  }

  ProductFormState copyWith({
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    int? minStock,
    List<CategoryEntity>? categories,
    ProductFormStatus? status,
    String? errorMessage,
    bool? isEdit,
    String? editingProductId,
    List<ProductEntity>? existingProducts,
    List<ProductEntity>? similarProducts,
    ProductEntity? exactDuplicateProduct,
    bool clearExactDuplicate = false,
    Set<String>? existingSkus,
    String? activityType,
    String? warrantyPeriod,
    String? brandOrModel,
    bool? isInstallmentEligible,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductFormState(
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      minStock: minStock ?? this.minStock,
      categories: categories ?? this.categories,
      status: status ?? this.status,
      errorMessage: errorMessage,
      isEdit: isEdit ?? this.isEdit,
      editingProductId: editingProductId ?? this.editingProductId,
      existingProducts: existingProducts ?? this.existingProducts,
      similarProducts: similarProducts ?? this.similarProducts,
      exactDuplicateProduct: clearExactDuplicate ? null : (exactDuplicateProduct ?? this.exactDuplicateProduct),
      existingSkus: existingSkus ?? this.existingSkus,
      activityType: activityType ?? this.activityType,
      warrantyPeriod: warrantyPeriod ?? this.warrantyPeriod,
      brandOrModel: brandOrModel ?? this.brandOrModel,
      isInstallmentEligible: isInstallmentEligible ?? this.isInstallmentEligible,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        name,
        description,
        categoryId,
        categoryName,
        minStock,
        categories,
        status,
        errorMessage,
        isEdit,
        editingProductId,
        existingProducts,
        similarProducts,
        exactDuplicateProduct,
        existingSkus,
        activityType,
        warrantyPeriod,
        brandOrModel,
        isInstallmentEligible,
        createdAt,
        updatedAt,
      ];
}
