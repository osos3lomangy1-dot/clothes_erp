import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/services/food_cost_calculator.dart';
import 'package:clothes_erp/features/products/presentation/widgets/culinary_profile_card.dart';

void main() {
  group('Task 30.9: Multi-Unit Conversion & Raw Material Matrix', () {
    test('Calculates cost per base unit accurately from wholesale purchase unit', () {
      // Flour 25kg sack purchased at 50,000 piasters (500 EGP)
      const data = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'شيكارة 25ك',
        baseUnit: 'جرام',
        conversionFactor: 25000.0,
      );

      final costPerGram = data.costPerBaseUnit(50000);
      expect(costPerGram, equals(2.0)); // 2 piasters per gram
    });

    test('ProductEntity exposes restaurantBaseUnit, conversionFactor, and costPerBaseUnit', () {
      final product = ProductEntity(
        id: 'raw-1',
        name: 'دقيق فاخر',
        description: const RestaurantCulinaryData(
          isRawMaterial: true,
          purchaseUnit: 'شيكارة 25ك',
          baseUnit: 'جرام',
          conversionFactor: 25000.0,
          packagingCostPiasters: 150,
        ).toEncodedString(),
        categoryId: 'cat-raw',
        categoryName: 'مواد خام',
        createdAt: DateTime.now(),
      );

      expect(product.isRestaurantRawMaterial, isTrue);
      expect(product.restaurantPurchaseUnit, equals('شيكارة 25ك'));
      expect(product.restaurantBaseUnit, equals('جرام'));
      expect(product.restaurantConversionFactor, equals(25000.0));
      expect(product.restaurantPackagingCostPiasters, equals(150));
      expect(product.costPerBaseUnit(75000), equals(3.0));
    });

    test('Formats dual stock balance cleanly with equivalent higher units', () {
      const flourData = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'شيكارة 25ك',
        baseUnit: 'جرام',
        conversionFactor: 25000.0,
      );

      // 14,250 grams -> 14.25 kg
      final formatted = flourData.formatDualQuantity(14250);
      expect(formatted, contains('14,250 جرام'));
      expect(formatted, contains('14.25 كجم'));

      // 20,000 ml oil -> 20 liters
      const oilData = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: 'جركن 20 لتر',
        baseUnit: 'مل',
        conversionFactor: 20000.0,
      );
      final formattedOil = oilData.formatDualQuantity(20000);
      expect(formattedOil, contains('20,000 مل'));
      expect(formattedOil, contains('20 لتر'));
    });
  });

  group('Task 30.9: Yield Loss & Recipe Item Costing', () {
    test('Calculates effective quantity needed accounting for shrinkage and loss', () {
      // 150g raw burger patty with 20% cooking shrinkage
      const recipeItem = RecipeItemData(
        rawMaterialId: 'beef-1',
        rawMaterialName: 'لحم بقري مفروم',
        quantityNeeded: 150.0,
        yieldLossPercentage: 20.0,
        unit: 'جرام',
      );

      // For 1 meal: 150 * (1 + 0.20) = 180g
      expect(recipeItem.effectiveQuantityNeeded(1), equals(180.0));

      // For 3 meals: 180 * 3 = 540g
      expect(recipeItem.effectiveQuantityNeeded(3), equals(540.0));

      // Cost calculation with unit cost of 0.5 piasters/gram: 180 * 0.5 = 90 piasters
      expect(recipeItem.calculateIngredientCost(0.5), equals(90.0));
    });
  });

  group('Task 30.9: FoodCostCalculator Engine & Live Badges', () {
    test('Food Cost <= 32% yields Excellent rating and green badge', () {
      const items = [
        RecipeItemData(
          rawMaterialId: 'raw-1',
          rawMaterialName: 'دجاج متبل',
          quantityNeeded: 200.0,
          yieldLossPercentage: 10.0, // 220g effective
          unit: 'جرام',
        ),
      ];

      // Cost per gram = 10 piasters -> raw material cost = 220 * 10 = 2,200 piasters
      // Packaging = 300 piasters -> Total cost = 2,500 piasters
      // Sale price = 10,000 piasters (100 EGP) -> Food Cost % = 25% (<= 32%)
      final analysis = FoodCostCalculator.calculate(
        recipeItems: items,
        rawMaterialUnitCostsPiasters: {'raw-1': 10.0},
        salePricePiasters: 10000,
        packagingCostPiasters: 300,
      );

      expect(analysis.rating, equals(FoodCostRating.excellent));
      expect(analysis.foodCostPercentage, equals(25.0));
      expect(analysis.profitMarginPercentage, equals(75.0));
      expect(analysis.badgeColor, equals(AppColors.successContainer));
      expect(analysis.badgeTextColor, equals(AppColors.success));
      expect(analysis.summaryText, contains('تكلفة ممتازة: 25% | هامش ربح: 75%'));
    });

    test('Food Cost 33% - 35% yields Acceptable rating and neutral badge', () {
      const items = [
        RecipeItemData(
          rawMaterialId: 'raw-2',
          rawMaterialName: 'لحم برجر',
          quantityNeeded: 150.0,
          yieldLossPercentage: 0.0,
          unit: 'جرام',
        ),
      ];

      // Cost per gram = 20 piasters -> raw material cost = 3,000 piasters
      // Packaging = 400 piasters -> Total cost = 3,400 piasters
      // Sale price = 10,000 piasters -> Food Cost % = 34% (33% - 35%)
      final analysis = FoodCostCalculator.calculate(
        recipeItems: items,
        rawMaterialUnitCostsPiasters: {'raw-2': 20.0},
        salePricePiasters: 10000,
        packagingCostPiasters: 400,
      );

      expect(analysis.rating, equals(FoodCostRating.acceptable));
      expect(analysis.foodCostPercentage, equals(34.0));
      expect(analysis.profitMarginPercentage, equals(66.0));
      expect(analysis.badgeColor, equals(AppColors.surfaceContainer));
      expect(analysis.badgeTextColor, equals(AppColors.onSurfaceVariant));
      expect(analysis.summaryText, contains('تكلفة مقبولة: 34% | هامش ربح: 66%'));
    });

    test('Food Cost > 35% yields High warning rating and orange badge', () {
      const items = [
        RecipeItemData(
          rawMaterialId: 'raw-3',
          rawMaterialName: 'ستيك لحم',
          quantityNeeded: 300.0,
          yieldLossPercentage: 0.0,
          unit: 'جرام',
        ),
      ];

      // Cost per gram = 15 piasters -> raw cost = 4,500 piasters
      // Sale price = 10,000 piasters -> Food Cost % = 45% (> 35%)
      final analysis = FoodCostCalculator.calculate(
        recipeItems: items,
        rawMaterialUnitCostsPiasters: {'raw-3': 15.0},
        salePricePiasters: 10000,
        packagingCostPiasters: 0,
      );

      expect(analysis.rating, equals(FoodCostRating.high));
      expect(analysis.foodCostPercentage, equals(45.0));
      expect(analysis.profitMarginPercentage, equals(55.0));
      expect(analysis.badgeColor, equals(AppColors.warningContainer));
      expect(analysis.badgeTextColor, equals(AppColors.warning));
      expect(analysis.summaryText, contains('تكلفة مرتفعة: 45% - مراجعة التسعير'));
    });
  });

  group('Task 30.9: CulinaryProfileCard Widget Tests with Live Badge', () {
    testWidgets('Displays live food cost badge when recipeItems and salePrice are passed', (tester) async {
      final ingCtrl = TextEditingController();
      final calCtrl = TextEditingController();
      final prepCtrl = TextEditingController();

      const items = [
        RecipeItemData(
          rawMaterialId: 'beef-10',
          rawMaterialName: 'لحم مفروم',
          quantityNeeded: 100.0,
          yieldLossPercentage: 0.0,
          unit: 'جرام',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CulinaryProfileCard(
                ingredientsController: ingCtrl,
                caloriesController: calCtrl,
                prepTimeController: prepCtrl,
                selectedAllergens: const {'بيض'},
                selectedKitchenStation: 'مطبخ ساخن (وجبات وجريل)',
                onKitchenStationChanged: (_) {},
                onAllergenToggled: (_, _) {},
                recipeItems: items,
                rawMaterialUnitCosts: const {'beef-10': 3.0}, // 300 piasters
                salePricePiasters: 1200, // 300 / 1200 = 25% -> excellent
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('food_cost_analysis_badge')), findsOneWidget);
      expect(find.textContaining('تكلفة ممتازة: 25% | هامش ربح: 75%'), findsOneWidget);
    });
  });

  group('Task 30.9: Strict F&B Isolation Verification', () {
    test('Retail/Apparel products have zero culinary/recipe metadata and standard string format', () {
      final apparel = ProductEntity(
        id: 'cloth-1',
        name: 'قميص أكسفورد أزرق',
        description: 'قطن 100% فاخر ومريح',
        categoryId: 'cat-apparel',
        categoryName: 'قمصان',
        activityType: 'clothing',
        createdAt: DateTime.now(),
      );

      expect(apparel.isRestaurantRawMaterial, isFalse);
      expect(apparel.restaurantRecipeItems, isEmpty);
      expect(apparel.restaurantBaseUnit, isNull);
      expect(apparel.restaurantPackagingCostPiasters, isNull);
      expect(apparel.cleanDescription, equals('قطن 100% فاخر ومريح'));
    });
  });
}
