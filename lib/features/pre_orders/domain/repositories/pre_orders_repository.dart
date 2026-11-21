import '../entities/pre_order_batch_entity.dart';
import '../entities/pre_order_entity.dart';
import '../entities/pre_order_item_entity.dart';

abstract class PreOrdersRepository {
  Future<void> ensureTablesExist();

  // --- الأوردرات الفردية ---
  Future<List<PreOrderEntity>> getPreOrders({
    String? status,
    String? searchQuery,
    String? batchId,
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

  // --- الشحنات المجمعة (Batches) ---
  Future<List<PreOrderBatchEntity>> getBatches({
    String? status,
    String? searchQuery,
  });

  Future<PreOrderBatchEntity?> getBatchById(String id);

  Future<PreOrderBatchEntity> createBatch(
    PreOrderBatchEntity batch,
    List<PreOrderEntity> orders, {
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });

  Future<void> markBatchArrivedAtStore(String batchId);

  Future<void> deleteBatch(String batchId);

  // --- سيناريوهات الشحنات والبنود الطارئة (Task 8.5.2) ---
  Future<void> attachOrderToBatch(String batchId, String orderId);

  Future<void> applyBatchEmergencyIncrease(
    String batchId,
    int increasePiasters,
    String handledBy,
  );

  Future<void> cancelOrderItem(
    String itemId, {
    required String refundOption,
    int refundPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  });

  Future<void> markOrderItemOutOfStock(
    String itemId, {
    required String refundOption,
    int refundPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  });

  Future<void> markOrderItemDamaged(
    String itemId, {
    bool refundDeposit = true,
    int refundPiasters = 0,
    bool transferToClearance = true,
    String? categoryId,
    String? notes,
    String? shiftId,
    String? cashierId,
  });

  Future<PreOrderEntity> addCustomerToBatch(
    String batchId,
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });

  // --- إدارة وتعديل الأصناف (Task 8.5.4) ---
  Future<void> updateOrderItem(PreOrderItemEntity item);
  Future<void> deleteOrderItem(String itemId);
  Future<PreOrderItemEntity> addOrderItem(
    String orderId,
    PreOrderItemEntity item,
  );
}
