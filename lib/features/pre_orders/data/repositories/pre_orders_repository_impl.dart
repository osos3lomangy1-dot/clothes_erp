import 'package:injectable/injectable.dart';

import '../../domain/entities/pre_order_entity.dart';
import '../../domain/repositories/pre_orders_repository.dart';
import '../datasources/pre_orders_local_data_source.dart';

@LazySingleton(as: PreOrdersRepository)
class PreOrdersRepositoryImpl implements PreOrdersRepository {
  final PreOrdersLocalDataSource _dataSource;

  PreOrdersRepositoryImpl(this._dataSource);

  @override
  Future<void> ensureTablesExist() => _dataSource.ensureTablesExist();

  @override
  Future<List<PreOrderEntity>> getPreOrders({
    String? status,
    String? searchQuery,
  }) {
    return _dataSource.getPreOrders(
      status: status,
      searchQuery: searchQuery,
    );
  }

  @override
  Future<PreOrderEntity?> getPreOrderById(String id) {
    return _dataSource.getPreOrderById(id);
  }

  @override
  Future<PreOrderEntity> createPreOrder(
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) {
    return _dataSource.insertPreOrder(
      order,
      initialDepositPiasters: initialDepositPiasters,
      paymentMethod: paymentMethod,
      shiftId: shiftId,
      cashierId: cashierId,
    );
  }

  @override
  Future<void> addPayment(
    String preOrderId,
    int amountPiasters, {
    String paymentMethod = 'cash',
    String? notes,
    String? shiftId,
    String? cashierId,
  }) {
    return _dataSource.addPayment(
      preOrderId,
      amountPiasters,
      paymentMethod: paymentMethod,
      notes: notes,
      shiftId: shiftId,
      cashierId: cashierId,
    );
  }

  @override
  Future<void> markArrivedAtStore(String preOrderId) {
    return _dataSource.markArrivedAtStore(preOrderId);
  }

  @override
  Future<void> deliverPreOrder(
    String preOrderId, {
    int finalPaymentPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) {
    return _dataSource.deliverPreOrder(
      preOrderId,
      finalPaymentPiasters: finalPaymentPiasters,
      paymentMethod: paymentMethod,
      shiftId: shiftId,
      cashierId: cashierId,
    );
  }

  @override
  Future<void> forfeitDeposit(
    String preOrderId, {
    bool transferItemsToInventory = true,
    String? categoryId,
  }) {
    return _dataSource.forfeitDeposit(
      preOrderId,
      transferItemsToInventory: transferItemsToInventory,
      categoryId: categoryId,
    );
  }

  @override
  Future<void> cancelAndRefund(
    String preOrderId, {
    int refundAmountPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  }) {
    return _dataSource.cancelAndRefund(
      preOrderId,
      refundAmountPiasters: refundAmountPiasters,
      notes: notes,
      shiftId: shiftId,
      cashierId: cashierId,
    );
  }

  @override
  Future<void> deletePreOrder(String preOrderId) {
    return _dataSource.deletePreOrder(preOrderId);
  }
}
