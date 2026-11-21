import '../entities/pre_order_entity.dart';

abstract class PreOrdersRepository {
  Future<void> ensureTablesExist();

  Future<List<PreOrderEntity>> getPreOrders({
    String? status,
    String? searchQuery,
  });

  Future<PreOrderEntity?> getPreOrderById(String id);

  Future<PreOrderEntity> createPreOrder(
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });

  Future<void> addPayment(
    String preOrderId,
    int amountPiasters, {
    String paymentMethod = 'cash',
    String? notes,
    String? shiftId,
    String? cashierId,
  });

  Future<void> markArrivedAtStore(String preOrderId);

  Future<void> deliverPreOrder(
    String preOrderId, {
    int finalPaymentPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });

  Future<void> forfeitDeposit(
    String preOrderId, {
    bool transferItemsToInventory = true,
    String? categoryId,
  });

  Future<void> cancelAndRefund(
    String preOrderId, {
    int refundAmountPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  });

  Future<void> deletePreOrder(String preOrderId);
}
