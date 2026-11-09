import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../data/datasources/purchases_local_data_source.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchases_repository.dart';
import 'purchases_state.dart';

@injectable
class PurchasesCubit extends Cubit<PurchasesState> {
  final PurchasesRepository _repository;

  PurchasesCubit(this._repository) : super(const PurchasesState());

  Future<void> loadPurchases({
    String? supplierId,
    String? paymentStatus,
  }) async {
    emit(state.copyWith(
      status: PurchasesStatus.loading,
      selectedSupplierId: supplierId,
      selectedPaymentStatus: paymentStatus,
    ));

    final result = await _repository.getPurchases(
      supplierId: supplierId,
      paymentStatus: paymentStatus,
    );

    result.fold(
      (failure) => emit(state.copyWith(
        status: PurchasesStatus.error,
        errorMessage: failure.message,
      )),
      (purchases) => emit(state.copyWith(
        status: PurchasesStatus.loaded,
        purchases: purchases,
      )),
    );
  }

  Future<PurchaseEntity?> createPurchaseInvoice({
    required String supplierId,
    String? invoiceNumber,
    required DateTime purchaseDate,
    required int paidAmount,
    String? notes,
    required List<PurchaseItemDraft> items,
    required String userId,
  }) async {
    emit(state.copyWith(status: PurchasesStatus.loading));

    final result = await _repository.createPurchaseInvoice(
      supplierId: supplierId,
      invoiceNumber: invoiceNumber,
      purchaseDate: purchaseDate,
      paidAmount: paidAmount,
      notes: notes,
      items: items,
      userId: userId,
    );

    return result.fold(
      (failure) {
        emit(state.copyWith(
          status: PurchasesStatus.error,
          errorMessage: failure.message,
        ));
        return null;
      },
      (newPurchase) {
        final updatedList = [newPurchase, ...state.purchases];
        emit(state.copyWith(
          status: PurchasesStatus.loaded,
          purchases: updatedList,
        ));
        return newPurchase;
      },
    );
  }
}

