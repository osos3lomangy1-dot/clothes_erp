import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_variants_usecase.dart';
import '../../domain/usecases/delete_variant_usecase.dart';
import 'variant_state.dart';

@injectable
class VariantCubit extends Cubit<VariantState> {
  final GetVariantsUseCase _getVariantsUseCase;
  final DeleteVariantUseCase _deleteVariantUseCase;

  VariantCubit(
    this._getVariantsUseCase,
    this._deleteVariantUseCase,
  ) : super(VariantInitial());

  Future<void> getVariants(String productId) async {
    emit(VariantLoading());
    final result = await _getVariantsUseCase(productId);
    result.fold(
      (failure) => emit(VariantError(failure.message)),
      (variants) {
        if (variants.isEmpty) {
          emit(VariantEmpty());
        } else {
          emit(VariantLoaded(variants));
        }
      },
    );
  }

  Future<void> deleteVariant(String id, String productId) async {
    final result = await _deleteVariantUseCase(id);
    result.fold(
      (failure) => emit(VariantError(failure.message)),
      (_) => getVariants(productId),
    );
  }
}
