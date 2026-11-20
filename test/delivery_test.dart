import 'package:clothes_erp/features/delivery/domain/entities/courier_settlement_summary.dart';
import 'package:clothes_erp/features/delivery/domain/entities/delivery_courier_entity.dart';
import 'package:clothes_erp/features/delivery/domain/entities/delivery_order_entity.dart';
import 'package:clothes_erp/features/delivery/presentation/cubits/delivery_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeliveryOrderEntity Tests', () {
    test('Calculates financial getters correctly in EGP', () {
      final order = DeliveryOrderEntity(
        id: 'ord-1',
        branchId: 'branch-1',
        orderRef: '#DEL-101',
        customerName: 'أحمد محمود',
        customerPhone: '01012345678',
        deliveryAddress: 'شارع الجمهورية - عمارة 5',
        deliveryFeePiasters: 2500, // 25.00 EGP
        orderTotalPiasters: 17550, // 175.50 EGP
        createdAt: DateTime(2026, 11, 20, 10, 0),
        updatedAt: DateTime(2026, 11, 20, 10, 0),
      );

      expect(order.deliveryFee, 25.0);
      expect(order.orderTotal, 175.50);
      expect(order.grandTotal, 200.50);
      expect(order.grandTotalPiasters, 20050);
    });

    test('Status flags reflect state correctly', () {
      final prep = DeliveryOrderEntity(
        id: '1',
        branchId: 'b',
        orderRef: '#1',
        customerName: 'علي',
        customerPhone: '010',
        deliveryAddress: 'القاهرة',
        deliveryFeePiasters: 2000,
        orderTotalPiasters: 10000,
        status: 'preparing',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(prep.isPreparing, true);
      expect(prep.isOutForDelivery, false);
      expect(prep.isDelivered, false);

      final out = prep.copyWith(status: 'out_for_delivery');
      expect(out.isPreparing, false);
      expect(out.isOutForDelivery, true);

      final delivered = prep.copyWith(status: 'delivered');
      expect(delivered.isDelivered, true);
    });
  });

  group('CourierSettlementSummary Tests', () {
    test('Computes aggregate totals correctly for courier payout', () {
      final order1 = DeliveryOrderEntity(
        id: 'o-1',
        branchId: 'b1',
        orderRef: '#DEL-1',
        customerName: 'عميل 1',
        customerPhone: '0111',
        deliveryAddress: 'عنوان 1',
        deliveryFeePiasters: 2000, // 20 LE
        orderTotalPiasters: 10000, // 100 LE -> Total 120 LE
        status: 'delivered',
        paymentMethod: 'cod',
        courierSettled: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final order2 = DeliveryOrderEntity(
        id: 'o-2',
        branchId: 'b1',
        orderRef: '#DEL-2',
        customerName: 'عميل 2',
        customerPhone: '0122',
        deliveryAddress: 'عنوان 2',
        deliveryFeePiasters: 3000, // 30 LE
        orderTotalPiasters: 20000, // 200 LE -> Total 230 LE
        status: 'delivered',
        paymentMethod: 'cod',
        courierSettled: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final summary = CourierSettlementSummary(
        courierId: 'courier-1',
        courierName: 'كابتن محمود',
        courierPhone: '01000000001',
        totalAssignedOrders: 2,
        deliveredOrdersCount: 2,
        pendingOrdersCount: 0,
        returnedOrdersCount: 0,
        totalCashToCollectPiasters:
            35000, // 120 + 230 = 350 LE (35000 piasters)
        totalDeliveryFeesPiasters: 5000, // 20 + 30 = 50 LE (5000 piasters)
        unsettledOrders: [order1, order2],
      );

      expect(summary.totalAssignedOrders, 2);
      expect(summary.totalCashToCollectPiasters, 35000);
      expect(summary.totalDeliveryFeesPiasters, 5000);
      expect(summary.totalCashToCollect, 350.0);
      expect(summary.totalDeliveryFees, 50.0);
      expect(summary.netCashHandoverRequired, 300.0); // 350 - 50 = 300 LE
    });
  });

  group('DeliveryState Computed Metrics Tests', () {
    test('Calculates metrics from orders stream correctly', () {
      final o1 = DeliveryOrderEntity(
        id: '1',
        branchId: 'b',
        orderRef: '1',
        customerName: 'س',
        customerPhone: '01',
        deliveryAddress: 'ع',
        deliveryFeePiasters: 1000,
        orderTotalPiasters: 9000, // grand 10000
        status: 'preparing',
        paymentMethod: 'cod',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final o2 = DeliveryOrderEntity(
        id: '2',
        branchId: 'b',
        orderRef: '2',
        customerName: 'ص',
        customerPhone: '02',
        deliveryAddress: 'ع',
        deliveryFeePiasters: 2000,
        orderTotalPiasters: 18000, // grand 20000
        status: 'out_for_delivery',
        paymentMethod: 'cod',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final o3 = DeliveryOrderEntity(
        id: '3',
        branchId: 'b',
        orderRef: '3',
        customerName: 'ع',
        customerPhone: '03',
        deliveryAddress: 'ع',
        deliveryFeePiasters: 1500,
        orderTotalPiasters: 8500, // grand 10000
        status: 'delivered',
        paymentMethod: 'cod',
        courierSettled: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = DeliveryState(
        orders: [o1, o2, o3],
        couriers: [
          DeliveryCourierEntity(
            id: 'c1',
            branchId: 'b',
            name: 'محمود',
            phone: '010',
            createdAt: DateTime.now(),
          ),
        ],
      );

      expect(state.preparingCount, 1);
      expect(state.outForDeliveryCount, 1);
      expect(state.deliveredCount, 1);
      expect(state.activeCashInTransitPiasters, 20000);
      expect(state.deliveredUnsettledCashPiasters, 10000);
      expect(state.activeCashInTransit, 200.0);
      expect(state.deliveredUnsettledCash, 100.0);
    });
  });
}
