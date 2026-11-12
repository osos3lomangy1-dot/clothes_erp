import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_variants_usecase.dart';
import '../../domain/usecases/delete_variant_usecase.dart';
import '../../domain/repositories/variant_repository.dart';
import 'variant_state.dart';

@injectable
class VariantCubit extends Cubit<VariantState> {
  final VariantRepository _variantRepository;
  final GetVariantsUseCase _getVariantsUseCase;
  final DeleteVariantUseCase _deleteVariantUseCase;
  String? _currentProductId;
  StreamSubscription? _variantsSubscription;

  VariantCubit(
    this._variantRepository,
    this._getVariantsUseCase,
    this._deleteVariantUseCase,
  ) : super(VariantInitial());

  Future<void> getVariants(String productId) async {
    _currentProductId = productId;
    _variantsSubscription?.cancel();
    _variantsSubscription = _variantRepository.watchVariants(productId).listen(
      (result) {
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
      },
      onError: (e) => emit(VariantError('تعذر تحميل المقاسات: $e')),
    );
  }

  Future<void> deleteVariant(String id, String productId) async {
    final result = await _deleteVariantUseCase(id);
    result.fold(
      (failure) => emit(VariantError(failure.message)),
      (_) {},
    );
  }

  @override
  Future<void> close() {
    _variantsSubscription?.cancel();
    return super.close();
  }
}