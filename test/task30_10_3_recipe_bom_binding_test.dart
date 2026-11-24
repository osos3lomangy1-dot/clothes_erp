import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';
import 'package:clothes_erp/features/categories/data/repositories/category_repository_impl.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/services/food_cost_calculator.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _cached;
  @override
  Future<void> cacheUser(UserModel user) async => _cached = user;
  @override
  Future<UserModel?> getCachedUser() async => _cached;
  @override
  Future<void> clearCache() async => _cached = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProductRepo implements ProductRepository {
  final List<ProductEntity> savedProducts = [];
  ProductEntity? lastUpdatedProduct;

  @override
  Future<Either<Failure, String>> addProductWithVariants(
      ProductEntity product, dynamic variants) async {
    savedProducts.add(product);
    return Right(product.id.isEmpty ? 'prod_1' : product.id);
  }

  @override
  Future<Either<Failure, Unit>> updateProduct(ProductEntity product) async {
    lastUpdatedProduct = product;
    final idx = savedProducts.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      savedProducts[idx] = product;
    } else {
      savedProducts.add(product);
    }
    return const Right(unit);
  }

  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      Right(savedProducts);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Addendum 30.10.3: FoodCostCalculator Calculation Truth', () {
    test('calculateTotalRecipeCostPiasters calculates ingredient costs with yield loss', () {
      final items = [
        const RecipeItemData(
          rawMaterialId: 'beef-1',
          rawMaterialName: 'لحم مفروم',
          quantityNeeded: 150, // 150g
          yieldLossPercentage: 10, // 10% loss -> 150 / 0.9 = 166.6667g
          unit: 'جرام',
        ),
        const RecipeItemData(
          rawMaterialId: 'bun-1',
          rawMaterialName: 'خبز كيزر',
          quantityNeeded: 1, // 1 piece
          yieldLossPercentage: 0,
          unit: 'قطعة',
        ),
      ];

      final unitCosts = <String, double>{
        'beef-1': 0.5, // 50 piasters per gram
        'bun-1': 500.0, // 500 piasters per piece
      };

      final total = FoodCostCalculator.calculateTotalRecipeCostPiasters(
        recipeItems: items,
        rawMaterialUnitCostsPiasters: unitCosts,
      );

      // beef: 150 * (1 + 0.1) * 0.5 = 82.5 piasters
      // bun: 1 * 500 = 500 piasters
      // total = 582.5
      expect(total, closeTo(582.5, 0.1));
    });
  });

  group('Addendum 30.10.3: SimpleProductFormDialog Recipe BOM Binding & Persistence', () {
    late AppDatabase db;
    late FeatureGate featureGate;
    late ActivitySettingsService activityService;
    late _MockProductRepo productRepo;
    late CategoryRepository categoryRepo;
    late ProductFormCubit productFormCubit;
    late AuthCubit authCubit;

    setUp(() async {
      final getIt = GetIt.instance;
      await getIt.reset();

      db = AppDatabase(NativeDatabase.memory());
      final authLocalDs = _FakeAuthLocalDataSource();
      final branchProvider = _FakeBranchProvider();
      final txWriter = TxWriter(db);
      featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
      activityService = ActivitySettingsService(db, featureGate);
      productRepo = _MockProductRepo();

      final categoryLocalDataSource = CategoryLocalDataSource(db, branchProvider);
      categoryRepo = CategoryRepositoryImpl(categoryLocalDataSource);

      getIt.registerSingleton<AppDatabase>(db);
      getIt.registerSingleton<FeatureGate>(featureGate);
      getIt.registerSingleton<ActivitySettingsService>(activityService);
      getIt.registerSingleton<ProductRepository>(productRepo);
      getIt.registerSingleton<CategoryRepository>(categoryRepo);

      final getCategoriesUseCase = GetCategoriesUseCase(categoryRepo);
      final addProductUseCase = AddProductUseCase(productRepo);
      final updateProductUseCase = UpdateProductUseCase(productRepo);

      productFormCubit = ProductFormCubit(
        addProductUseCase,
        updateProductUseCase,
        getCategoriesUseCase,
        productRepo,
      );
      getIt.registerFactory<ProductFormCubit>(() => productFormCubit);

      authCubit = _FakeAuthCubit(UserModel(
        id: 'u1',
        name: 'مشرف المطبخ',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      ));
      getIt.registerSingleton<AuthCubit>(authCubit);

      await categoryRepo.seedDefaultHospitalityCategories();
    });

    tearDown(() async {
      await db.close();
      await GetIt.instance.reset();
    });

    testWidgets('SimpleProductFormDialog loads existing recipeItems and preserves them on edit', (tester) async {
      tester.view.physicalSize = const Size(1280, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Create a meal that already has recipeItems
      final initialRecipe = [
        const RecipeItemData(
          rawMaterialId: 'raw-beef-1',
          rawMaterialName: 'لحم بقري مفروم',
          quantityNeeded: 200,
          yieldLossPercentage: 15,
          unit: 'جرام',
        ),
      ];

      final existingMeal = ProductEntity(
        id: 'meal-burger-1',
        name: 'برجر كلاسيك سينجل',
        categoryId: 'cat_hosp_meals',
        categoryName: 'وجبات ومأكولات سريعة',
        description: RestaurantCulinaryData(
          ingredients: 'لحم بقري، كيزر، صوص',
          calories: 650,
          prepTimeMinutes: 12,
          recipeItems: initialRecipe,
          mealStockMode: 'onDemand',
        ).toEncodedString(),
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );

      productRepo.savedProducts.add(existingMeal);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: Scaffold(
              body: SimpleProductFormDialog(
                product: existingMeal,
                initialActivityType: ActivityType.restaurantsCafes,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that culinary profile card rendered with initial recipe item
      expect(find.byKey(const Key('culinary_profile_card')), findsOneWidget);
      expect(find.text('لحم بقري مفروم'), findsOneWidget);
      expect(find.text('200 جرام'), findsOneWidget);

      // Now tap the save button to verify no data loss on edit
      final saveBtn = find.byKey(const Key('simple_product_save_btn'));
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify productRepo received updated product with preserved recipeItems
      expect(productRepo.lastUpdatedProduct, isNotNull);
      final updatedDesc = productRepo.lastUpdatedProduct!.description;
      final updatedCul = RestaurantCulinaryData.parse(updatedDesc);
      expect(updatedCul.recipeItems.length, 1);
      expect(updatedCul.recipeItems.first.rawMaterialName, 'لحم بقري مفروم');
      expect(updatedCul.recipeItems.first.quantityNeeded, 200);
      expect(updatedCul.recipeItems.first.yieldLossPercentage, 15);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('SimpleProductFormDialog saves newly added product with recipeItems', (tester) async {
      tester.view.physicalSize = const Size(1280, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Seed a raw material in the database so it appears in add recipe item dialog
      final now = DateTime.now();
      await db.into(db.products).insert(
            ProductsCompanion(
              id: const drift.Value('raw-cheese-1'),
              branchId: const drift.Value('branch-1'),
              name: const drift.Value('جبن شيدر طبيعي'),
              categoryId: const drift.Value('cat_hosp_raw'),
              activityType: const drift.Value('restaurantsCafes'),
              description: drift.Value(
                RestaurantCulinaryData(
                  isRawMaterial: true,
                  baseUnit: 'شريحة',
                  purchaseUnit: 'قالب 1 كجم',
                  conversionFactor: 50,
                ).toEncodedString(),
              ),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const Scaffold(
              body: SimpleProductFormDialog(
                initialActivityType: ActivityType.restaurantsCafes,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter product name
      final nameField = find.widgetWithText(TextFormField, 'اسم الصنف / المنتج *');
      await tester.enterText(nameField, 'وجبة شيدر برجر جديد');

      // Enter cost and sell price
      final costField = find.widgetWithText(TextFormField, 'سعر التكلفة (ج.م) *');
      await tester.enterText(costField, '45');
      final sellField = find.widgetWithText(TextFormField, 'سعر البيع قطاعي (ج.م) *');
      await tester.enterText(sellField, '95');

      // Scroll down to culinary profile card and tap Add Recipe Item button
      final addRecipeBtn = find.byKey(const Key('add_recipe_item_btn'));
      expect(addRecipeBtn, findsOneWidget);
      await tester.ensureVisible(addRecipeBtn);
      await tester.tap(addRecipeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog opens
      expect(find.byKey(const Key('add_recipe_item_dialog')), findsOneWidget);

      // Fill recipe qty
      final qtyInput = find.byKey(const Key('recipe_item_qty_field'));
      await tester.enterText(qtyInput, '2');

      // Confirm add
      final confirmBtn = find.byKey(const Key('confirm_add_recipe_item_btn'));
      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify item now in list
      expect(find.text('جبن شيدر طبيعي'), findsOneWidget);
      expect(find.text('2 شريحة'), findsOneWidget);

      // Now save the product
      final saveBtn = find.byKey(const Key('simple_product_save_btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify saved in productRepo
      expect(productRepo.savedProducts.isNotEmpty, isTrue);
      final saved = productRepo.savedProducts.firstWhere((p) => p.name == 'وجبة شيدر برجر جديد');
      final cul = RestaurantCulinaryData.parse(saved.description);
      expect(cul.recipeItems.length, 1);
      expect(cul.recipeItems.first.rawMaterialName, 'جبن شيدر طبيعي');
      expect(cul.recipeItems.first.quantityNeeded, 2);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('SimpleProductFormDialog automatically recalculates cost price when recipe items are added', (tester) async {
      tester.view.physicalSize = const Size(1280, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Seed raw material with variant cost in database
      final now = DateTime.now();
      await db.into(db.products).insert(
            ProductsCompanion(
              id: const drift.Value('raw-meat-5'),
              branchId: const drift.Value('branch-1'),
              name: const drift.Value('لحم برجر مفروم'),
              categoryId: const drift.Value('cat_hosp_raw'),
              activityType: const drift.Value('restaurantsCafes'),
              description: drift.Value(
                RestaurantCulinaryData(
                  isRawMaterial: true,
                  baseUnit: 'جرام',
                  purchaseUnit: 'كيلو',
                  conversionFactor: 1000,
                ).toEncodedString(),
              ),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

      // Cost 40000 piasters (400 LE) for 1000g -> 40 piasters / gram
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion(
              id: const drift.Value('var-meat-5'),
              branchId: const drift.Value('branch-1'),
              productId: const drift.Value('raw-meat-5'),
              sku: const drift.Value('RAW-MEAT-5'),
              color: const drift.Value('-'),
              size: const drift.Value('كيلو'),
              costPrice: const drift.Value(40000),
              sellPrice: const drift.Value(50000),
              quantity: const drift.Value(5000),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const Scaffold(
              body: SimpleProductFormDialog(
                initialActivityType: ActivityType.restaurantsCafes,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final costField = find.widgetWithText(TextFormField, 'سعر التكلفة (ج.م) *');
      expect(costField, findsOneWidget);

      // Tap add recipe item
      final addRecipeBtn = find.byKey(const Key('add_recipe_item_btn'));
      await tester.ensureVisible(addRecipeBtn);
      await tester.tap(addRecipeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter 150 grams
      final qtyInput = find.byKey(const Key('recipe_item_qty_field'));
      await tester.enterText(qtyInput, '150');

      // Confirm
      final confirmBtn = find.byKey(const Key('confirm_add_recipe_item_btn'));
      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 150g * 40 piasters = 6000 piasters = 60.00 LE
      expect(find.text('60.00'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
