import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/delete_variant_usecase.dart';
import '../../domain/repositories/variant_repository.dart';
import 'variant_state.dart';

@injectable
class VariantCubit extends Cubit<VariantState> {
  final VariantRepository _variantRepository;
  final DeleteVariantUseCase _deleteVariantUseCase;
  StreamSubscription? _variantsSubscription;

  VariantCubit(
    this._variantRepository,
    this._deleteVariantUseCase,
  ) : super(VariantInitial());

  Future<void> getVariants(String productId) async {
    _variantsSubscription?.cancel();
    _variantsSubscription = _variantRepository.watchVariants(productId).listen(
      (result) {
        if (isClosed) return;
        result.fold(
          (failure) {
            if (!isClosed) emit(VariantError(failure.message));
          },
          (variants) {
            if (isClosed) return;
            if (variants.isEmpty) {
              emit(VariantEmpty());
            } else {
              emit(VariantLoaded(variants));
            }
          },
        );
      },
      onError: (e) {
        if (!isClosed) emit(VariantError('تعذر تحميل المقاسات: $e'));
      },
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