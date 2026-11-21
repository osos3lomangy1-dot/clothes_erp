import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/repositories/pre_orders_repository.dart';
import 'pre_orders_state.dart';

@injectable
class PreOrdersCubit extends Cubit<PreOrdersState> {
  final PreOrdersRepository _repository;

  PreOrdersCubit(this._repository) : super(const PreOrdersState());

  Future<void> loadPreOrders() async {
    emit(state.copyWith(status: PreOrdersViewStatus.loading));
    try {
      final orders = await _repository.getPreOrders();
      final batches = await _repository.getBatches();
      emit(
        state.copyWith(
          status: PreOrdersViewStatus.loaded,
          allOrders: orders,
          allBatches: batches,
          errorMessage: null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: PreOrdersViewStatus.error,
          errorMessage: 'فشل تحميل طلبات الحجز والشحنات: $e',
        ),
      );
    }
  }

  void setMode(String mode) {
    emit(state.copyWith(activeMode: mode));
  }

  void setTab(String tab) {
    emit(state.copyWith(selectedTab: tab));
  }

  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  Future<bool> createPreOrder(
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.createPreOrder(
        order,
        initialDepositPiasters: initialDepositPiasters,
        paymentMethod: paymentMethod,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل إنشاء طلب الحجز: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> addPayment(
    String preOrderId,
    int amountPiasters, {
    String paymentMethod = 'cash',
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.addPayment(
        preOrderId,
        amountPiasters,
        paymentMethod: paymentMethod,
        notes: notes,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل تسجيل الدفعة: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> markArrivedAtStore(String preOrderId) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.markArrivedAtStore(preOrderId);
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل تحديث حالة الحجز إلى وصل للمحل: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> deliverPreOrder(
    String preOrderId, {
    int finalPaymentPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.deliverPreOrder(
        preOrderId,
        finalPaymentPiasters: finalPaymentPiasters,
        paymentMethod: paymentMethod,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل إتمام تسليم الأوردر: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> forfeitDeposit(
    String preOrderId, {
    bool transferItemsToInventory = true,
    String? categoryId,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.forfeitDeposit(
        preOrderId,
        transferItemsToInventory: transferItemsToInventory,
        categoryId: categoryId,
      );
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل مصادرة العربون: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> cancelAndRefund(
    String preOrderId, {
    int refundAmountPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.cancelAndRefund(
        preOrderId,
        refundAmountPiasters: refundAmountPiasters,
        notes: notes,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل إلغاء الحجز ورد المبلغ: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> deletePreOrder(String preOrderId) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.deletePreOrder(preOrderId);
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(isSubmitting: false, errorMessage: 'فشل حذف الحجز: $e'),
      );
      return false;
    }
  }

  // ==========================================
  // --- عمليات الشحنات المجمعة (Batches) ---
  // ==========================================

  Future<bool> createBatch(
    PreOrderBatchEntity batch,
    List<PreOrderEntity> orders, {
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.createBatch(
        batch,
        orders,
        paymentMethod: paymentMethod,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل إنشاء الشحنة المجمعة: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> markBatchArrivedAtStore(String batchId) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.markBatchArrivedAtStore(batchId);
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل تحديث حالة الشحنة إلى وصلت للمحل: $e',
        ),
      );
      return false;
    }
  }

  Future<bool> deleteBatch(String batchId) async {
    emit(state.copyWith(isSubmitting: true));
    try {
      await _repository.deleteBatch(batchId);
      await loadPreOrders();
      emit(state.copyWith(isSubmitting: false));
      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'فشل حذف الشحنة المجمعة: $e',
        ),
      );
      return false;
    }
  }
}
