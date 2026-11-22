import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/products/data/models/product_model.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';

void main() {
  group('Task 11.1 - Product Timestamps and History Tracking Tests', () {
    test('ProductEntity preserves createdAt and updatedAt', () {
      final now = DateTime(2026, 11, 20, 10, 30);
      final updated = DateTime(2026, 11, 22, 14, 45);

      final entity = ProductEntity(
        id: 'prod_12345',
        name: 'قميص كلاسيك كروهات',
        categoryId: 'cat_shirts',
        categoryName: 'قمصان',
        description: 'قميص رجالي قطن 100%',
        minStock: 5,
        isActive: true,
        createdAt: now,
        updatedAt: updated,
      );

      expect(entity.id, equals('prod_12345'));
      expect(entity.createdAt, equals(now));
      expect(entity.updatedAt, equals(updated));
    });

    test('ProductModel serializes and deserializes timestamps accurately', () {
      final created = DateTime(2026, 1, 15, 8, 0);
      final updated = DateTime(2026, 6, 20, 16, 30);

      final model = ProductModel(
        id: 'p_1',
        name: 'بدلة كاملة',
        categoryId: 'cat_suits',
        categoryName: 'بدل',
        description: 'بدلة كلاسيك رسمية',
        createdAt: created,
        updatedAt: updated,
        minStock: 2,
        isActive: true,
      );

      final json = model.toJson();
      expect(json['createdAt'], equals(created.toIso8601String()));
      expect(json['updatedAt'], equals(updated.toIso8601String()));

      final restored = ProductModel.fromJson(json);
      expect(restored.createdAt, equals(created));
      expect(restored.updatedAt, equals(updated));
    });

    test('ProductModel copyWith updates updatedAt without mutating createdAt', () {
      final created = DateTime(2026, 3, 1, 12, 0);
      final updatedFirst = DateTime(2026, 3, 5, 15, 0);
      final updatedSecond = DateTime(2026, 3, 10, 18, 0);

      final model = ProductModel(
        id: 'p_2',
        name: 'تيشيرت بولو',
        categoryId: 'cat_tshirts',
        categoryName: 'تيشيرتات',
        description: 'تيشيرت بولو كاجوال',
        createdAt: created,
        updatedAt: updatedFirst,
      );

      final updatedModel = model.copyWith(
        name: 'تيشيرت بولو كحلي',
        updatedAt: updatedSecond,
      );

      expect(updatedModel.name, equals('تيشيرت بولو كحلي'));
      expect(updatedModel.createdAt, equals(created));
      expect(updatedModel.updatedAt, equals(updatedSecond));
    });
  });

  group('Task 11.2 - Master Categorized Feature Control Matrix Keys Tests', () {
    test('all 4 feature category keys are properly registered in FeatureKeys', () {
      // 1. POS & Cashier Controls
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.pos), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.wholesalePricing), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.splitPayment), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.creditSales), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.holdBills), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.promotions), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.loyalty), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.installments), isTrue);

      // 2. Inventory & Activities Controls
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.inventory), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.inventoryLogs), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.purchases), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.suppliers), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.lowStockAlerts), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.productTimestamps), isTrue);

      // 3. Omnichannel & Pre-Orders Controls
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.preOrders), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.consolidatedBatches), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.telegramBot), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.whatsappDirect), isTrue);

      // 4. Financial, Shifts & Security Controls
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.shifts), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.blindShiftClosing), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.drawerPettyCash), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.expenses), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.reports), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.partners), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.employees), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.payroll), isTrue);
      expect(FeatureKeys.byKey.containsKey(FeatureKeys.managerPinProtection), isTrue);
    });

    test('feature dependencies are correctly enforced', () {
      expect(
        FeatureKeys.byKey[FeatureKeys.payroll]!.dependencies,
        contains(FeatureKeys.employees),
      );
      expect(
        FeatureKeys.byKey[FeatureKeys.suppliers]!.dependencies,
        contains(FeatureKeys.purchases),
      );
      expect(
        FeatureKeys.byKey[FeatureKeys.installments]!.dependencies,
        contains(FeatureKeys.customers),
      );
      expect(
        FeatureKeys.byKey[FeatureKeys.loyalty]!.dependencies,
        contains(FeatureKeys.customers),
      );
    });
  });
}
