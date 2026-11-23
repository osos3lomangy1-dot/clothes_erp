import 'dart:convert';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/hotkey_strip_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/domain/models/cashier_permissions_config.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/services/cashier_permissions_service.dart';
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';
import 'package:clothes_erp/features/categories/data/repositories/category_repository_impl.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/widgets/culinary_profile_card.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:dartz/dartz.dart';
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
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProductRepo implements ProductRepository {
  final List<ProductEntity> savedProducts = [];

  @override
  Future<Either<Failure, String>> addProductWithVariants(
      ProductEntity product, dynamic variants) async {
    savedProducts.add(product);
    return Right(product.id.isEmpty ? 'prod_1' : product.id);
  }

  @override
  Future<Either<Failure, Unit>> updateProduct(ProductEntity product) async {
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
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() =>
      Stream.value(Right(savedProducts));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepo implements VariantRepository {
  List<VariantEntity> variants = [];
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(Right(variants));
  @override
  Future<Either<Failure, List<VariantEntity>>> getVariants(
          String productId) async =>
      Right(variants.where((v) => v.productId == productId).toList());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShiftCubit extends Cubit<ShiftState> implements ShiftCubit {
  _FakeShiftCubit()
      : super(const ShiftState(shiftsEnabled: false, status: ShiftStatus.loaded));
  @override
  Future<void> loadShiftData() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Task 30.4: RestaurantCulinaryData Image Modeling Tests', () {
    test('serializes and deserializes imagePath accurately', () {
      const culinary = RestaurantCulinaryData(
        ingredients: 'لحم بقري، خس، صوص خاص',
        calories: 620,
        prepTimeMinutes: 12,
        kitchenStation: 'مطبخ ساخن (وجبات وجريل)',
        imagePath: 'C:/assets/food/burger.png',
      );

      final json = culinary.toJson();
      expect(json['imagePath'], 'C:/assets/food/burger.png');
      expect(json['calories'], 620);

      final decoded = RestaurantCulinaryData.fromJson(json);
      expect(decoded.imagePath, 'C:/assets/food/burger.png');
      expect(decoded.ingredients, 'لحم بقري، خس، صوص خاص');
      expect(decoded.calories, 620);
      expect(decoded.hasCulinaryInfo, isTrue);
      expect(decoded.isEmpty, isFalse);
    });

    test('imagePath alone marks hasCulinaryInfo as true', () {
      const culinary = RestaurantCulinaryData(
        imagePath: '/images/pizza.jpg',
      );
      expect(culinary.hasCulinaryInfo, isTrue);
      expect(culinary.isEmpty, isFalse);
      expect(culinary.toJson()['imagePath'], '/images/pizza.jpg');
    });

    test('copyWith properly updates imagePath', () {
      const culinary = RestaurantCulinaryData(calories: 400);
      final updated = culinary.copyWith(imagePath: '/photos/salad.png');
      expect(updated.imagePath, '/photos/salad.png');
      expect(updated.calories, 400);
    });

    test('ProductEntity exposes foodImagePath getter', () {
      const culinary = RestaurantCulinaryData(
        imagePath: '/images/shawarma.jpg',
        calories: 550,
      );

      final product = ProductEntity(
        id: 'prod_shawarma',
        name: 'شاورما لحم',
        description: culinary.toEncodedString(),
        categoryId: 'cat_meals',
        categoryName: 'وجبات',
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );

      expect(product.foodImagePath, '/images/shawarma.jpg');
      expect(product.calories, 550);
      expect(product.activityTypeEnum, ActivityType.restaurantsCafes);
    });
  });

  group('Task 30.4: PosCubit Kitchen Notes & Modifiers Cart Tests', () {
    late PosCubit posCubit;
    late _MockProductRepo mockProductRepo;
    late _FakeVariantRepo mockVariantRepo;
    late CategoryRepository categoryRepo;

    final testVariant = VariantEntity(
      id: 'var_burger_1',
      productId: 'prod_burger_1',
      productName: 'برجر كلاسيك',
      productCode: 'BURGER-1',
      size: 'عادي',
      color: 'أساسي',
      costPrice: 5000,
      salePrice: 12000,
      quantity: 50,
      minStock: 5,
      createdAt: DateTime.now(),
    );

    setUp(() async {
      mockProductRepo = _MockProductRepo();
      mockVariantRepo = _FakeVariantRepo();
      final db = AppDatabase(NativeDatabase.memory());
      final branchProvider = _FakeBranchProvider();
      final catLocalDs = CategoryLocalDataSource(db, branchProvider);
      categoryRepo = CategoryRepositoryImpl(catLocalDs);

      posCubit = PosCubit(
        CreateSaleUseCase(_FakePosRepo()),
        mockVariantRepo,
        categoryRepo,
        mockProductRepo,
        _FakePosRepo(),
      );
    });

    tearDown(() {
      posCubit.close();
    });

    test('addToCart adds meal with kitchenNotes and modifiers', () {
      posCubit.addToCart(
        testVariant,
        1,
        'بدون بصل - سبايسي',
        ['بدون بصل', 'سبايسي'],
      );

      expect(posCubit.state.cart.length, 1);
      final item = posCubit.state.cart.first;
      expect(item.variantId, 'var_burger_1');
      expect(item.quantity, 1);
      expect(item.kitchenNotes, 'بدون بصل - سبايسي');
      expect(item.modifiers, ['بدون بصل', 'سبايسي']);
    });

    test('addToCart with identical notes combines quantity', () {
      posCubit.addToCart(
        testVariant,
        1,
        'بدون بصل',
        ['بدون بصل'],
      );
      posCubit.addToCart(
        testVariant,
        2,
        'بدون بصل',
        ['بدون بصل'],
      );

      expect(posCubit.state.cart.length, 1);
      expect(posCubit.state.cart.first.quantity, 3);
      expect(posCubit.state.cart.first.kitchenNotes, 'بدون بصل');
    });

    test('addToCart with different notes creates distinct cart line items', () {
      posCubit.addToCart(
        testVariant,
        1,
        'بدون بصل',
        ['بدون بصل'],
      );
      posCubit.addToCart(
        testVariant,
        1,
        'زيادة جبنة',
        ['زيادة جبنة'],
      );

      expect(posCubit.state.cart.length, 2);
      expect(posCubit.state.cart[0].kitchenNotes, 'بدون بصل');
      expect(posCubit.state.cart[1].kitchenNotes, 'زيادة جبنة');
    });
  });

  group('Task 30.4: CulinaryProfileCard Image Selector Widget Tests', () {
    testWidgets('renders photo picker row and handles remove callback', (tester) async {
      String? currentImagePath = '/path/to/meal.png';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return CulinaryProfileCard(
                    ingredientsController: TextEditingController(),
                    caloriesController: TextEditingController(),
                    prepTimeController: TextEditingController(),
                    selectedAllergens: const {},
                    selectedKitchenStation: null,
                    imagePath: currentImagePath,
                    onImagePathChanged: (newPath) {
                      setState(() {
                        currentImagePath = newPath;
                      });
                    },
                    onKitchenStationChanged: (_) {},
                    onAllergenToggled: (_, _) {},
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('culinary_profile_card')), findsOneWidget);
      expect(find.byKey(const Key('pick_culinary_image_btn')), findsOneWidget);
      expect(find.byKey(const Key('remove_culinary_image_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove_culinary_image_btn')));
      await tester.pumpAndSettle();

      expect(currentImagePath, isNull);
      expect(find.byKey(const Key('remove_culinary_image_btn')), findsNothing);
    });
  });

  group('Task 30.4: SimpleProductFormDialog with Culinary Profile', () {
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
        name: 'مشرف النظام',
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

    testWidgets('SimpleProductFormDialog saves culinary profile details', (tester) async {
      tester.view.physicalSize = const Size(1280, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      expect(find.byKey(const Key('culinary_profile_card')), findsOneWidget);

      final nameField = find.widgetWithText(TextFormField, 'اسم الصنف / المنتج *');
      await tester.enterText(nameField, 'وجبة سموك برجر');

      final ingredientsField = find.byKey(const Key('culinary_ingredients_field'));
      expect(ingredientsField, findsOneWidget);
      await tester.enterText(ingredientsField, 'لحم بقري مدخن، صوص باربكيو، جبنة شيدر');

      final caloriesField = find.byKey(const Key('culinary_calories_field'));
      expect(caloriesField, findsOneWidget);
      await tester.enterText(caloriesField, '750');

      final chip15 = find.byKey(const Key('prep_time_chip_15'));
      expect(chip15, findsOneWidget);
      await tester.tap(chip15);
      await tester.pump();

      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -250));
      await tester.pumpAndSettle();

      final sellField = find.widgetWithText(TextFormField, 'سعر البيع قطاعي (ج.م) *');
      await tester.enterText(sellField, '145');

      final saveBtn = find.byKey(const Key('simple_product_save_btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(productRepo.savedProducts.length, equals(1));
      final saved = productRepo.savedProducts.first;
      expect(saved.name, equals('وجبة سموك برجر'));
      expect(saved.ingredients, equals('لحم بقري مدخن، صوص باربكيو، جبنة شيدر'));
      expect(saved.calories, equals(750));
      expect(saved.prepTimeMinutes, equals(15));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('Task 30.4: Visual POS Card & Instant Meal Customizer Modal', () {
    late AppDatabase db;
    late FeatureGate featureGate;
    late ActivitySettingsService activityService;
    late _MockProductRepo productRepo;
    late _FakeVariantRepo variantRepo;
    late CategoryRepository categoryRepo;
    late AuthCubit authCubit;
    late ShiftCubit shiftCubit;
    late PosCubit posCubit;

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
      variantRepo = _FakeVariantRepo();

      final categoryLocalDataSource = CategoryLocalDataSource(db, branchProvider);
      categoryRepo = CategoryRepositoryImpl(categoryLocalDataSource);

      getIt.registerSingleton<AppDatabase>(db);
      getIt.registerSingleton<FeatureGate>(featureGate);
      getIt.registerSingleton<ActivitySettingsService>(activityService);
      getIt.registerSingleton<ProductRepository>(productRepo);
      getIt.registerSingleton<VariantRepository>(variantRepo);
      getIt.registerSingleton<CategoryRepository>(categoryRepo);
      getIt.registerSingleton<PosRepository>(_FakePosRepo());
      getIt.registerSingleton<ShortcutSettingsService>(ShortcutSettingsService(db));

      AppBranding.apply(AppBrandingConfig.defaults);
      CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
      HotkeyStripService.isVisible.value = true;

      const culinary = RestaurantCulinaryData(
        ingredients: 'شريحتي لحم، جبنة، خس، طماطم',
        calories: 850,
        prepTimeMinutes: 10,
        kitchenStation: 'مطبخ ساخن (وجبات وجريل)',
      );

      final restaurantProduct = ProductEntity(
        id: 'prod_fnb_1',
        name: 'تشيز برجر دبل',
        description: culinary.toEncodedString(),
        categoryId: 'cat_fnb',
        categoryName: 'برجر ووجبات',
        activityType: 'restaurantsCafes',
        createdAt: DateTime.now(),
      );
      productRepo.savedProducts.add(restaurantProduct);

      final restaurantVariant = VariantEntity(
        id: 'var_fnb_1',
        productId: 'prod_fnb_1',
        productName: 'تشيز برجر دبل',
        productCode: 'REST-001',
        size: 'عادي',
        color: 'أساسي',
        costPrice: 6000,
        salePrice: 15000,
        quantity: 999,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      variantRepo.variants.add(restaurantVariant);

      authCubit = _FakeAuthCubit(UserModel(
        id: 'u1',
        name: 'كاشير المطعم',
        email: 'cashier@test.com',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      ));
      getIt.registerSingleton<AuthCubit>(authCubit);

      shiftCubit = _FakeShiftCubit();
      getIt.registerSingleton<ShiftCubit>(shiftCubit);

      posCubit = PosCubit(
        CreateSaleUseCase(_FakePosRepo()),
        variantRepo,
        categoryRepo,
        productRepo,
        _FakePosRepo(),
      );
      getIt.registerSingleton<PosCubit>(posCubit);
      await posCubit.init();
    });

    tearDown(() async {
      await db.close();
      await GetIt.instance.reset();
    });

    testWidgets('Displays visual food card with calories badge and opens customizer on tap', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<ShiftCubit>.value(value: shiftCubit),
              BlocProvider<PosCubit>.value(value: posCubit),
            ],
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify calories badge and meal title
      expect(find.text('تشيز برجر دبل'), findsWidgets);
      expect(find.byKey(const Key('product_calorie_badge_prod_fnb_1')), findsOneWidget);
      expect(find.text('850 kcal'), findsOneWidget);

      // Tap on the card to open instant meal customizer modal
      await tester.tap(find.text('تشيز برجر دبل').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify meal customizer modal opens
      expect(find.byKey(const Key('meal_customizer_modal')), findsOneWidget);
      expect(find.text('استثناءات المطبخ (بدون):'), findsOneWidget);
      expect(find.text('خيارات الطهي والإضافات:'), findsOneWidget);

      // Tap modifier pills: 'بدون بصل' and 'سبايسي'
      await tester.tap(find.byKey(const Key('modifier_pill_بدون بصل')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('modifier_pill_سبايسي')));
      await tester.pump();

      // Verify notes field was auto-populated with selected modifiers
      final notesField = tester.widget<TextFormField>(find.byKey(const Key('customizer_notes_field')));
      expect(notesField.controller?.text, contains('بدون بصل'));
      expect(notesField.controller?.text, contains('سبايسي'));

      // Increment quantity with stepper
      expect(find.byKey(const Key('customizer_qty_text')), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.byKey(const Key('customizer_qty_plus')));
      await tester.pump();
      expect(find.text('2'), findsWidgets);

      // Add to order
      expect(find.byKey(const Key('customizer_add_to_order_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('customizer_add_to_order_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal should dismiss
      expect(find.byKey(const Key('meal_customizer_modal')), findsNothing);

      // Pos cart should have item with quantity 2 and kitchen notes
      expect(posCubit.state.cart.length, 1);
      final item = posCubit.state.cart.first;
      expect(item.productName, 'تشيز برجر دبل');
      expect(item.quantity, 2);
      expect(item.kitchenNotes, contains('بدون بصل'));
      expect(item.kitchenNotes, contains('سبايسي'));
      expect(item.modifiers, contains('بدون بصل'));
      expect(item.modifiers, contains('سبايسي'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
