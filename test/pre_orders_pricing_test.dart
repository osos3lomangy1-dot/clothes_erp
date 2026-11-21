import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/features/pre_orders/domain/entities/pre_order_entity.dart';
import 'package:clothes_erp/features/pre_orders/domain/entities/pre_order_item_entity.dart';

void main() {
  group('PreOrders Task 8.2 Entity & Pricing Tests', () {
    test('PreOrderItemEntity calculates cost and profit correctly', () {
      final item = PreOrderItemEntity(
        id: 'item-1',
        preOrderId: 'order-1',
        productName: 'فستان مخملي',
        quantity: 2,
        costPricePiasters: 40000, // 400 LE cost
        commissionPiasters: 5000, // 50 LE commission
        unitPricePiasters: 45000, // 450 LE retail
        totalPricePiasters: 90000, // 900 LE total retail
      );

      expect(item.totalCostPiasters, equals(80000)); // 2 * 400 = 800 LE
      expect(item.totalProfitPiasters, equals(10000)); // 2 * 50 = 100 LE
    });

    test('PreOrderEntity aggregates agent cost and profit correctly', () {
      final item1 = PreOrderItemEntity(
        id: 'item-1',
        preOrderId: 'order-1',
        productName: 'فستان',
        quantity: 1,
        costPricePiasters: 30000,
        commissionPiasters: 5000,
        unitPricePiasters: 35000,
        totalPricePiasters: 35000,
      );

      final item2 = PreOrderItemEntity(
        id: 'item-2',
        preOrderId: 'order-1',
        productName: 'حذاء',
        quantity: 2,
        costPricePiasters: 20000,
        commissionPiasters: 4000,
        unitPricePiasters: 24000,
        totalPricePiasters: 48000,
      );

      final order = PreOrderEntity(
        id: 'order-1',
        branchId: 'b-1',
        orderNumber: 'PO-1001',
        customerName: 'سارة',
        customerPhone: '01012345678',
        agentName: 'كابتن رامي',
        trackingNumber: 'SH-98412',
        totalPiasters: 83000, // 350 + 480 = 830 LE
        depositPiasters: 30000, // 300 LE
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [item1, item2],
      );

      expect(order.agentName, equals('كابتن رامي'));
      expect(order.trackingNumber, equals('SH-98412'));
      // Total cost = 300 + (2 * 200) = 700 LE = 70000 piasters
      expect(order.totalCostPiasters, equals(70000));
      // Total profit = 830 - 700 = 130 LE = 13000 piasters
      expect(order.totalProfitPiasters, equals(13000));
      // Remaining = 830 - 300 = 530 LE = 53000 piasters
      expect(order.remainingPiasters, equals(53000));
    });

    test('PreOrderEntity serialization preserves agentName and trackingNumber', () {
      final order = PreOrderEntity(
        id: 'order-2',
        branchId: 'b-1',
        orderNumber: 'PO-1002',
        customerName: 'أحمد',
        customerPhone: '01112223334',
        agentName: 'شركة الشحن السريع',
        trackingNumber: 'TRK-554433',
        totalPiasters: 50000,
        depositPiasters: 20000,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final map = order.toMap();
      expect(map['agent_name'], equals('شركة الشحن السريع'));
      expect(map['tracking_number'], equals('TRK-554433'));

      final restored = PreOrderEntity.fromMap(map);
      expect(restored.agentName, equals('شركة الشحن السريع'));
      expect(restored.trackingNumber, equals('TRK-554433'));
    });
  });
}
