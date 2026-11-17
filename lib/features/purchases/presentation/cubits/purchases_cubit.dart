import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../data/datasources/purchases_local_data_source.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/purchase_return_entity.dart';
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

    final returnsResult = await _repository.getPurchaseReturns(
      supplierId: supplierId,
    );
    final returns = returnsResult.getOrElse(() => state.returns);

    result.fold(
      (failure) => emit(state.copyWith(
        status: PurchasesStatus.error,
        errorMessage: failure.message,
        returns: returns,
      )),
      (purchases) => emit(state.copyWith(
        status: PurchasesStatus.loaded,
        purchases: purchases,
        returns: returns,
      )),
    );
  }

  Future<void> loadReturns({
    String? supplierId,
    String? purchaseId,
  }) async {
    final result = await _repository.getPurchaseReturns(
      supplierId: supplierId,
      purchaseId: purchaseId,
    );

    result.fold(
      (failure) => null,
      (returns) => emit(state.copyWith(returns: returns)),
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
    String? goodsReceiptId,
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
      goodsReceiptId: goodsReceiptId,
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

  Future<PurchaseReturnEntity?> createPurchaseReturn({
    required String supplierId,
    String? purchaseId,
    required List<PurchaseReturnItemDraft> items,
    required String refundType,
    String? reason,
    required String userId,
  }) async {
    emit(state.copyWith(status: PurchasesStatus.loading));

    final result = await _repository.createPurchaseReturn(
      supplierId: supplierId,
      purchaseId: purchaseId,
      items: items,
      refundType: refundType,
      reason: reason,
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
      (newReturn) async {
        final updatedPurchasesResult = await _repository.getPurchases(
          supplierId: state.selectedSupplierId,
          paymentStatus: state.selectedPaymentStatus,
        );

        final updatedList = [newReturn, ...state.returns];
        emit(state.copyWith(
          status: PurchasesStatus.loaded,
          returns: updatedList,
          purchases: updatedPurchasesResult.getOrElse(() => state.purchases),
        ));
        return newReturn;
      },
    );
  }
}
