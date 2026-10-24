import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/variant_entity.dart';
import '../../domain/usecases/add_variant_usecase.dart';
import '../../domain/usecases/update_variant_usecase.dart';
import 'variant_form_state.dart';

@injectable
class VariantFormCubit extends Cubit<VariantFormState> {
  final AddVariantUseCase _addVariantUseCase;
  final UpdateVariantUseCase _updateVariantUseCase;

  VariantFormCubit(
    this._addVariantUseCase,
    this._updateVariantUseCase,
  ) : super(const VariantFormState());

  void init(VariantEntity? variant) {
    if (variant != null) {
      emit(state.copyWith(
        productCode: variant.productCode,
        color: variant.color,
        size: variant.size,
        quantity: variant.quantity,
        costPrice: variant.costPrice,
        salePrice: variant.salePrice,
        minStock: variant.minStock,
        isEdit: true,
      ));
    }
  }

  void onProductCodeChanged(String value) => emit(state.copyWith(productCode: value));
  void onColorChanged(String value) => emit(state.copyWith(color: value));
  void onSizeChanged(String value) => emit(state.copyWith(size: value));
  void onQuantityChanged(int value) => emit(state.copyWith(quantity: value));
  void onCostPriceChanged(double value) => emit(state.copyWith(costPrice: value));
  void onSalePriceChanged(double value) => emit(state.copyWith(salePrice: value));
  void onMinStockChanged(int value) => emit(state.copyWith(minStock: value));

  Future<void> submit({required String? id, required String productId}) async {
    if (state.productCode.isEmpty || state.color.isEmpty || state.size.isEmpty) {
      emit(state.copyWith(
        status: VariantFormStatus.error,
        errorMessage: 'Product Code, Color, and Size are required',
      ));
      return;
    }

    emit(state.copyWith(status: VariantFormStatus.loading));

    final variant = VariantEntity(
      id: id ?? '',
      productId: productId,
      productCode: state.productCode,
      color: state.color,
      size: state.size,
      quantity: state.quantity,
      costPrice: state.costPrice,
      salePrice: state.salePrice,
      minStock: state.minStock,
      createdAt: DateTime.now(),
    );

    final result = state.isEdit
        ? await _updateVariantUseCase(variant)
        : await _addVariantUseCase(variant);

    result.fold(
      (failure) => emit(state.copyWith(
        status: VariantFormStatus.error,
        errorMessage: failure.message,
      )),
      (_) => emit(state.copyWith(status: VariantFormStatus.success)),
    );
  }
}
