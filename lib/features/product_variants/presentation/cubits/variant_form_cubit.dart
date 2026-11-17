import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/di/injection.dart';
import '../../data/datasources/variant_local_data_source.dart';
import '../../domain/entities/variant_entity.dart';
import '../../domain/usecases/add_variant_usecase.dart';
import '../../domain/usecases/update_variant_usecase.dart';
import 'variant_form_state.dart';

@injectable
class VariantFormCubit extends Cubit<VariantFormState> {
  final AddVariantUseCase _addVariantUseCase;
  final UpdateVariantUseCase _updateVariantUseCase;
  final VariantLocalDataSource? _variantLocalDataSource;

  VariantFormCubit(
    this._addVariantUseCase,
    this._updateVariantUseCase, {
    @ignoreParam VariantLocalDataSource? variantLocalDataSource,
  })  : _variantLocalDataSource = variantLocalDataSource,
        super(const VariantFormState());

  Future<void> init(VariantEntity? variant) async {
    Set<String> existingSkus = const {};
    try {
      final ds = _variantLocalDataSource ??
          (getIt.isRegistered<VariantLocalDataSource>()
              ? getIt<VariantLocalDataSource>()
              : null);
      if (ds != null) {
        final all = await ds.getAllVariants();
        existingSkus = all
            .where((v) => variant == null || v.id != variant.id)
            .map((v) => v.sku.trim().toLowerCase())
            .toSet();
      }
    } catch (_) {}

    if (variant != null) {
      emit(state.copyWith(
        productCode: variant.productCode,
        color: variant.color,
        size: variant.size,
        quantity: variant.quantity,
        costPrice: variant.costPrice,
        salePrice: variant.salePrice,
        wholesalePrice: variant.wholesalePrice,
        minStock: variant.minStock,
        isEdit: true,
        existingSkus: existingSkus,
        hasDuplicateSku: false,
      ));
    } else {
      emit(state.copyWith(existingSkus: existingSkus));
    }
  }

  void onProductCodeChanged(String value) {
    final cleanLower = value.trim().toLowerCase();
    final isDup = cleanLower.isNotEmpty && state.existingSkus.contains(cleanLower);
    emit(state.copyWith(productCode: value, hasDuplicateSku: isDup));
  }

  void onColorChanged(String value) => emit(state.copyWith(color: value));
  void onSizeChanged(String value) => emit(state.copyWith(size: value));
  void onQuantityChanged(int value) => emit(state.copyWith(quantity: value));
  void onCostPriceChanged(int value) => emit(state.copyWith(costPrice: value));
  void onSalePriceChanged(int value) => emit(state.copyWith(salePrice: value));
  void onWholesalePriceChanged(int value) => emit(state.copyWith(wholesalePrice: value));
  void onMinStockChanged(int value) => emit(state.copyWith(minStock: value));

  Future<void> submit({required String? id, required String productId}) async {
    final cleanCode = state.productCode.trim();
    if (cleanCode.isEmpty || state.color.trim().isEmpty || state.size.trim().isEmpty) {
      emit(state.copyWith(
        status: VariantFormStatus.error,
        errorMessage: 'يرجى إدخال كود الصنف واللون والمقاس',
      ));
      return;
    }

    if (state.hasDuplicateSku || state.existingSkus.contains(cleanCode.toLowerCase())) {
      emit(state.copyWith(
        status: VariantFormStatus.error,
        hasDuplicateSku: true,
        errorMessage: 'عفواً، الكود ("$cleanCode") مسجل بالفعل لصنف آخر. لا يمكن تكرار الأكواد.',
      ));
      return;
    }

    emit(state.copyWith(status: VariantFormStatus.loading));

    final variant = VariantEntity(
      id: id ?? '',
      productId: productId,
      productCode: cleanCode,
      color: state.color,
      size: state.size,
      quantity: state.quantity,
      costPrice: state.costPrice,
      salePrice: state.salePrice,
      wholesalePrice: state.wholesalePrice,
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
