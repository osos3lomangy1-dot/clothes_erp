import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_products_usecase.dart';
import '../../domain/usecases/delete_product_usecase.dart';
import 'product_state.dart';

@injectable
class ProductCubit extends Cubit<ProductState> {
  final GetProductsUseCase _getProductsUseCase;
  final DeleteProductUseCase _deleteProductUseCase;

  ProductCubit(
    this._getProductsUseCase,
    this._deleteProductUseCase,
  ) : super(ProductInitial());

  Future<void> getProducts() async {
    emit(ProductLoading());
    final result = await _getProductsUseCase();
    result.fold(
      (failure) => emit(ProductError(failure.message)),
      (products) {
        if (products.isEmpty) {
          emit(ProductEmpty());
        } else {
          emit(ProductLoaded(products));
        }
      },
    );
  }

  Future<void> deleteProduct(String id) async {
    final result = await _deleteProductUseCase(id);
    result.fold(
      (failure) => emit(ProductError(failure.message)),
      (_) => getProducts(),
    );
  }
}
