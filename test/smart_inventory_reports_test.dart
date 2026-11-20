import 'package:clothes_erp/features/reports/domain/entities/smart_inventory_entities.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/smart_inventory_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Smart Inventory Reports Entities & State Calculations', () {
    test('ReorderSuggestionEntity computes properties and props correctly', () {
      const item = ReorderSuggestionEntity(
        variantId: 'v1',
        productId: 'p1',
        productName: 'قميص كاجوال كحلي',
        sku: '100200',
        categoryName: 'قمصان',
        color: 'كحلي',
        size: 'L',
        currentStock: 2,
        minStock: 10,
        soldLast30Days: 25,
        dailySalesRate: 25 / 30,
        suggestedReorderQty: 18,
        costPricePiasters: 15000,
        totalEstimatedCostPiasters: 18 * 15000,
      );

      expect(item.currentStock, 2);
      expect(item.suggestedReorderQty, 18);
      expect(item.costPricePiasters, 15000);
      expect(item.totalEstimatedCostPiasters, 270000); // 2700.00 EGP
    });

    test('DeadStockItemEntity calculates frozen capital accurately', () {
      const item = DeadStockItemEntity(
        variantId: 'v2',
        productId: 'p2',
        productName: 'بنطلون جينز كلاسيك',
        sku: '100300',
        categoryName: 'بنطلونات',
        color: 'أزرق',
        size: '34',
        currentStock: 15,
        costPricePiasters: 20000, // 200 EGP
        sellPricePiasters: 35000, // 350 EGP
        frozenCapitalPiasters: 15 * 20000, // 3000 EGP
        lostRevenuePotentialPiasters: 15 * 35000, // 5250 EGP
        daysWithoutSale: 60,
      );

      expect(item.currentStock, 15);
      expect(item.frozenCapitalPiasters, 300000);
      expect(item.lostRevenuePotentialPiasters, 525000);
      expect(item.daysWithoutSale, 60);
    });

    test('StockMovementCardItemEntity tracks running balance and transaction types', () {
      final now = DateTime(2026, 11, 20, 10, 30);
      final entry1 = StockMovementCardItemEntity(
        logId: 'l1',
        date: now,
        type: 'receive',
        typeLabel: 'استلام / توريد بضاعة',
        qtyDelta: 20,
        runningBalance: 20,
        userName: 'المدير',
      );

      final entry2 = StockMovementCardItemEntity(
        logId: 'l2',
        date: now.add(const Duration(hours: 2)),
        type: 'sale',
        typeLabel: 'فاتورة مبيعات',
        qtyDelta: -3,
        runningBalance: 17,
        refType: 'sale',
        refId: 's-12345678',
        userName: 'كاشير 1',
      );

      expect(entry1.qtyDelta, 20);
      expect(entry1.runningBalance, 20);
      expect(entry2.qtyDelta, -3);
      expect(entry2.runningBalance, 17);
    });

    test('SmartInventoryState aggregates totals across items correctly', () {
      const reorder1 = ReorderSuggestionEntity(
        variantId: 'v1',
        productId: 'p1',
        productName: 'Item 1',
        sku: 'SKU1',
        categoryName: 'Cat 1',
        color: 'Red',
        size: 'M',
        currentStock: 1,
        minStock: 5,
        soldLast30Days: 10,
        dailySalesRate: 10 / 30,
        suggestedReorderQty: 10,
        costPricePiasters: 5000,
        totalEstimatedCostPiasters: 50000,
      );

      const reorder2 = ReorderSuggestionEntity(
        variantId: 'v2',
        productId: 'p2',
        productName: 'Item 2',
        sku: 'SKU2',
        categoryName: 'Cat 2',
        color: 'Blue',
        size: 'L',
        currentStock: 0,
        minStock: 8,
        soldLast30Days: 15,
        dailySalesRate: 15 / 30,
        suggestedReorderQty: 16,
        costPricePiasters: 10000,
        totalEstimatedCostPiasters: 160000,
      );

      const dead1 = DeadStockItemEntity(
        variantId: 'v3',
        productId: 'p3',
        productName: 'Dead 1',
        sku: 'SKU3',
        categoryName: 'Cat 1',
        color: 'Black',
        size: 'XL',
        currentStock: 10,
        costPricePiasters: 8000,
        sellPricePiasters: 15000,
        frozenCapitalPiasters: 80000,
        lostRevenuePotentialPiasters: 150000,
        daysWithoutSale: 60,
      );

      const dead2 = DeadStockItemEntity(
        variantId: 'v4',
        productId: 'p4',
        productName: 'Dead 2',
        sku: 'SKU4',
        categoryName: 'Cat 2',
        color: 'White',
        size: 'S',
        currentStock: 5,
        costPricePiasters: 12000,
        sellPricePiasters: 20000,
        frozenCapitalPiasters: 60000,
        lostRevenuePotentialPiasters: 100000,
        daysWithoutSale: 90,
      );

      final state = const SmartInventoryState().copyWith(
        reorderSuggestions: [reorder1, reorder2],
        deadStockItems: [dead1, dead2],
      );

      expect(state.totalReorderCostPiasters, 210000); // 50,000 + 160,000
      expect(state.totalFrozenCapitalPiasters, 140000); // 80,000 + 60,000
      expect(state.totalLostRevenuePotentialPiasters, 250000); // 150,000 + 100,000
      expect(state.totalDeadUnits, 15); // 10 + 5
    });
  });
}

