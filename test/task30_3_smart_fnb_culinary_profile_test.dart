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
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/services/kitchen_order_ticket_service.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
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
  final List<VariantInput> savedVariants = [];

  @override
  Future<Either<Failure, String>> addProductWithVariants(
      ProductEntity product, List<VariantInput> variants) async {
    savedProducts.add(product);
    savedVariants.addAll(variants);
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

  group('Addendum 30.3: Culinary Data Modeling & JSON Serialization', () {
    test('RestaurantCulinaryData serializes and parses safely', () {
      const data = RestaurantCulinaryData(
        ingredients: 'لحم بقري 150جم، صوص مشروم، جبنة شيدر',
        calories: 620,
        allergens: ['جلوتين / قمح', 'لاكتوز / حليب'],
        prepTimeMinutes: 15,
        kitchenStation: 'مطبخ ساخن (وجبات وجريل)',
        userDescription: 'وجبة مميزة خاصة بالشيف',
      );

      final encoded = data.toEncodedString();
      expect(encoded.startsWith('{'), isTrue);

      final decoded = RestaurantCulinaryData.parse(encoded);
      expect(decoded.ingredients, equals('لحم بقري 150جم، صوص مشروم، جبنة شيدر'));
      expect(decoded.calories, equals(620));
      expect(decoded.allergens, equals(['جلوتين / قمح', 'لاكتوز / حليب']));
      expect(decoded.prepTimeMinutes, equals(15));
      expect(decoded.kitchenStation, equals('مطبخ ساخن (وجبات وجريل)'));
      expect(decoded.userDescription, equals('وجبة مميزة خاصة بالشيف'));
    });

    test('ProductEntity getters seamlessly extract culinary data from description', () {
      const culinary = RestaurantCulinaryData(
        ingredients: 'دجاج متبل، خبز، بطاطس',
        calories: 520,
        allergens: ['بيض', 'سمسم'],
        prepTimeMinutes: 12,
        kitchenStation: 'فرن وبيتزا',
        userDescription: 'ساندوتش دجاج كرسبي',
      );

      final product = ProductEntity(
        id: 'p_101',
        name: 'ساندوتش كرسبي',
        categoryId: 'c_1',
        categoryName: 'وجبات',
        createdAt: DateTime.now(),
        description: culinary.toEncodedString(),
        activityType: 'restaurantsCafes',
      );

      expect(product.ingredients, equals('دجاج متبل، خبز، بطاطس'));
      expect(product.calories, equals(520));
      expect(product.allergens, containsAll(['بيض', 'سمسم']));
      expect(product.prepTimeMinutes, equals(12));
      expect(product.kitchenStation, equals('فرن وبيتزا'));
      expect(product.cleanDescription, equals('ساندوتش دجاج كرسبي'));
    });

    test('ProductEntity cleanDescription falls back safely for legacy descriptions', () {
      final legacyProduct = ProductEntity(
        id: 'p_102',
        name: 'عصير برتقال فريش',
        categoryId: 'c_2',
        categoryName: 'مشروبات',
        createdAt: DateTime.now(),
        description: 'برتقال طبيعي معصور بدون سكر',
        activityType: 'restaurantsCafes',
      );

      expect(legacyProduct.ingredients, isNull);
      expect(legacyProduct.calories, isNull);
      expect(legacyProduct.allergens, isEmpty);
      expect(legacyProduct.prepTimeMinutes, isNull);
      expect(legacyProduct.kitchenStation, isNull);
      expect(legacyProduct.cleanDescription, equals('برتقال طبيعي معصور بدون سكر'));
    });
  });

  group('Addendum 30.3: KitchenOrderTicketService Profile Integration', () {
    test('KOT ticket includes preparation time, kitchen station, and allergen alerts', () {
      final product1 = ProductEntity(
        id: 'prod_burger',
        name: 'برجر دبل تشيز',
        categoryId: 'c_fastfood',
        categoryName: 'وجبات',
        createdAt: DateTime.now(),
        activityType: 'restaurantsCafes',
        description: const RestaurantCulinaryData(
          ingredients: 'لحم بقري، شيدر، بصل مكرمل',
          calories: 780,
          allergens: ['جلوتين / قمح', 'لاكتوز / حليب'],
          prepTimeMinutes: 15,
          kitchenStation: 'مطبخ ساخن (وجبات وجريل)',
        ).toEncodedString(),
      );

      final product2 = ProductEntity(
        id: 'prod_juice',
        name: 'موهيتو ليمون نعناع',
        categoryId: 'c_drinks',
        categoryName: 'مشروبات',
        createdAt: DateTime.now(),
        activityType: 'restaurantsCafes',
        description: const RestaurantCulinaryData(
          ingredients: 'ليمون، صودا، نعناع طازج',
          calories: 140,
          allergens: [],
          prepTimeMinutes: 5,
          kitchenStation: 'بار المشروبات والعصائر',
        ).toEncodedString(),
      );

      final items = [
        const SaleItemEntity(
          variantId: 'v_1',
          productId: 'prod_burger',
          productName: 'برجر دبل تشيز',
          size: '-',
          color: '-',
          price: 15000,
          quantity: 2,
          kitchenNotes: 'بدون بصل',
        ),
        const SaleItemEntity(
          variantId: 'v_2',
          productId: 'prod_juice',
          productName: 'موهيتو ليمون نعناع',
          size: '-',
          color: '-',
          price: 4500,
          quantity: 1,
        ),
      ];

      final ticket = KitchenOrderTicketService.generateKitchenOrderTicket(
        orderType: 'dineIn',
        tableNumber: '7',
        invoiceNumber: 'KOT-8899',
        date: DateTime(2026, 11, 23, 20, 30),
        items: items,
        cashierName: 'محمد الكاشير',
        productMap: {
          'prod_burger': product1,
          'prod_juice': product2,
        },
      );

      // Verify Order Meta Section
      expect(ticket, contains('محطة التحضير : مطبخ ساخن (وجبات وجريل) - بار المشروبات والعصائر'));
      expect(ticket, contains('وقت التحضير   : 15 دقيقة (تقديري)'));
      expect(ticket, contains('تنبيه حساسية  : جلوتين / قمح، لاكتوز / حليب'));

      // Verify Item Details
      expect(ticket, contains('1. [ 2 x ] برجر دبل تشيز'));
      expect(ticket, contains('محطة التحضير: مطبخ ساخن (وجبات وجريل)'));
      expect(ticket, contains('وقت التجهيز: 15 دقيقة'));
      expect(ticket, contains('تحذير حساسية: جلوتين / قمح، لاكتوز / حليب'));
      expect(ticket, contains('استثناءات: بدون بصل'));

      expect(ticket, contains('2. [ 1 x ] موهيتو ليمون نعناع'));
      expect(ticket, contains('محطة التحضير: بار المشروبات والعصائر'));
      expect(ticket, contains('وقت التجهيز: 5 دقيقة'));
    });
  });

  group('Addendum 30.3: SimpleProductFormDialog Culinary Profile UI', () {
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

      // Seed default hospitality categories
      await categoryRepo.seedDefaultHospitalityCategories();
    });

    tearDown(() async {
      await db.close();
      await GetIt.instance.reset();
    });

    testWidgets('SimpleProductFormDialog shows CulinaryProfileCard and saves culinary profile', (tester) async {
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

      // Culinary profile card must be visible
      expect(find.byKey(const Key('culinary_profile_card')), findsOneWidget);
      expect(find.text('بطاقة بيانات وتحضير الوجبة (القيم الغذائية والمطبخ)'), findsOneWidget);

      // Fill in meal name
      final nameField = find.widgetWithText(TextFormField, 'اسم الصنف / المنتج *');
      await tester.enterText(nameField, 'وجبة برجر سبيشال');

      // Fill in ingredients
      final ingredientsField = find.byKey(const Key('culinary_ingredients_field'));
      expect(ingredientsField, findsOneWidget);
      await tester.enterText(ingredientsField, 'لحم بقري 150جم، صوص مشروم، جبنة شيدر');

      // Fill in calories
      final caloriesField = find.byKey(const Key('culinary_calories_field'));
      expect(caloriesField, findsOneWidget);
      await tester.enterText(caloriesField, '650');

      // Quick prep time chip: 15 دقائق
      final chip15 = find.byKey(const Key('prep_time_chip_15'));
      expect(chip15, findsOneWidget);
      await tester.tap(chip15);
      await tester.pump();

      final prepTimeField = find.byKey(const Key('culinary_prep_time_field'));
      expect(find.descendant(of: prepTimeField, matching: find.text('15')), findsOneWidget);

      // Scroll to allergen chips
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -250));
      await tester.pumpAndSettle();

      // Select allergen chip: جلوتين / قمح
      final glutenChip = find.byKey(const Key('allergen_chip_جلوتين / قمح'));
      expect(glutenChip, findsOneWidget);
      await tester.tap(glutenChip);
      await tester.pump();

      // Enter price
      final sellField = find.widgetWithText(TextFormField, 'سعر البيع قطاعي (ج.م) *');
      await tester.enterText(sellField, '120');

      // Save
      final saveBtn = find.byKey(const Key('simple_product_save_btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify product was saved with encoded culinary JSON
      expect(productRepo.savedProducts.length, equals(1));
      final saved = productRepo.savedProducts.first;
      expect(saved.name, equals('وجبة برجر سبيشال'));
      expect(saved.ingredients, equals('لحم بقري 150جم، صوص مشروم، جبنة شيدر'));
      expect(saved.calories, equals(650));
      expect(saved.prepTimeMinutes, equals(15));
      expect(saved.allergens, contains('جلوتين / قمح'));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('Addendum 30.3: POS Screen Calorie Badge & Meal Info Dialog', () {
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

      // Add a product with culinary info
      const culinary = RestaurantCulinaryData(
        ingredients: 'دجاج زنجر حار، مايونيز، خس',
        calories: 520,
        allergens: ['بيض', 'سمسم'],
        prepTimeMinutes: 10,
        kitchenStation: 'مطبخ ساخن (وجبات وجريل)',
      );

      final prod = ProductEntity(
        id: 'p_zinger',
        name: 'زنجر حار سوبريم',
        categoryId: 'cat_fnb',
        categoryName: 'وجبات',
        createdAt: DateTime.now(),
        activityType: 'restaurantsCafes',
        description: culinary.toEncodedString(),
      );
      productRepo.savedProducts.add(prod);

      final variant = VariantEntity(
        id: 'var_zinger',
        productId: 'p_zinger',
        productName: 'زنجر حار سوبريم',
        productCode: 'ZING-01',
        color: '-',
        size: '-',
        costPrice: 5000,
        salePrice: 9500,
        quantity: 50,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      variantRepo.variants.add(variant);

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

    testWidgets('POS screen shows calorie badge and clicking info button displays dialog', (tester) async {
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

      // Calorie badge must be visible on the product card
      final calorieBadge = find.byKey(const Key('product_calorie_badge_p_zinger'));
      expect(calorieBadge, findsOneWidget);
      expect(find.descendant(of: calorieBadge, matching: find.text('520 kcal')), findsOneWidget);

      // Info button must be visible
      final infoBtn = find.byKey(const Key('product_culinary_info_btn_p_zinger'));
      expect(infoBtn, findsOneWidget);

      // Tap info button
      await tester.tap(infoBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Culinary info dialog must be open
      expect(find.byKey(const Key('culinary_info_dialog')), findsOneWidget);
      expect(find.text('بيانات الوجبة: زنجر حار سوبريم'), findsOneWidget);
      expect(find.text('دجاج زنجر حار، مايونيز، خس'), findsOneWidget);
      expect(find.text('السعرات الحرارية: 520 kcal'), findsOneWidget);
      expect(find.text('وقت التحضير: 10 دقيقة'), findsOneWidget);
      expect(find.text('محطة المطبخ: مطخ ساخن (وجبات وجريل)'), findsNothing); // sanity check
      expect(find.text('محطة المطبخ: مطبخ ساخن (وجبات وجريل)'), findsOneWidget);
      expect(find.text('بيض'), findsOneWidget);
      expect(find.text('سمسم'), findsOneWidget);

      // Close dialog
      final closeBtn = find.text('إغلاق');
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
