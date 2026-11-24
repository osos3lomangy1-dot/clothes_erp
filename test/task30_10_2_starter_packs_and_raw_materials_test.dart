import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/services/culinary_starter_pack_engine.dart';
import 'package:clothes_erp/features/products/presentation/widgets/add_raw_material_dialog.dart';
import 'package:clothes_erp/features/products/presentation/widgets/culinary_starter_pack_dialog.dart';

class FakeProductRepository implements ProductRepository {
  final List<ProductEntity> products;

  FakeProductRepository([List<ProductEntity>? initial])
      : products = initial ?? [];

  @override
  Future<Either<Failure, void>> addProduct(ProductEntity product) async {
    products.add(product);
    return const Right(null);
  }

  @override
  Future<Either<Failure, String>> addProductWithVariants(
      ProductEntity product, List<VariantInput> variants) async {
    products.add(product);
    return Right(product.id);
  }

  @override
  Future<Either<Failure, void>> deleteProduct(
    String id, {
    bool forceDeleteForAdmin = false,
    String? userId,
  }) async =>
      const Right(null);

  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      Right(products);

  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() async* {
    yield Right(products);
  }

  @override
  Future<Either<Failure, void>> updateProduct(ProductEntity product) async =>
      const Right(null);
}

class FakeCategoryRepository implements CategoryRepository {
  final List<CategoryEntity> categories;

  FakeCategoryRepository([List<CategoryEntity>? initial])
      : categories = initial ?? [];

  @override
  Future<Either<Failure, void>> addCategory(CategoryEntity category) async {
    categories.add(category);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> deleteCategory(String id) async =>
      const Right(null);

  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async =>
      Right(categories);

  @override
  Future<Either<Failure, List<CategoryEntity>>>
      seedDefaultHospitalityCategories() async => Right(categories);

  @override
  Future<Either<Failure, void>> updateCategory(CategoryEntity category) async =>
      const Right(null);
}

void main() {
  group('Addendum 30.10.2: One-Click Starter Packs & Direct Raw Materials', () {
    test('1. Burger Diner Pack: Seeds 8 raw materials, 3 meals, and creates categories', () async {
      final prodRepo = FakeProductRepository();
      final catRepo = FakeCategoryRepository();

      final result = await CulinaryStarterPackEngine.seedStarterPack(
        packType: CulinaryStarterPackType.burgerDiner,
        productRepository: prodRepo,
        categoryRepository: catRepo,
      );

      expect(result.rawMaterialsCreated, 8);
      expect(result.mealsCreated, 3);
      expect(result.skippedCount, 0);
      expect(result.totalItemsAdded, 11);
      expect(prodRepo.products.length, 11);

      // Verify raw materials
      final rawMeat = prodRepo.products.firstWhere((p) => p.name == 'لحم بقري مفروم');
      expect(rawMeat.isRestaurantRawMaterial, isTrue);
      expect(rawMeat.culinaryData.baseUnit, 'جرام');
      expect(rawMeat.culinaryData.purchaseUnit, 'كرتونة 10 كجم');
      expect(rawMeat.culinaryData.conversionFactor, 10000.0);

      final briocheBun = prodRepo.products.firstWhere((p) => p.name == 'خبز كيزر بريوش');
      expect(briocheBun.isRestaurantRawMaterial, isTrue);
      expect(briocheBun.culinaryData.baseUnit, 'قطعة');

      // Verify meal and BOM linkage
      final burgerMeal = prodRepo.products.firstWhere((p) => p.name == 'سنجل كلاسيك برجر');
      expect(burgerMeal.isRestaurantRawMaterial, isFalse);
      expect(burgerMeal.culinaryData.mealStockMode, 'onDemand');
      expect(burgerMeal.culinaryData.recipeItems.length, 5);

      final meatRecipeItem = burgerMeal.culinaryData.recipeItems.firstWhere((r) => r.rawMaterialName == 'لحم بقري مفروم');
      expect(meatRecipeItem.rawMaterialId, rawMeat.id);
      expect(meatRecipeItem.quantityNeeded, 150.0);
      expect(meatRecipeItem.yieldLossPercentage, 15.0);

      final bunRecipeItem = burgerMeal.culinaryData.recipeItems.firstWhere((r) => r.rawMaterialName == 'خبز كيزر بريوش');
      expect(bunRecipeItem.rawMaterialId, briocheBun.id);
      expect(bunRecipeItem.quantityNeeded, 1.0);
    });

    test('2. Specialty Cafe Pack: Seeds 5 raw materials and 4 barista drinks with BOM', () async {
      final prodRepo = FakeProductRepository();
      final catRepo = FakeCategoryRepository();

      final result = await CulinaryStarterPackEngine.seedStarterPack(
        packType: CulinaryStarterPackType.specialtyCafe,
        productRepository: prodRepo,
        categoryRepository: catRepo,
      );

      expect(result.rawMaterialsCreated, 5);
      expect(result.mealsCreated, 4);
      expect(result.totalItemsAdded, 9);

      final coffeeBeans = prodRepo.products.firstWhere((p) => p.name == 'بن حبوب كولومبي مختص');
      expect(coffeeBeans.isRestaurantRawMaterial, isTrue);

      final flatWhite = prodRepo.products.firstWhere((p) => p.name == 'فلات وايت');
      expect(flatWhite.culinaryData.recipeItems.length, 3);

      final coffeeInDrink = flatWhite.culinaryData.recipeItems.firstWhere((r) => r.rawMaterialName == 'بن حبوب كولومبي مختص');
      expect(coffeeInDrink.rawMaterialId, coffeeBeans.id);
      expect(coffeeInDrink.quantityNeeded, 18.0);
    });

    test('3. Pizzeria & Pasta Pack: Seeds 7 raw materials and 2 signature dishes with BOM', () async {
      final prodRepo = FakeProductRepository();
      final catRepo = FakeCategoryRepository();

      final result = await CulinaryStarterPackEngine.seedStarterPack(
        packType: CulinaryStarterPackType.pizzeriaAndPasta,
        productRepository: prodRepo,
        categoryRepository: catRepo,
      );

      expect(result.rawMaterialsCreated, 7);
      expect(result.mealsCreated, 2);
      expect(result.totalItemsAdded, 9);

      final flour = prodRepo.products.firstWhere((p) => p.name == 'دقيق إيطالي Tipo 00');
      expect(flour.isRestaurantRawMaterial, isTrue);

      final pizza = prodRepo.products.firstWhere((p) => p.name == 'بيتزا مارجريتا نابوليتانو');
      expect(pizza.culinaryData.recipeItems.length, 5);

      final flourInPizza = pizza.culinaryData.recipeItems.firstWhere((r) => r.rawMaterialName == 'دقيق إيطالي Tipo 00');
      expect(flourInPizza.rawMaterialId, flour.id);
      expect(flourInPizza.quantityNeeded, 220.0);
    });

    test('4. Deduplication: skipIfExists avoids duplicate entries on re-run', () async {
      final prodRepo = FakeProductRepository();
      final catRepo = FakeCategoryRepository();

      // First run: installs 11 items
      final firstRun = await CulinaryStarterPackEngine.seedStarterPack(
        packType: CulinaryStarterPackType.burgerDiner,
        productRepository: prodRepo,
        categoryRepository: catRepo,
        skipIfExists: true,
      );
      expect(firstRun.rawMaterialsCreated, 8);
      expect(firstRun.mealsCreated, 3);

      // Second run: should skip existing items
      final secondRun = await CulinaryStarterPackEngine.seedStarterPack(
        packType: CulinaryStarterPackType.burgerDiner,
        productRepository: prodRepo,
        categoryRepository: catRepo,
        skipIfExists: true,
      );
      expect(secondRun.rawMaterialsCreated, 0);
      expect(secondRun.mealsCreated, 0);
      expect(secondRun.skippedCount, 11);
      expect(prodRepo.products.length, 11);
    });

    testWidgets('5. CulinaryStarterPackDialog: Renders 3 pack cards and install action button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CulinaryStarterPackDialog(),
          ),
        ),
      );

      expect(find.text('باقات المنيو والخامات الجاهزة بنقرة واحدة'), findsOneWidget);
      expect(find.text('باقة برجر داينر (Burger Diner)'), findsOneWidget);
      expect(find.text('باقة مقهى ومشروبات مختصة (Specialty Cafe)'), findsOneWidget);
      expect(find.text('باقة بيتزا نابوليتانو وباستا (Pizzeria & Pasta)'), findsOneWidget);
      expect(find.byKey(const Key('install_starter_pack_btn')), findsOneWidget);

      // Tap on another pack
      await tester.tap(find.text('باقة مقهى ومشروبات مختصة (Specialty Cafe)'));
      await tester.pumpAndSettle();
    });

    testWidgets('6. AddRawMaterialDialog: Renders all raw material creation fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddRawMaterialDialog(),
          ),
        ),
      );

      expect(find.text('إضافة مادة خام أو مستلزم جديد'), findsOneWidget);
      expect(find.byKey(const Key('add_raw_material_name_field')), findsOneWidget);
      expect(find.byKey(const Key('add_raw_material_category_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('add_raw_material_unit_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('add_raw_material_cost_field')), findsOneWidget);
      expect(find.byKey(const Key('add_raw_material_stock_field')), findsOneWidget);
      expect(find.byKey(const Key('add_raw_material_min_stock_field')), findsOneWidget);
      expect(find.byKey(const Key('save_raw_material_btn')), findsOneWidget);
    });

    test('7. Filter Logic: Separates Raw Materials from Menu Meals with strict isolation', () {
      final raw1 = ProductEntity(
        id: 'r1',
        name: 'لحم بقري',
        description: const RestaurantCulinaryData(isRawMaterial: true).toEncodedString(),
        categoryId: 'c1',
        categoryName: 'خامات',
        createdAt: DateTime.now(),
      );

      final meal1 = ProductEntity(
        id: 'm1',
        name: 'برجر كلاسيك',
        description: const RestaurantCulinaryData(isRawMaterial: false).toEncodedString(),
        categoryId: 'c2',
        categoryName: 'وجبات',
        createdAt: DateTime.now(),
      );

      final allProducts = [raw1, meal1];

      // Tab 'meals': only isRawMaterial == false
      final mealsOnly = allProducts.where((p) => !p.culinaryData.isRawMaterial).toList();
      expect(mealsOnly.length, 1);
      expect(mealsOnly.first.name, 'برجر كلاسيك');

      // Tab 'rawMaterials': only isRawMaterial == true
      final rawOnly = allProducts.where((p) => p.culinaryData.isRawMaterial).toList();
      expect(rawOnly.length, 1);
      expect(rawOnly.first.name, 'لحم بقري');
    });
  });
}
