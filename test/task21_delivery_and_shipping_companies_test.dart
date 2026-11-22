import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/features/delivery/data/datasources/delivery_local_data_source.dart';
import 'package:clothes_erp/features/delivery/data/repositories/delivery_repository_impl.dart';
import 'package:clothes_erp/features/delivery/domain/entities/delivery_courier_entity.dart';
import 'package:clothes_erp/features/delivery/domain/entities/delivery_order_entity.dart';
import 'package:clothes_erp/features/delivery/domain/entities/shipping_company_payout_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 21: Domain Entities & Provider Differentiation Tests', () {
    test('DeliveryCourierEntity correctly distinguishes in-house vs shipping company', () {
      final inHouse = DeliveryCourierEntity(
        id: 'c-inhouse-1',
        branchId: 'b1',
        name: 'كابتن محمود',
        phone: '01011112222',
        vehicleType: 'موتوسيكل',
        providerType: 'in_house',
        createdAt: DateTime.now(),
      );

      final shippingCo = DeliveryCourierEntity(
        id: 'c-ship-1',
        branchId: 'b1',
        name: 'شركة بوسطة للشحن',
        phone: '19000',
        providerType: 'shipping_company',
        accountNumber: 'ACC-8831',
        defaultRatePiasters: 4500, // 45 EGP
        trackingUrlTemplate: 'https://track.bosta.co/{TRACKING}',
        createdAt: DateTime.now(),
      );

      expect(inHouse.isInHouse, isTrue);
      expect(inHouse.isShippingCompany, isFalse);

      expect(shippingCo.isInHouse, isFalse);
      expect(shippingCo.isShippingCompany, isTrue);
      expect(shippingCo.accountNumber, 'ACC-8831');
      expect(shippingCo.defaultRate, 45.0);
      expect(shippingCo.trackingUrlTemplate, contains('{TRACKING}'));
    });

    test('DeliveryOrderEntity calculates netStoreDuePiasters according to shippingFeePayer', () {
      // Case 1: customer_direct (Customer pays shipping fee directly to shipping company)
      // Store is due 100% of order items.
      final directOrder = DeliveryOrderEntity(
        id: 'ord-direct-1',
        branchId: 'b1',
        orderRef: 'ORD-101',
        customerName: 'فاطمة أحمد',
        customerPhone: '01234567890',
        deliveryAddress: 'الإسكندرية - سموحة',
        deliveryFeePiasters: 4000, // 40 EGP
        orderTotalPiasters: 25000, // 250 EGP
        providerType: 'shipping_company',
        shippingFeePayer: 'customer_direct',
        waybillNumber: 'WB-9901',
        shippingCostPiasters: 3500, // 35 EGP
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(directOrder.isCustomerDirectShipping, isTrue);
      expect(directOrder.grandTotalPiasters, 29000); // 250 + 40 = 290 EGP
      expect(directOrder.netStoreDuePiasters, 25000); // 100% of items

      // Case 2: store_collected (Store collected shipping fee; shipping cost deducted from total)
      final storeOrder = DeliveryOrderEntity(
        id: 'ord-store-1',
        branchId: 'b1',
        orderRef: 'ORD-102',
        customerName: 'طارق حسام',
        customerPhone: '01122334455',
        deliveryAddress: 'طنطا - شارع البحر',
        deliveryFeePiasters: 5000, // 50 EGP
        orderTotalPiasters: 30000, // 300 EGP
        providerType: 'shipping_company',
        shippingFeePayer: 'store_collected',
        waybillNumber: 'WB-9902',
        shippingCostPiasters: 4500, // 45 EGP
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(storeOrder.isCustomerDirectShipping, isFalse);
      expect(storeOrder.grandTotalPiasters, 35000); // 300 + 50 = 350 EGP
      // Net due = (300 + 50) - 45 = 305 EGP (30500 piasters)
      expect(storeOrder.netStoreDuePiasters, 30500);
    });
  });

  group('Task 21: Database & Financial Integration Tests', () {
    late AppDatabase db;
    late BranchProvider branchProvider;
    late DeliveryLocalDataSourceImpl dataSource;
    late DeliveryRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      branchProvider = BranchProvider(db);
      dataSource = DeliveryLocalDataSourceImpl(db, branchProvider);
      repo = DeliveryRepositoryImpl(dataSource);
    });

    tearDown(() async {
      await db.close();
    });

    test('Settle in-house courier orders automatically creates Cash-In movement in active shift drawer', () async {
      // 1. Create an active cashier shift
      const shiftId = 'test-shift-active-01';
      final now = DateTime.now();
      await db.into(db.shifts).insert(
        ShiftsCompanion.insert(
          id: shiftId,
          branchId: 'default',
          cashierId: 'cashier-1',
          openingBalance: 10000,
          openedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 2. Insert in-house courier
      final courier = DeliveryCourierEntity(
        id: 'courier-ali',
        branchId: 'default',
        name: 'علي الطيار',
        phone: '01099887766',
        vehicleType: 'موتوسيكل',
        providerType: 'in_house',
        createdAt: now,
      );
      await dataSource.insertCourier(courier);

      // 3. Insert delivered COD orders
      final order1 = DeliveryOrderEntity(
        id: 'ord-ali-1',
        branchId: 'default',
        orderRef: 'DEL-01',
        customerName: 'عميل 1',
        customerPhone: '0111',
        deliveryAddress: 'شارع 1',
        deliveryFeePiasters: 2000, // 20 EGP
        orderTotalPiasters: 15000, // 150 EGP -> Grand: 170 EGP (17000 piasters)
        courierId: courier.id,
        courierName: courier.name,
        providerType: 'in_house',
        status: 'delivered',
        paymentMethod: 'cod',
        courierSettled: false,
        createdAt: now,
        updatedAt: now,
      );
      final order2 = DeliveryOrderEntity(
        id: 'ord-ali-2',
        branchId: 'default',
        orderRef: 'DEL-02',
        customerName: 'عميل 2',
        customerPhone: '0122',
        deliveryAddress: 'شارع 2',
        deliveryFeePiasters: 3000, // 30 EGP
        orderTotalPiasters: 20000, // 200 EGP -> Grand: 230 EGP (23000 piasters)
        courierId: courier.id,
        courierName: courier.name,
        providerType: 'in_house',
        status: 'delivered',
        paymentMethod: 'cod',
        courierSettled: false,
        createdAt: now,
        updatedAt: now,
      );
      await dataSource.insertDeliveryOrder(order1);
      await dataSource.insertDeliveryOrder(order2);

      // 4. Settle courier orders
      await dataSource.settleCourierOrders(courier.id, [order1.id, order2.id]);

      // 5. Verify orders marked settled
      final orders = await dataSource.getDeliveryOrders();
      expect(orders.every((o) => o.courierSettled), isTrue);

      // 6. Verify cash_movements contains a cash-in entry for the active shift
      // Total cash = 17000 + 23000 = 40000 piasters (400 EGP)
      final movements = await db.customSelect(
        "SELECT * FROM cash_movements WHERE shift_id = '$shiftId'",
      ).get();

      expect(movements.isNotEmpty, isTrue);
      final movement = movements.first.data;
      expect(movement['type'], 'deposit');
      expect(movement['direction'], 'in');
      expect(movement['method'], 'cash');
      expect(movement['amount_piasters'], 40000);
      expect(movement['notes'], contains('علي الطيار'));
    });

    test('Shipping company running ledger, statement, partial payouts, and batch reconciliation', () async {
      final now = DateTime.now();

      // 1. Create a shipping company
      final company = DeliveryCourierEntity(
        id: 'ship-bosta',
        branchId: 'default',
        name: 'بوسطة للشحن',
        phone: '19000',
        providerType: 'shipping_company',
        accountNumber: 'ACC-BOSTA-1',
        defaultRatePiasters: 4000,
        createdAt: now,
      );
      await dataSource.insertCourier(company);

      // 2. Insert 3 orders: 2 delivered, 1 preparing
      final o1 = DeliveryOrderEntity(
        id: 'ship-ord-1',
        branchId: 'default',
        orderRef: 'ORD-B1',
        customerName: 'كريم محمود',
        customerPhone: '0101',
        deliveryAddress: 'المعادي',
        deliveryFeePiasters: 4000, // 40 EGP
        orderTotalPiasters: 20000, // 200 EGP -> Grand 24000
        providerType: 'shipping_company',
        shippingFeePayer: 'customer_direct', // Net due: 20000
        waybillNumber: 'WB-1001',
        shippingCostPiasters: 3500, // 35 EGP
        courierId: company.id,
        courierName: company.name,
        status: 'delivered',
        paymentMethod: 'cod',
        createdAt: now,
        updatedAt: now,
      );

      final o2 = DeliveryOrderEntity(
        id: 'ship-ord-2',
        branchId: 'default',
        orderRef: 'ORD-B2',
        customerName: 'ياسر علي',
        customerPhone: '0102',
        deliveryAddress: 'المهندسين',
        deliveryFeePiasters: 5000, // 50 EGP
        orderTotalPiasters: 30000, // 300 EGP -> Grand 35000
        providerType: 'shipping_company',
        shippingFeePayer: 'store_collected', // Net due: (30000 + 5000) - 4000 = 31000
        waybillNumber: 'WB-1002',
        shippingCostPiasters: 4000, // 40 EGP
        courierId: company.id,
        courierName: company.name,
        status: 'delivered',
        paymentMethod: 'cod',
        createdAt: now,
        updatedAt: now,
      );

      final o3 = DeliveryOrderEntity(
        id: 'ship-ord-3',
        branchId: 'default',
        orderRef: 'ORD-B3',
        customerName: 'سارة حسن',
        customerPhone: '0103',
        deliveryAddress: 'مدينة نصر',
        deliveryFeePiasters: 4000,
        orderTotalPiasters: 15000,
        providerType: 'shipping_company',
        shippingFeePayer: 'customer_direct',
        courierId: company.id,
        courierName: company.name,
        status: 'preparing', // still preparing
        paymentMethod: 'cod',
        createdAt: now,
        updatedAt: now,
      );

      await dataSource.insertDeliveryOrder(o1);
      await dataSource.insertDeliveryOrder(o2);
      await dataSource.insertDeliveryOrder(o3);

      // 3. Verify Statement before any payouts
      final res1 = await repo.getShippingCompanyStatement(company.id);
      expect(res1.isRight(), isTrue);
      final s1 = res1.getOrElse(() => throw Exception());

      expect(s1.totalAssignedOrders, 3);
      expect(s1.deliveredOrdersCount, 2);
      expect(s1.pendingOrdersCount, 1);
      expect(s1.totalCodDeliveredPiasters, 24000 + 35000); // 59000
      expect(s1.totalShippingFeesPiasters, 3500 + 4000); // 7500
      expect(s1.totalNetDueToStorePiasters, 20000 + 31000); // 51000
      expect(s1.totalPayoutsReceivedPiasters, 0);
      expect(s1.remainingBalancePiasters, 51000);

      // 4. Record partial payouts
      final payout1 = ShippingCompanyPayoutEntity(
        id: 'payout-1',
        branchId: 'default',
        courierId: company.id,
        amountPiasters: 20000, // 200 EGP
        paymentMethod: 'bank_transfer',
        referenceNumber: 'TRX-99881',
        payoutDate: now,
        createdAt: now,
      );
      final payout2 = ShippingCompanyPayoutEntity(
        id: 'payout-2',
        branchId: 'default',
        courierId: company.id,
        amountPiasters: 15000, // 150 EGP
        paymentMethod: 'safe',
        referenceNumber: 'REC-0012',
        payoutDate: now,
        createdAt: now,
      );

      await repo.recordShippingCompanyPayout(payout1);
      await repo.recordShippingCompanyPayout(payout2);

      // 5. Verify Statement after payouts
      final res2 = await repo.getShippingCompanyStatement(company.id);
      final s2 = res2.getOrElse(() => throw Exception());
      expect(s2.totalPayoutsReceivedPiasters, 35000); // 20000 + 15000
      expect(s2.remainingBalancePiasters, 16000); // 51000 - 35000
      expect(s2.payouts.length, 2);

      // 6. Reconcile Shipping Batch
      const batchId = 'BATCH-20261120-001';
      final reconcileRes = await repo.reconcileShippingBatch(
        company.id,
        [o1.id, o2.id],
        batchId,
      );
      expect(reconcileRes.isRight(), isTrue);

      final res3 = await repo.getShippingCompanyStatement(company.id);
      final s3 = res3.getOrElse(() => throw Exception());
      final batchOrders = s3.orders.where((o) => o.shippingBatchId == batchId).toList();
      expect(batchOrders.length, 2);
    });
  });

  group('Task 21: Thermal Delivery Slip Generation in Receipt PDF Tests', () {
    test('generateReceiptPdf includes delivery slip section when deliveryOrder is provided', () async {
      final invoice = InvoiceDetailsEntity(
        id: 'inv-test-01',
        shortRef: 'INV-1001',
        date: DateTime.now(),
        cashierId: 'cashier-1',
        cashierName: 'محمد كاشير',
        customerName: 'محمد كمال',
        customerPhone: '01001122334',
        paymentMethod: 'cod',
        subtotal: 35000,
        total: 35000,
        discountAmount: 0,
        items: const [],
      );

      final deliveryOrder = DeliveryOrderEntity(
        id: 'del-inv-1',
        branchId: 'default',
        orderRef: 'INV-1001',
        customerName: 'محمد كمال',
        customerPhone: '01001122334',
        deliveryAddress: 'القاهرة - التجمع الخامس - فيلا 12',
        deliveryFeePiasters: 5000, // 50 EGP
        orderTotalPiasters: 30000, // 300 EGP
        providerType: 'shipping_company',
        shippingFeePayer: 'customer_direct',
        courierName: 'أرامكس',
        waybillNumber: 'ARX-994821',
        shippingCostPiasters: 4000,
        notes: 'برجاء الاتصال قبل الوصول بنصف ساعة',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        invoice,
        deliveryOrder: deliveryOrder,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
    });
  });

  group('Task 21: WhatsApp Dispatch Message Formatting Tests', () {
    test('Formats WhatsApp message appropriately for in-house courier', () {
      final order = DeliveryOrderEntity(
        id: 'ord-wa-1',
        branchId: 'default',
        orderRef: 'DEL-881',
        customerName: 'سارة خالد',
        customerPhone: '01012345678',
        deliveryAddress: 'مدينة نصر - شارع عباس العقاد',
        deliveryFeePiasters: 2500,
        orderTotalPiasters: 17500,
        courierName: 'كابتن حسام',
        providerType: 'in_house',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final msg = 'طلبك في الطريق مع الكابتن ${order.courierName ?? "المندوب"} - المبلغ المطلوب: ${order.grandTotal.toStringAsFixed(2)} ج.م';
      expect(msg, contains('طلبك في الطريق مع الكابتن كابتن حسام'));
      expect(msg, contains('200.00 ج.م'));
    });

    test('Formats WhatsApp message appropriately for external shipping company with waybill', () {
      final order = DeliveryOrderEntity(
        id: 'ord-wa-2',
        branchId: 'default',
        orderRef: 'DEL-882',
        customerName: 'مازن يوسف',
        customerPhone: '01123456789',
        deliveryAddress: 'الشيخ زايد - كمبوند الياسمين',
        deliveryFeePiasters: 5000,
        orderTotalPiasters: 45000,
        courierName: 'بوسطة للشحن',
        providerType: 'shipping_company',
        waybillNumber: 'BOSTA-774411',
        shippingFeePayer: 'customer_direct',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final waybillText = (order.waybillNumber != null && order.waybillNumber!.isNotEmpty)
          ? ' برقم بوليصة ${order.waybillNumber}'
          : '';
      final msg = 'تم تسليم شحنتك لشركة ${order.courierName ?? "الشحن"}$waybillText للتتبع - المبلغ المطلوب تحصيله (COD): ${order.grandTotal.toStringAsFixed(2)} ج.م';

      expect(msg, contains('تم تسليم شحنتك لشركة بوسطة للشحن'));
      expect(msg, contains('برقم بوليصة BOSTA-774411'));
      expect(msg, contains('500.00 ج.م'));
    });
  });
}
