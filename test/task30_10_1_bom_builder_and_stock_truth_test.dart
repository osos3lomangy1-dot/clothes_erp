import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/presentation/widgets/culinary_profile_card.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/payment_method_pie_chart.dart';

void main() {
  group('Addendum 30.10.1: BOM Builder, Raw Stock Truth & Purchases Isolation', () {
    testWidgets('1. Interactive Recipe BOM Builder UI and dynamic item add/delete', (tester) async {
      final ingredientsCtrl = TextEditingController();
      final caloriesCtrl = TextEditingController();
      final prepTimeCtrl = TextEditingController();
      final selectedAllergens = <String>{};

      List<RecipeItemData> recipeItems = [
        const RecipeItemData(
          rawMaterialId: 'raw_meat_1',
          rawMaterialName: 'لحم مفروم بلدي',
          quantityNeeded: 200,
          unit: 'جرام',
          yieldLossPercentage: 10,
        ),
      ];

      final rawMaterials = <ProductEntity>[
        ProductEntity(
          id: 'raw_meat_1',
          name: 'لحم مفروم بلدي',
          description: const RestaurantCulinaryData(isRawMaterial: true).toEncodedString(),
          categoryId: 'raw_cat',
          categoryName: 'خامات',
          createdAt: DateTime.now(),
        ),
        ProductEntity(
          id: 'raw_cheese_1',
          name: 'جبنة شيدر مستوردة',
          description: const RestaurantCulinaryData(isRawMaterial: true).toEncodedString(),
          categoryId: 'raw_cat',
          categoryName: 'خامات',
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return CulinaryProfileCard(
                    ingredientsController: ingredientsCtrl,
                    caloriesController: caloriesCtrl,
                    prepTimeController: prepTimeCtrl,
                    selectedAllergens: selectedAllergens,
                    selectedKitchenStation: 'مطبخ ساخن (وجبات وجريل)',
                    onKitchenStationChanged: (_) {},
                    onAllergenToggled: (_, _) {},
                    recipeItems: recipeItems,
                    onRecipeItemsChanged: (newItems) {
                      setState(() => recipeItems = newItems);
                    },
                    availableRawMaterials: rawMaterials,
                    mealStockMode: 'onDemand',
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Verify BOM header section and add button
      expect(find.text('خامات ومقادير الوجبة (Recipe BOM):'), findsOneWidget);
      expect(find.byKey(const Key('add_recipe_item_btn')), findsOneWidget);

      // Verify existing recipe item is rendered in table
      expect(find.text('لحم مفروم بلدي'), findsOneWidget);
      expect(find.text('200 جرام'), findsOneWidget);
      expect(find.text('فاقد: 10%'), findsOneWidget);

      // Delete the existing recipe item
      final deleteBtn = find.byKey(const Key('delete_recipe_item_raw_meat_1'));
      expect(deleteBtn, findsOneWidget);
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Verify list is now empty and banner is displayed
      expect(recipeItems.isEmpty, isTrue);
      expect(find.textContaining('لم يتم ربط مقادير خامات بهذه الوجبة'), findsOneWidget);
    });

    test('2. Yield Loss & Effective Quantity Calculation for Bottleneck Analysis', () {
      const itemWithLoss = RecipeItemData(
        rawMaterialId: 'chicken_breast',
        rawMaterialName: 'صدور دجاج مخلية',
        quantityNeeded: 250, // 250g
        unit: 'جرام',
        yieldLossPercentage: 20, // 20% loss when cooking/trimming
      );

      // 250g needed with 20% yield loss = 250 * 1.20 = 300g effective needed
      expect(itemWithLoss.effectiveQuantityNeeded(1), 300.0);
      expect(itemWithLoss.effectiveQuantityNeeded(5), 1500.0);

      const itemZeroLoss = RecipeItemData(
        rawMaterialId: 'burger_bun',
        rawMaterialName: 'خبز برجر سمسم',
        quantityNeeded: 1,
        unit: 'حبة',
        yieldLossPercentage: 0,
      );

      expect(itemZeroLoss.effectiveQuantityNeeded(1), 1.0);
      expect(itemZeroLoss.effectiveQuantityNeeded(10), 10.0);
    });

    test('3. Raw Material Stock Bottleneck Servings Logic', () {
      // Scenario:
      // Recipe requires:
      // - 200g meat (yield loss 25% => 250g needed per meal)
      // - 1 bun (yield loss 0% => 1 needed per meal)
      // - 50g cheese (yield loss 0% => 50g needed per meal)
      const recipe = [
        RecipeItemData(
          rawMaterialId: 'meat',
          rawMaterialName: 'لحم',
          quantityNeeded: 200,
          unit: 'جرام',
          yieldLossPercentage: 25,
        ),
        RecipeItemData(
          rawMaterialId: 'bun',
          rawMaterialName: 'خبز',
          quantityNeeded: 1,
          unit: 'حبة',
          yieldLossPercentage: 0,
        ),
        RecipeItemData(
          rawMaterialId: 'cheese',
          rawMaterialName: 'جبنة',
          quantityNeeded: 50,
          unit: 'جرام',
          yieldLossPercentage: 0,
        ),
      ];

      // Inventory:
      // meat: 1000g available => 1000 / 250 = 4 meals
      // bun: 10 available => 10 / 1 = 10 meals
      // cheese: 150g available => 150 / 50 = 3 meals (Bottleneck!)
      final inventory = <String, int>{
        'meat': 1000,
        'bun': 10,
        'cheese': 150,
      };

      int minMeals = 999999;
      String bottleneckName = '';

      for (final ri in recipe) {
        final stock = inventory[ri.rawMaterialId] ?? 0;
        final neededPerMeal = ri.effectiveQuantityNeeded(1);
        final possible = (stock / neededPerMeal).floor();
        if (possible < minMeals) {
          minMeals = possible;
          bottleneckName = ri.rawMaterialName;
        }
      }

      expect(minMeals, 3);
      expect(bottleneckName, 'جبنة');
    });

    test('4. Strict Isolation: Raw Materials vs Prepared Meals Separation', () {
      final rawMaterial = ProductEntity(
        id: 'raw_oil',
        name: 'زيت قلي ذرة 20 لتر',
        description: const RestaurantCulinaryData(
          isRawMaterial: true,
          purchaseUnit: 'جركن 20 لتر',
          baseUnit: 'لتر',
          conversionFactor: 20.0,
        ).toEncodedString(),
        categoryId: 'raw_cat',
        categoryName: 'خامات',
        createdAt: DateTime.now(),
      );

      final preparedMeal = ProductEntity(
        id: 'meal_pizza',
        name: 'بيتزا سوبر سوبريم',
        description: const RestaurantCulinaryData(
          isRawMaterial: false,
          mealStockMode: 'onDemand',
        ).toEncodedString(),
        categoryId: 'pizza_cat',
        categoryName: 'وجبات',
        createdAt: DateTime.now(),
      );

      expect(rawMaterial.culinaryData.isRawMaterial, isTrue);
      expect(rawMaterial.isRestaurantRawMaterial, isTrue);

      expect(preparedMeal.culinaryData.isRawMaterial, isFalse);
      expect(preparedMeal.isRestaurantRawMaterial, isFalse);

      // In Purchases Screen for Hospitality:
      // Only items where cul.isRawMaterial == true are purchasable
      final allProducts = [rawMaterial, preparedMeal];
      final purchasableInHospitality = allProducts
          .where((p) => p.culinaryData.isRawMaterial)
          .toList();

      expect(purchasableInHospitality.length, 1);
      expect(purchasableInHospitality.first.name, 'زيت قلي ذرة 20 لتر');

      // In Non-Hospitality (Retail):
      // Raw materials are excluded
      final purchasableInRetail = allProducts
          .where((p) => !p.culinaryData.isRawMaterial)
          .toList();

      expect(purchasableInRetail.length, 1);
      expect(purchasableInRetail.first.name, 'بيتزا سوبر سوبريم');
    });

    testWidgets('5. PaymentMethodPieChart renders cleanly without overflow on tight widths', (tester) async {
      final breakdown = <String, int>{
        'cash': 6000,
        'card': 4000,
      };

      // Test with tight width (e.g., 400px split window or dashboard card)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: PaymentMethodPieChart(breakdown: breakdown),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('توزيع طرق الدفع'), findsOneWidget);
      expect(find.text('كاش (نقدي)'), findsOneWidget);
    });
  });
}
