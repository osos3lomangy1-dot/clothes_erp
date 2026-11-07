import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../categories/domain/usecases/get_categories_usecase.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/usecases/add_product_usecase.dart';
import '../../domain/usecases/update_product_usecase.dart';
import 'product_form_state.dart';

@injectable
class ProductFormCubit extends Cubit<ProductFormState> {
  final AddProductUseCase _addProductUseCase;
  final UpdateProductUseCase _updateProductUseCase;
  final GetCategoriesUseCase _getCategoriesUseCase;
  final ProductRepository _productRepository;

  ProductFormCubit(
    this._addProductUseCase,
    this._updateProductUseCase,
    this._getCategoriesUseCase,
    this._productRepository,
  ) : super(const ProductFormState());

  Future<void> init(ProductEntity? product) async {
    emit(state.copyWith(status: ProductFormStatus.loading));
    
    final categoriesResult = await _getCategoriesUseCase();
    
    categoriesResult.fold(
      (failure) => emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: failure.message,
      )),
      (categories) {
        if (product != null) {
          emit(state.copyWith(
            name: product.name,
            description: product.description,
            categoryId: product.categoryId,
            categoryName: product.categoryName,
            categories: categories,
            isEdit: true,
            status: ProductFormStatus.initial,
          ));
        } else {
          emit(state.copyWith(
            categories: categories,
            status: ProductFormStatus.initial,
          ));
        }
      },
    );
  }

  void onNameChanged(String value) {
    emit(state.copyWith(name: value));
  }

  void onDescriptionChanged(String value) {
    emit(state.copyWith(description: value));
  }

  void onCategoryChanged(String id, String name) {
    emit(state.copyWith(categoryId: id, categoryName: name));
  }

  Future<void> submit(String? id) async {
    if (state.name.isEmpty || state.categoryId == null) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: 'Name and Category are required',
      ));
      return;
    }

    emit(state.copyWith(status: ProductFormStatus.loading));

    final product = ProductEntity(
      id: id ?? '',
      name: state.name,
      description: state.description,
      categoryId: state.categoryId!,
      categoryName: state.categoryName!,
      createdAt: DateTime.now(),
    );

    final result = state.isEdit
        ? await _updateProductUseCase(product)
        : await _addProductUseCase(product);

    result.fold(
      (failure) => emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: failure.message,
      )),
      (_) => emit(state.copyWith(status: ProductFormStatus.success)),
    );
  }

  Future<void> submitWithVariants({
    String? id,
    required List<VariantInput> variants,
  }) async {
    if (state.name.trim().isEmpty || state.categoryId == null) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: 'اسم المنتج والتصنيف مطلوبان',
      ));
      return;
    }

    if (!state.isEdit && variants.isEmpty) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: 'يرجى إضافة مقاس واحد على الأقل في جدول المقاسات',
      ));
      return;
    }

    emit(state.copyWith(status: ProductFormStatus.loading));

    final product = ProductEntity(
      id: id ?? '',
      name: state.name.trim(),
      description: state.description,
      categoryId: state.categoryId!,
      categoryName: state.categoryName ?? '',
      createdAt: DateTime.now(),
    );

    if (state.isEdit) {
      final result = await _updateProductUseCase(product);
      result.fold(
        (failure) => emit(state.copyWith(
          status: ProductFormStatus.error,
          errorMessage: failure.message,
        )),
        (_) => emit(state.copyWith(status: ProductFormStatus.success)),
      );
    } else {
      final result = await _productRepository.addProductWithVariants(product, variants);
      result.fold(
        (failure) => emit(state.copyWith(
          status: ProductFormStatus.error,
          errorMessage: failure.message,
        )),
        (_) => emit(state.copyWith(status: ProductFormStatus.success)),
      );
    }
  }
}
