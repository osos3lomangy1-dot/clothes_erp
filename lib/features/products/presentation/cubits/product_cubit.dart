import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_products_usecase.dart';
import '../../domain/usecases/delete_product_usecase.dart';
import '../../domain/repositories/product_repository.dart';
import 'product_state.dart';

@injectable
class ProductCubit extends Cubit<ProductState> {
  final ProductRepository _productRepository;
  final DeleteProductUseCase _deleteProductUseCase;
  StreamSubscription? _productsSubscription;

  ProductCubit(
    this._productRepository,
    this._deleteProductUseCase,
  ) : super(ProductInitial()) {
    _listenToProducts();
  }

  void _listenToProducts() {
    _productsSubscription?.cancel();
    _productsSubscription = _productRepository.watchAllProducts().listen(
      (result) {
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
      },
      onError: (e) => emit(ProductError('تعذر تحميل بيانات المنتجات: $e')),
    );
  }

  Future<void> getProducts() async {
    emit(ProductLoading());
    try {
      final result = await _productRepository.getProducts();
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
    } catch (e) {
      emit(ProductError('تعذر تحميل بيانات المنتجات: $e'));
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      final result = await _deleteProductUseCase(id);
      result.fold(
        (failure) => emit(ProductError(failure.message)),
        (_) {},
      );
    } catch (e) {
      emit(ProductError('تعذر حذف المنتج: $e'));
    }
  }

  @override
  Future<void> close() {
    _productsSubscription?.cancel();
    return super.close();
  }
}