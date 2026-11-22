import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';
import 'package:clothes_erp/features/categories/data/repositories/category_repository_impl.dart';
import 'package:clothes_erp/features/categories/domain/usecases/delete_category_usecase.dart';
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_cubit.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/data/repositories/product_repository_impl.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/delete_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/widgets/rapid_barcode_intake_dialog.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late FeatureGate featureGate;
  late ProductLocalDataSource productDs;
  late VariantLocalDataSource variantDs;
  late CategoryLocalDataSource categoryDs;
  late ProductRepository productRepo;
  late ProductFormCubit productFormCubit;
  late UserModel adminUser;
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    final authDs = _FakeAuthLocalDataSource();
    adminUser = UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'a@a.a',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    authDs.setUser(adminUser);

    final tx = TxWriter(db);
    final branch = BranchProvider(db);
    featureGate = FeatureGate(db, authDs, tx, branch);
    productDs = ProductLocalDataSource(db, branch, tx);
    variantDs = VariantLocalDataSource(db, branch, tx);
    categoryDs = CategoryLocalDataSource(db, branch);

    productRepo = ProductRepositoryImpl(productDs);
    final categoryRepo = CategoryRepositoryImpl(categoryDs);

    productFormCubit = ProductFormCubit(
      AddProductUseCase(productRepo),
      UpdateProductUseCase(productRepo),
      GetCategoriesUseCase(categoryRepo),
      productRepo,
      variantLocalDataSource: variantDs,
    );

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<FeatureGate>(featureGate);
    getIt.registerSingleton<ProductLocalDataSource>(productDs);
    getIt.registerSingleton<VariantLocalDataSource>(variantDs);
    getIt.registerSingleton<CategoryLocalDataSource>(categoryDs);
    getIt.registerSingleton<ProductRepository>(productRepo);
    getIt.registerSingleton<ProductFormCubit>(productFormCubit);
    getIt.registerFactory<CategoryCubit>(
      () => CategoryCubit(GetCategoriesUseCase(categoryRepo), DeleteCategoryUseCase(categoryRepo)),
    );
    getIt.registerFactory<ProductCubit>(
      () => ProductCubit(productRepo, DeleteProductUseCase(productRepo)),
    );

    // Seed default category
    await categoryDs.addCategory('عام');
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  group('Retail Sector Mode & Settings Tests', () {
    test('SettingsCubit loads sectorMode as apparel by default and updates correctly', () async {
      final cubit = SettingsCubit(featureGate);
      cubit.start();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.sectorMode, RetailSector.apparel);

      final err1 = await cubit.setSectorMode(RetailSector.supermarket, 'admin-1');
      expect(err1, isNull);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.sectorMode, RetailSector.supermarket);

      final err2 = await cubit.setSectorMode(RetailSector.houseware, 'admin-1');
      expect(err2, isNull);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.sectorMode, RetailSector.houseware);

      await cubit.close();
    });

    test('RetailSector helpers identify single product modes correctly', () {
      expect(RetailSector.isSingleProductMode(RetailSector.apparel), isFalse);
      expect(RetailSector.isSingleProductMode(RetailSector.supermarket), isTrue);
      expect(RetailSector.isSingleProductMode(RetailSector.houseware), isTrue);
    });

    testWidgets('SystemSettingsScreen renders _SectorModeSettingsCard with all 3 sectors',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      getIt.registerFactory<SettingsCubit>(() => SettingsCubit(featureGate));

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const SystemSettingsScreen(initialCategory: 'store'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تخصيص نمط النظام لنشاط المحل'), findsOneWidget);
      expect(find.text('ملابس وأحذية وأزياء'), findsOneWidget);
      expect(find.text('سوبر ماركت وبقالة'), findsOneWidget);
      expect(find.text('أدوات منزلية وتجارة عامة'), findsOneWidget);

      // Tap on Supermarket mode
      await tester.tap(find.byKey(const Key('sector_tile_supermarket')));
      await tester.pumpAndSettle();

      final currentMeta = await featureGate.getMeta(RetailSector.metaKey);
      expect(currentMeta, RetailSector.supermarket);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('SimpleProductFormDialog Tests (Housewares & Supermarket Single Item Mode)', () {
    testWidgets('creates a simple product with single shadow variant (no sizes/colors needed)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const Scaffold(
                body: SimpleProductFormDialog(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إضافة صنف جديد (منتج مفرد)'), findsOneWidget);

      // Enter product name
      final nameField = find.widgetWithText(TextFormField, 'اسم الصنف / المنتج *');
      await tester.enterText(nameField, 'طقم حلل جرانيت 10 قطع');

      // Enter cost price (e.g. 1500 EGP)
      final costField = find.widgetWithText(TextFormField, 'سعر التكلفة (ج.م) *');
      await tester.enterText(costField, '1500');

      // Enter sell price (e.g. 2100 EGP)
      final sellField = find.widgetWithText(TextFormField, 'سعر البيع قطاعي (ج.م) *');
      await tester.enterText(sellField, '2100');

      // Enter quantity (e.g. 12)
      final qtyField = find.widgetWithText(TextFormField, 'الكمية الأولية بالمخزن *');
      await tester.enterText(qtyField, '12');

      // Tap save
      final saveBtn = find.text('إضافة الصنف للمخزن');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify product is in database
      final products = await productDs.getProducts();
      expect(products.length, 1);
      expect(products.first.name, 'طقم حلل جرانيت 10 قطع');

      // Verify single variant was created atomically with color='-', size='-'
      final variants = await variantDs.getVariants(products.first.id);
      expect(variants.length, 1);
      expect(variants.first.color, '-');
      expect(variants.first.size, '-');
      expect(variants.first.costPrice, 150000); // 1500.00 EGP in piasters
      expect(variants.first.sellPrice, 210000); // 2100.00 EGP in piasters
      expect(variants.first.quantity, 12);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('RapidBarcodeIntakeDialog Tests (Supermarket Rapid Scan Intake)', () {
    testWidgets('scans a new barcode and quickly adds product with custom price and qty',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: _FakeAuthCubit(adminUser)),
                BlocProvider<CategoryCubit>(
                  create: (_) => getIt<CategoryCubit>()..getCategories(),
                ),
              ],
              child: const Scaffold(
                body: RapidBarcodeIntakeDialog(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('المسح السريع للمنتجات (نمط السوبر ماركت والبقالة)'), findsOneWidget);

      // Scan barcode: 6223000123456
      final barcodeField = find.byType(TextField).first;
      await tester.enterText(barcodeField, '6223000123456');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      // New product form appears
      expect(find.text('باركود جديد: 6223000123456'), findsOneWidget);

      // Enter name: "شيبسي بالجبنة"
      final nameField = find.widgetWithText(TextField, 'اسم الصنف *');
      await tester.enterText(nameField, 'شيبسي بالجبنة');

      // Enter sell price: "10.00"
      final sellField = find.widgetWithText(TextField, 'سعر البيع (ج.م) *');
      await tester.enterText(sellField, '10');

      // Enter cost price: "8.00"
      final costField = find.widgetWithText(TextField, 'سعر التكلفة (ج.م) *');
      await tester.enterText(costField, '8');

      // Enter qty: "24"
      final qtyField = find.widgetWithText(TextField, 'الكمية المستلمة *');
      await tester.enterText(qtyField, '24');

      // Tap Save
      final saveBtn = find.text('حفظ وإضافة');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify product added in session log
      expect(find.text('أصناف تم مسحها وتحديثها في هذه الجلسة (1)'), findsOneWidget);
      expect(find.text('شيبسي بالجبنة'), findsOneWidget);
      expect(find.text('+24 قطعة'), findsOneWidget);

      // Now scan the same barcode again -> should increment quantity!
      await tester.enterText(barcodeField, '6223000123456');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      // Session history now has 2 entries (first addition + second increment)
      expect(find.text('أصناف تم مسحها وتحديثها في هذه الجلسة (2)'), findsOneWidget);
      expect(find.text('+1 قطعة'), findsOneWidget);

      // Check DB stock: 24 + 1 = 25
      final allVariants = await variantDs.getAllVariants();
      final chipsVariant = allVariants.firstWhere((v) => v.sku == '6223000123456');
      expect(chipsVariant.quantity, 25);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
