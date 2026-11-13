import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../data/datasources/inventory_local_data_source.dart';
import '../../domain/entities/goods_receipt_entity.dart';
import 'goods_receipt_state.dart';

@injectable
class GoodsReceiptCubit extends Cubit<GoodsReceiptState> {
  final InventoryLocalDataSource _dataSource;

  GoodsReceiptCubit(this._dataSource) : super(const GoodsReceiptState());

  Future<void> loadGoodsReceipts({String? status}) async {
    emit(state.copyWith(status: GoodsReceiptStatus.loading));
    try {
      final list = await _dataSource.getGoodsReceipts(status: status);
      emit(state.copyWith(
        status: GoodsReceiptStatus.loaded,
        receipts: list,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: GoodsReceiptStatus.error,
        errorMessage: 'تعذر تحميل بيانات الاستلامات المخزنية: $e',
      ));
    }
  }

  Future<GoodsReceiptEntity?> createGoodsReceipt({
    required List<GoodsReceiptDraftItem> items,
    required String cashierId,
    String? notes,
    DateTime? receivedAt,
  }) async {
    emit(state.copyWith(status: GoodsReceiptStatus.loading));
    try {
      final receipt = await _dataSource.createGoodsReceipt(
        items: items,
        cashierId: cashierId,
        notes: notes,
        receivedAt: receivedAt,
      );
      emit(state.copyWith(
        status: GoodsReceiptStatus.success,
        successMessage: 'تم حفظ شحنة الاستلام المخزني بنجاح وزيادة أرصدة المقاسات',
      ));
      return receipt;
    } catch (e) {
      emit(state.copyWith(
        status: GoodsReceiptStatus.error,
        errorMessage: 'فشل حفظ الشحنة: $e',
      ));
      return null;
    }
  }

  Future<bool> updateStatus({
    required String receiptId,
    required String newStatus,
    required String userId,
  }) async {
    try {
      await _dataSource.updateGoodsReceiptStatus(
        receiptId: receiptId,
        newStatus: newStatus,
        userId: userId,
      );
      await loadGoodsReceipts(status: 'pending');
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: GoodsReceiptStatus.error,
        errorMessage: 'فشل تحديث حالة الاستلام: $e',
      ));
      return false;
    }
  }
}

