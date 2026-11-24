import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/pos/domain/services/kitchen_order_ticket_service.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/payment_method_pie_chart.dart';

void main() {
  group('Addendum 30.10: Smart Restaurant & Cafe Suite Phase 1', () {
    test('1. Meal Stock Modes: onDemand vs dailyBatch in ProductEntity', () {
      const onDemandData = RestaurantCulinaryData(
        mealStockMode: 'onDemand',
        recipeItems: [
          RecipeItemData(
            rawMaterialId: 'raw_meat',
            rawMaterialName: 'لحم بقري',
            quantityNeeded: 250,
            unit: 'جرام',
          ),
        ],
      );

      final pOnDemand = ProductEntity(
        id: 'burger_1',
        name: 'برجر لحم كلاسيك',
        description: onDemandData.toEncodedString(),
        categoryId: 'cat_burgers',
        categoryName: 'برجر',
        createdAt: DateTime.now(),
      );

      expect(pOnDemand.mealStockMode, 'onDemand');
      expect(pOnDemand.isDailyBatch, isFalse);
      expect(pOnDemand.culinaryData.recipeItems.length, 1);

      const dailyBatchData = RestaurantCulinaryData(
        mealStockMode: 'dailyBatch',
        dailyBatchCount: 25,
      );

      final pDailyBatch = ProductEntity(
        id: 'soup_1',
        name: 'شوربة كوارع مجهزة يومياً',
        description: dailyBatchData.toEncodedString(),
        categoryId: 'cat_soups',
        categoryName: 'شوربات',
        createdAt: DateTime.now(),
      );

      expect(pDailyBatch.mealStockMode, 'dailyBatch');
      expect(pDailyBatch.isDailyBatch, isTrue);
      expect(pDailyBatch.dailyBatchCount, 25);
    });

    test('2. Paid Modifiers Model & Serialization', () {
      const paidMod1 = PaidModifierData(
        name: 'إكسترا جبنة شيدر',
        pricePiasters: 1500, // 15 EGP
        rawMaterialId: 'cheese_raw',
        quantityNeeded: 50,
      );

      const paidMod2 = PaidModifierData(
        name: 'شريحة بيكون بقري',
        pricePiasters: 2500, // 25 EGP
      );

      final culinary = const RestaurantCulinaryData().copyWith(
        paidModifiers: [paidMod1, paidMod2],
      );

      final encoded = culinary.toEncodedString();
      final parsed = RestaurantCulinaryData.parse(encoded);

      expect(parsed.paidModifiers.length, 2);
      expect(parsed.paidModifiers[0].name, 'إكسترا جبنة شيدر');
      expect(parsed.paidModifiers[0].pricePiasters, 1500);
      expect(parsed.paidModifiers[1].name, 'شريحة بيكون بقري');
      expect(parsed.paidModifiers[1].pricePiasters, 2500);
    });

    test('3. Kitchen Order Ticket: Normal vs Rush Order Banner', () {
      final items = [
        const SaleItemEntity(
          variantId: 'v1',
          productId: 'p1',
          productName: 'برجر دوبل تريبل',
          price: 12000,
          quantity: 2,
          color: '-',
          size: '-',
          kitchenNotes: 'بدون بصل',
          modifiers: ['سبايسي', 'إكسترا جبنة شيدر (+15.00 ج.م)'],
        ),
      ];

      // Normal ticket
      final normalTicket = KitchenOrderTicketService.generateKitchenOrderTicket(
        orderType: 'dineIn',
        tableNumber: '7',
        invoiceNumber: 'KOT-101',
        date: DateTime(2026, 11, 24, 15, 30),
        items: items,
        isRush: false,
      );

      expect(normalTicket.contains('بون تحضير المطبخ (KOT)'), isTrue);
      expect(normalTicket.contains('[ أوردر مستعجل - أولوية أولى للتحضير فـوراً ]'), isFalse);
      expect(normalTicket.contains('صالة (طاولة: 7)'), isTrue);

      // Rush ticket
      final rushTicket = KitchenOrderTicketService.generateKitchenOrderTicket(
        orderType: 'takeaway',
        tableNumber: null,
        invoiceNumber: 'KOT-102',
        date: DateTime(2026, 11, 24, 15, 31),
        items: items,
        isRush: true,
      );

      expect(rushTicket.contains('[ أوردر مستعجل - أولوية أولى للتحضير فـوراً ]'), isTrue);
      expect(rushTicket.contains('تيك أواي / سفري'), isTrue);
    });

    test('4. Receipt Config: Tax & Dine-in Service Charge Control', () {
      final defaultCfg = ReceiptConfig.defaults;
      expect(defaultCfg.taxEnabled, isFalse);
      expect(defaultCfg.taxRate, 14.0);
      expect(defaultCfg.taxInclusive, isFalse);
      expect(defaultCfg.dineInServiceChargeEnabled, isFalse);
      expect(defaultCfg.dineInServiceChargeRate, 12.0);

      final hospCfg = ReceiptConfig.hospitalityDefaults;
      expect(hospCfg.dineInServiceChargeEnabled, isTrue);
      expect(hospCfg.dineInServiceChargeRate, 12.0);

      final updated = hospCfg.copyWith(
        taxEnabled: true,
        taxRate: 14.0,
        taxInclusive: true,
        dineInServiceChargeRate: 10.0,
      );

      expect(updated.taxEnabled, isTrue);
      expect(updated.taxInclusive, isTrue);
      expect(updated.dineInServiceChargeRate, 10.0);
    });

    test('5. Multi-Unit Pack Size Conversion in Purchases Logic', () {
      const rawBulk = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'كرتونة 500 كانز',
        baseUnit: 'كانز',
        conversionFactor: 500.0,
      );

      expect(rawBulk.isRawMaterial, isTrue);
      expect(rawBulk.conversionFactor, 500.0);

      // Purchase of 2 cartons at 5,000 EGP total (2,500 EGP per carton)
      const qtyCartonsPurchased = 2;
      const cartonCostPiasters = 250000; // 2,500 EGP

      final totalBaseUnits = (qtyCartonsPurchased * rawBulk.conversionFactor!).round();
      final unitCostPiasters = (cartonCostPiasters / rawBulk.conversionFactor!).round();

      expect(totalBaseUnits, 1000);
      expect(unitCostPiasters, 500); // 5.00 EGP per can
    });

    testWidgets('6. PaymentMethodPieChart layout resilience on tight width (No RenderFlex overflow)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 600));

      final breakdown = {
        'cash': 6000,
        'card': 4000,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380, // tight width simulating half-screen
                child: PaymentMethodPieChart(breakdown: breakdown),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(PaymentMethodPieChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
