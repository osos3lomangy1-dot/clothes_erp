import 'package:clothes_erp/features/pre_orders/domain/entities/pre_order_batch_entity.dart';
import 'package:clothes_erp/features/pre_orders/domain/entities/pre_order_entity.dart';
import 'package:clothes_erp/features/pre_orders/domain/entities/pre_order_item_entity.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('PreOrders Task 8.3 Batch & Shipping Split Tests', () {
    test('PreOrderEntity correctly includes allocated shipping in totals', () {
      final order = PreOrderEntity(
        id: 'order-batch-1',
        branchId: 'b-1',
        batchId: 'batch-101',
        orderNumber: 'PO-1003',
        customerName: 'نورا',
        customerPhone: '01234567890',
        totalPiasters: 60000, // 600 LE
        depositPiasters: 20000, // 200 LE
        allocatedShippingPiasters: 5000, // 50 LE shipping
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(order.batchId, equals('batch-101'));
      expect(order.allocatedShippingPiasters, equals(5000));
      // 600 LE + 50 LE shipping = 650 LE = 65000 piasters
      expect(order.totalWithShippingPiasters, equals(65000));
      // 650 LE - 200 LE deposit = 450 LE = 45000 piasters
      expect(order.remainingWithShippingPiasters, equals(45000));

      final map = order.toMap();
      expect(map['batch_id'], equals('batch-101'));
      expect(map['allocated_shipping_piasters'], equals(5000));

      final restored = PreOrderEntity.fromMap(map);
      expect(restored.batchId, equals('batch-101'));
      expect(restored.allocatedShippingPiasters, equals(5000));
      expect(restored.totalWithShippingPiasters, equals(65000));
      expect(restored.remainingWithShippingPiasters, equals(45000));
    });

    test('PreOrderBatchEntity aggregates pieces, cost, retail, and profit correctly', () {
      final item1 = PreOrderItemEntity(
        id: 'it-1',
        preOrderId: 'ord-1',
        productName: 'قميص',
        quantity: 3,
        costPricePiasters: 15000, // 150 LE each
        commissionPiasters: 3000, // 30 LE each
        unitPricePiasters: 18000, // 180 LE
        totalPricePiasters: 54000, // 540 LE
      );
      final order1 = PreOrderEntity(
        id: 'ord-1',
        branchId: 'b-1',
        batchId: 'batch-1',
        orderNumber: 'PO-1',
        customerName: 'عميل 1',
        customerPhone: '0100',
        totalPiasters: 54000,
        depositPiasters: 20000,
        allocatedShippingPiasters: 6000, // 60 LE
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [item1],
      );

      final item2 = PreOrderItemEntity(
        id: 'it-2',
        preOrderId: 'ord-2',
        productName: 'بنطلون',
        quantity: 2,
        costPricePiasters: 25000, // 250 LE each
        commissionPiasters: 5000, // 50 LE each
        unitPricePiasters: 30000, // 300 LE
        totalPricePiasters: 60000, // 600 LE
      );
      final order2 = PreOrderEntity(
        id: 'ord-2',
        branchId: 'b-1',
        batchId: 'batch-1',
        orderNumber: 'PO-2',
        customerName: 'عميل 2',
        customerPhone: '0101',
        totalPiasters: 60000,
        depositPiasters: 30000,
        allocatedShippingPiasters: 4000, // 40 LE
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [item2],
      );

      final batch = PreOrderBatchEntity(
        id: 'batch-1',
        branchId: 'b-1',
        batchNumber: 'شحنة 21 نوفمبر',
        agentName: 'شركة الشحن الدولي',
        trackingNumber: 'TRK-9900',
        totalShippingPiasters: 10000, // 100 LE
        shippingSplitMethod: ShippingSplitMethods.perItem,
        status: PreOrderStatuses.pendingProcessing,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        orders: [order1, order2],
      );

      expect(batch.totalOrdersCount, equals(2));
      // Pieces: 3 + 2 = 5 pieces
      expect(batch.totalPiecesCount, equals(5));
      // Total retail: 540 + 600 = 1140 LE = 114000 piasters
      expect(batch.totalRetailPiasters, equals(114000));
      // Total agent cost: (3 * 150) + (2 * 250) = 450 + 500 = 950 LE = 95000 piasters
      expect(batch.totalCostPiasters, equals(95000));
      // Base profit: 1140 - 950 = 190 LE = 19000 piasters (when customers pay shipping)
      expect(batch.totalProfitPiasters, equals(19000));
      // Total deposits: 200 + 300 = 500 LE = 50000 piasters
      expect(batch.totalDepositsPiasters, equals(50000));
      // Total allocated shipping: 60 + 40 = 100 LE = 10000 piasters
      expect(batch.totalAllocatedShippingPiasters, equals(10000));
      // Total remaining with shipping: (540+60-200) + (600+40-300) = 400 + 340 = 740 LE = 74000 piasters
      expect(batch.totalRemainingWithShippingPiasters, equals(74000));

      // Test Free Shipping: merchant absorbs the 100 LE shipping
      final freeShippingBatch = batch.copyWith(
        shippingSplitMethod: ShippingSplitMethods.freeShipping,
      );
      // Profit: 190 LE base profit - 100 LE shipping = 90 LE = 9000 piasters
      expect(freeShippingBatch.totalProfitPiasters, equals(9000));
    });

    test('PreOrderBatchEntity toMap and fromMap serialization', () {
      final now = DateTime.now();
      final batch = PreOrderBatchEntity(
        id: 'batch-99',
        branchId: 'b-main',
        batchNumber: 'شحنة تركيا دفعة 3',
        agentName: 'علي التركي',
        trackingNumber: 'TR-TURK-1234',
        totalShippingPiasters: 25000,
        shippingSplitMethod: ShippingSplitMethods.equalPerCustomer,
        status: PreOrderStatuses.arrivedAtStore,
        createdAt: now,
        updatedAt: now,
        arrivedAt: now,
      );

      final map = batch.toMap();
      expect(map['batch_number'], equals('شحنة تركيا دفعة 3'));
      expect(map['agent_name'], equals('علي التركي'));
      expect(map['tracking_number'], equals('TR-TURK-1234'));
      expect(map['total_shipping_piasters'], equals(25000));
      expect(map['shipping_split_method'], equals('equalPerCustomer'));
      expect(map['status'], equals(PreOrderStatuses.arrivedAtStore));

      final restored = PreOrderBatchEntity.fromMap(map);
      expect(restored.id, equals('batch-99'));
      expect(restored.batchNumber, equals('شحنة تركيا دفعة 3'));
      expect(restored.agentName, equals('علي التركي'));
      expect(restored.trackingNumber, equals('TR-TURK-1234'));
      expect(restored.totalShippingPiasters, equals(25000));
      expect(restored.shippingSplitMethod, equals(ShippingSplitMethods.equalPerCustomer));
      expect(restored.status, equals(PreOrderStatuses.arrivedAtStore));
    });
  });

  group('PreOrders Task 8.5.2 Shein Real-World Scenarios & All-Inclusive Pricing Tests', () {
    test('PreOrderItemEntity status effects: cancelled and outOfStock items have 0 cost to supplier', () {
      final activeItem = PreOrderItemEntity(
        id: 'it-1',
        preOrderId: 'ord-1',
        productName: 'فستان صيفي',
        quantity: 2,
        costPricePiasters: 20000,
        unitPricePiasters: 25000,
        totalPricePiasters: 50000,
        status: 'active',
      );

      final cancelledItem = PreOrderItemEntity(
        id: 'it-2',
        preOrderId: 'ord-1',
        productName: 'تنورة ملغاة قبل الطلب',
        quantity: 1,
        costPricePiasters: 15000,
        unitPricePiasters: 20000,
        totalPricePiasters: 20000,
        status: 'cancelled',
      );

      final outOfStockItem = PreOrderItemEntity(
        id: 'it-3',
        preOrderId: 'ord-1',
        productName: 'بلوزة نفدت من شي إن',
        quantity: 1,
        costPricePiasters: 10000,
        unitPricePiasters: 14000,
        totalPricePiasters: 14000,
        status: 'outOfStock',
      );

      final damagedItem = PreOrderItemEntity(
        id: 'it-4',
        preOrderId: 'ord-1',
        productName: 'شال تالف/أوتلت',
        quantity: 1,
        costPricePiasters: 5000,
        unitPricePiasters: 8000,
        totalPricePiasters: 8000,
        status: 'damaged',
      );

      expect(activeItem.totalCostPiasters, equals(40000));
      expect(activeItem.totalProfitPiasters, equals(10000));

      // Cancelled before order: not owed to supplier
      expect(cancelledItem.totalCostPiasters, equals(0));
      expect(cancelledItem.totalProfitPiasters, equals(0));

      // Out of stock by Shein: not owed to supplier
      expect(outOfStockItem.totalCostPiasters, equals(0));
      expect(outOfStockItem.totalProfitPiasters, equals(0));

      // Damaged/Clearance item received: cost was paid, but routed to outlet
      expect(damagedItem.totalCostPiasters, equals(5000));
    });

    test('PreOrderEntity handles emergencyIncreasePiasters correctly in customer remaining balance', () {
      final item = PreOrderItemEntity(
        id: 'it-1',
        preOrderId: 'ord-1',
        productName: 'صنف شي إن',
        quantity: 1,
        costPricePiasters: 30000,
        unitPricePiasters: 40000,
        totalPricePiasters: 40000,
      );

      final orderWithoutSurcharge = PreOrderEntity(
        id: 'ord-1',
        branchId: 'b-1',
        orderNumber: 'PO-2001',
        customerName: 'مريم',
        customerPhone: '01011112222',
        totalPiasters: 40000, // 400 LE
        depositPiasters: 10000, // 100 LE
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [item],
      );

      // Remaining = 400 - 100 = 300 LE = 30000 piasters
      expect(orderWithoutSurcharge.remainingPiasters, equals(30000));

      // Now emergency exchange rate surcharge applied to customer (+ 50 LE = 5000 piasters)
      final orderWithSurcharge = orderWithoutSurcharge.copyWith(
        emergencyIncreasePiasters: 5000,
      );

      // Total due = 400 + 50 = 450 LE = 45000 piasters
      expect(orderWithSurcharge.totalWithShippingPiasters, equals(45000));
      // Remaining = 450 - 100 = 350 LE = 35000 piasters
      expect(orderWithSurcharge.remainingPiasters, equals(35000));
      expect(orderWithSurcharge.remainingWithShippingPiasters, equals(35000));
    });

    test('PreOrderBatchEntity calculates merchant profit correctly when merchant absorbs emergency increase vs when customers pay', () {
      final item = PreOrderItemEntity(
        id: 'it-1',
        preOrderId: 'ord-1',
        productName: 'فستان',
        quantity: 10,
        costPricePiasters: 10000, // 100 LE each -> 1000 LE total cost
        unitPricePiasters: 15000, // 150 LE each -> 1500 LE total retail
        totalPricePiasters: 150000,
      );

      final order = PreOrderEntity(
        id: 'ord-1',
        branchId: 'b-1',
        orderNumber: 'PO-3001',
        customerName: 'سارة',
        customerPhone: '010',
        totalPiasters: 150000, // 1500 LE
        depositPiasters: 50000, // 500 LE
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: [item],
      );

      // Scenario: Batch with 200 LE general shipping paid by merchant, and 100 LE emergency increase
      final batch = PreOrderBatchEntity(
        id: 'batch-shein',
        branchId: 'b-1',
        batchNumber: 'شحنة شي إن 25 نوفمبر',
        totalShippingPiasters: 20000, // 200 LE shipping overhead
        emergencyIncreasePiasters: 10000, // 100 LE customs/currency surge
        emergencyIncreaseHandledBy: 'merchant', // Merchant absorbs
        shippingSplitMethod: ShippingSplitMethods.freeShipping,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        orders: [order],
      );

      // Retail: 1500 LE, Cost: 1000 LE -> Base Profit: 500 LE
      // Deduct General Shipping (200 LE) -> 300 LE
      // Deduct Merchant absorbed emergency increase (100 LE) -> Net Profit: 200 LE = 20000 piasters
      expect(batch.totalProfitPiasters, equals(20000));

      // If emergency surge was passed to customers instead:
      final batchPassedToCustomers = batch.copyWith(
        emergencyIncreaseHandledBy: 'customers',
      );
      // Net profit = 500 - 200 = 300 LE = 30000 piasters
      expect(batchPassedToCustomers.totalProfitPiasters, equals(30000));
    });

    test('PreOrderEntity handles sourcePlatform and displaySourcePlatform correctly (Task 8.5.3)', () {
      final orderWithPlatform = PreOrderEntity(
        id: 'order-plat-1',
        branchId: 'b-1',
        orderNumber: 'PO-3001',
        customerName: 'مريم محمود',
        customerPhone: '01012345678',
        sourcePlatform: PreOrderPlatforms.trendyol,
        totalPiasters: 50000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(orderWithPlatform.displaySourcePlatform, equals('ترينديول'));
      expect(orderWithPlatform.toMap()['source_platform'], equals('ترينديول'));

      final fromMapOrder = PreOrderEntity.fromMap(orderWithPlatform.toMap());
      expect(fromMapOrder.sourcePlatform, equals('ترينديول'));
      expect(fromMapOrder.displaySourcePlatform, equals('ترينديول'));

      // If order.sourcePlatform is null, fallback to first item's platform or 'طلب خاص'
      final itemWithPlatform = PreOrderItemEntity(
        id: 'it-plat-1',
        preOrderId: 'order-plat-2',
        productName: 'فستان زارا',
        unitPricePiasters: 80000,
        totalPricePiasters: 80000,
        sourcePlatform: PreOrderPlatforms.zara,
      );
      final orderFallback = PreOrderEntity(
        id: 'order-plat-2',
        branchId: 'b-1',
        orderNumber: 'PO-3002',
        customerName: 'هدى',
        customerPhone: '01111111111',
        totalPiasters: 80000,
        items: [itemWithPlatform],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(orderFallback.displaySourcePlatform, equals('زارا'));

      final orderNoPlatform = PreOrderEntity(
        id: 'order-plat-3',
        branchId: 'b-1',
        orderNumber: 'PO-3003',
        customerName: 'نورا',
        customerPhone: '01222222222',
        totalPiasters: 30000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(orderNoPlatform.displaySourcePlatform, equals('طلب خاص'));
    });
  });
}


