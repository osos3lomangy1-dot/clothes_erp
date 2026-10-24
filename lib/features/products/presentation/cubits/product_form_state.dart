import 'package:equatable/equatable.dart';
import '../../../categories/domain/entities/category_entity.dart';

enum ProductFormStatus { initial, loading, success, error }

class ProductFormState extends Equatable {
  final String name;
  final String description;
  final String? categoryId;
  final String? categoryName;
  final List<CategoryEntity> categories;
  final ProductFormStatus status;
  final String? errorMessage;
  final bool isEdit;

  const ProductFormState({
    this.name = '',
    this.description = '',
    this.categoryId,
    this.categoryName,
    this.categories = const [],
    this.status = ProductFormStatus.initial,
    this.errorMessage,
    this.isEdit = false,
  });

  ProductFormState copyWith({
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    List<CategoryEntity>? categories,
    ProductFormStatus? status,
    String? errorMessage,
    bool? isEdit,
  }) {
    return ProductFormState(
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categories: categories ?? this.categories,
      status: status ?? this.status,
      errorMessage: errorMessage,
      isEdit: isEdit ?? this.isEdit,
    );
  }

  @override
  List<Object?> get props => [
        name,
        description,
        categoryId,
        categoryName,
        categories,
        status,
        errorMessage,
        isEdit,
      ];
}
