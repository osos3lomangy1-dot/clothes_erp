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
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_form_screen.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
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
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      Right(savedProducts);

  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() =>
      Stream.value(Right(savedProducts));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeBranchProvider branchProvider;
  late TxWriter txWriter;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late _FakeAuthLocalDataSource authLocalDs;
  late CategoryLocalDataSource categoryLocalDataSource;
  late CategoryRepositoryImpl categoryRepository;
  late _MockProductRepo mockProductRepo;
  late UserModel testAdminUser;
  late _FakeAuthCubit authCubit;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    branchProvider = _FakeBranchProvider();
    txWriter = TxWriter(db);
    authLocalDs = _FakeAuthLocalDataSource();
    featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    activityService = ActivitySettingsService(db, featureGate);
    categoryLocalDataSource = CategoryLocalDataSource(db, branchProvider);
    categoryRepository = CategoryRepositoryImpl(categoryLocalDataSource);
    mockProductRepo = _MockProductRepo();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<BranchProvider>(branchProvider);
    sl.registerSingleton<TxWriter>(txWriter);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<CategoryLocalDataSource>(categoryLocalDataSource);
    sl.registerSingleton<CategoryRepository>(categoryRepository);
    sl.registerSingleton<ProductRepository>(mockProductRepo);

    sl.registerFactory<ProductFormCubit>(() => ProductFormCubit(
          AddProductUseCase(mockProductRepo),
          UpdateProductUseCase(mockProductRepo),
          GetCategoriesUseCase(categoryRepository),
          mockProductRepo,
        ));

    testAdminUser = UserModel(
      id: 'admin_1',
      name: 'مدير النظام',
      email: 'admin@system.local',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    await authLocalDs.cacheUser(testAdminUser);
    authCubit = _FakeAuthCubit(testAdminUser);

    // Apply hospitality preset
    await activityService.applyStorePreset(
      StorePreset.hospitality,
      userId: 'admin_1',
    );
    await activityService.getEnabledActivities();
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 30.1: Default Hospitality Categories Auto-Seeding', () {
    test('seedDefaultHospitalityCategories seeds all 5 basic F&B categories', () async {
      final res = await categoryRepository.seedDefaultHospitalityCategories();
      expect(res.isRight(), isTrue);

      final categories = res.getOrElse(() => []);
      expect(categories.length, equals(5));

      final names = categories.map((c) => c.name).toList();
      expect(names, contains('وجبات وساندوتشات'));
      expect(names, contains('مشروبات وعصائر'));
      expect(names, contains('بيتزا وفطائر'));
      expect(names, contains('مقبلات وإضافات'));
      expect(names, contains('حلويات ومخبوزات'));
    });

    test('getCategories automatically seeds hospitality categories when empty and restaurants activity is active', () async {
      final initialRows = await categoryLocalDataSource.getCategories();
      expect(initialRows, isEmpty);

      final result = await categoryRepository.getCategories();
      expect(result.isRight(), isTrue);

      final categories = result.getOrElse(() => []);
      expect(categories.length, equals(5));
      expect(categories.first.name, equals('وجبات وساندوتشات'));
    });
  });

  group('Task 30.1: ProductFormScreen Effortless Restaurant Items Creation', () {
    testWidgets('Renders quick add category button and restaurant visual hints', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<ProductFormCubit>(
                create: (_) => GetIt.instance<ProductFormCubit>()..init(null),
              ),
            ],
            child: const ProductFormScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check for quick category button
      expect(find.byKey(const Key('add_category_quick_btn')), findsOneWidget);
      expect(find.text('قسم جديد'), findsOneWidget);

      // Verify restaurant hints & icons
      expect(find.byIcon(Icons.restaurant_menu_rounded), findsWidgets);
      expect(find.text('مثال: برجر دبل تشيز / بيتزا مارجريتا / كابتشينو'), findsOneWidget);
      expect(find.text('الباركود / كود المنتج (SKU) (اختياري)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Submitting restaurant meal without entering barcode generates REST-... SKU and 999 quantity', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<ProductFormCubit>(
                create: (_) => GetIt.instance<ProductFormCubit>()..init(null),
              ),
            ],
            child: const ProductFormScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Enter Meal Name
      final nameField = find.widgetWithText(TextFormField, 'اسم المنتج *');
      await tester.enterText(nameField, 'برجر دبل تشيز');
      await tester.pump();

      // Clear SKU to test auto-generating barcode without writing barcode
      final skuField = find.widgetWithText(TextFormField, 'الباركود / كود المنتج (SKU) (اختياري)');
      await tester.enterText(skuField, '');
      await tester.pump();

      // Submit Form
      final saveBtn = find.byKey(const Key('product_form_save_btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify saved product & variant in mock repo
      expect(mockProductRepo.savedProducts.length, equals(1));
      expect(mockProductRepo.savedProducts.first.name, equals('برجر دبل تشيز'));
      expect(mockProductRepo.savedProducts.first.activityType, equals('restaurantsCafes'));

      expect(mockProductRepo.savedVariants.length, equals(1));
      final savedVariant = mockProductRepo.savedVariants.first;
      expect(savedVariant.sku, startsWith('REST-'));
      expect(savedVariant.quantity, equals(999));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 30.1: SimpleProductFormDialog Restaurant Automation', () {
    testWidgets('SimpleProductFormDialog initializes with 999 qty, REST SKU, and auto-selected first category', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const SimpleProductFormDialog(
                initialActivityType: ActivityType.restaurantsCafes,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify F&B visual hints
      expect(find.byIcon(Icons.restaurant_menu_rounded), findsWidgets);
      expect(find.text('مثال: برجر دبل تشيز / بيتزا مارجريتا / كابتشينو'), findsOneWidget);
      expect(find.text('الباركود / الكود (SKU) (اختياري)'), findsOneWidget);

      // Verify default quantity is 999
      expect(find.text('999'), findsOneWidget);

      // Verify SKU text field is prefilled with REST-
      final skuField = find.widgetWithText(TextFormField, 'الباركود / الكود (SKU) (اختياري)');
      final skuWidget = tester.widget<TextFormField>(skuField);
      expect(skuWidget.controller?.text, startsWith('REST-'));

      // Enter Meal Name & Sell Price
      final nameField = find.widgetWithText(TextFormField, 'اسم الصنف / المنتج *');
      await tester.enterText(nameField, 'كابتشينو كراميل');
      await tester.pump();

      final sellPriceField = find.widgetWithText(TextFormField, 'سعر البيع قطاعي (ج.م) *');
      await tester.enterText(sellPriceField, '65.00');
      await tester.pump();

      // Tap Save button
      final saveBtn = find.byKey(const Key('simple_product_save_btn'));
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify saved in mock repo
      expect(mockProductRepo.savedProducts.any((p) => p.name == 'كابتشينو كراميل'), isTrue);
      final variant = mockProductRepo.savedVariants.firstWhere((v) => v.sku.startsWith('REST-'));
      expect(variant.quantity, equals(999));
      expect(variant.sellPrice, equals(6500)); // 65.00 * 100 piasters

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
