import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../categories/domain/usecases/get_categories_usecase.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/usecases/add_product_usecase.dart';
import '../../domain/usecases/update_product_usecase.dart';
import 'product_form_state.dart';

@injectable
class ProductFormCubit extends Cubit<ProductFormState> {
  final AddProductUseCase _addProductUseCase;
  final UpdateProductUseCase _updateProductUseCase;
  final GetCategoriesUseCase _getCategoriesUseCase;

  ProductFormCubit(
    this._addProductUseCase,
    this._updateProductUseCase,
    this._getCategoriesUseCase,
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
}
