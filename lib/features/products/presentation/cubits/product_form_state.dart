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
  });

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
      ];
}
