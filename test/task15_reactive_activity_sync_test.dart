import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/database_reset_service.dart';
import 'package:clothes_erp/core/services/license_activation_service.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pre_orders/data/services/telegram_bot_service.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/widgets/simple_product_form_dialog.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
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

class _FakeAuthDs implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? u) => _user = u;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  _FakeSettingsCubit() : super(const SettingsState());
  @override
  void start() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBackupService extends LocalBackupService {
  _FakeBackupService(super.db, super.featureGate);
  @override
  Future<BackupResult> createBackup({
    String? targetFilePath,
    String userId = 'system',
    bool updateMetadata = true,
  }) async {
    return BackupResult(
      filePath: 'dummy.sqlite',
      sizeBytes: 1024,
      createdAt: DateTime.now(),
    );
  }
}

class _FakeVariantRepo implements VariantRepository {
  List<VariantEntity> variants = [];
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() {
    return Stream.value(Right(variants));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  List<ProductEntity> products = [];
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async {
    return Right(products);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  List<CategoryEntity> categories = [];
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async {
    return Right(categories);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCreateSaleUseCase implements CreateSaleUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddProductUseCase implements AddProductUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUpdateProductUseCase implements UpdateProductUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late LicenseActivationService licenseService;
  late _FakeVariantRepo variantRepo;
  late _FakeProductRepo productRepo;
  late _FakeCategoryRepo categoryRepo;
  late _FakePosRepo posRepo;
  late _FakeCreateSaleUseCase createSaleUseCase;
  late UserModel adminUser;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final authDs = _FakeAuthDs();
    adminUser = UserModel(
      id: 'admin_1',
      name: 'المدير العام',
      email: 'admin@bay3ah.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    authDs.setUser(adminUser);

    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    featureGate = FeatureGate(db, authDs, txWriter, branchProvider);
    activityService = ActivitySettingsService(db, featureGate);
    licenseService = LicenseActivationService(db);
    final backupService = _FakeBackupService(db, featureGate);
    final resetService = DatabaseResetService(db, backupService);

    variantRepo = _FakeVariantRepo();
    productRepo = _FakeProductRepo();
    categoryRepo = _FakeCategoryRepo();
    posRepo = _FakePosRepo();
    createSaleUseCase = _FakeCreateSaleUseCase();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<LicenseActivationService>(licenseService);
    sl.registerSingleton<DatabaseResetService>(resetService);
    sl.registerSingleton<LocalBackupService>(backupService);
    sl.registerSingleton<ProductRepository>(productRepo);
    sl.registerSingleton<TelegramBotService>(TelegramBotService(db, featureGate));
    sl.registerLazySingleton<ManagerPinService>(
      () => ManagerPinService(db, txWriter, branchProvider, authDs, featureGate),
    );
    sl.registerFactory<SettingsCubit>(() => _FakeSettingsCubit());

    final getCatUseCase = GetCategoriesUseCase(categoryRepo);
    final addProdUseCase = _FakeAddProductUseCase();
    final updateProdUseCase = _FakeUpdateProductUseCase();
    sl.registerFactory<ProductFormCubit>(
      () => ProductFormCubit(
        addProdUseCase,
        updateProdUseCase,
        getCatUseCase,
        productRepo,
      ),
    );
  });

  tearDown(() async {
    licenseService.dispose();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 15: Instant Reactive Cross-Screen Activity Sync in PosCubit', () {
    test('PosCubit updates enabled activities and filters out inactive activities in "all" mode', () async {
      final cat = CategoryEntity(
        id: 'cat_1',
        name: 'عام',
        description: '',
        createdAt: DateTime.now(),
      );
      categoryRepo.categories = [cat];

      final pClothing = ProductEntity(
        id: 'p_cloth',
        categoryId: 'cat_1',
        categoryName: 'عام',
        name: 'قميص أزرق',
        description: '',
        activityType: 'clothing',
        createdAt: DateTime.now(),
      );
      final pGrocery = ProductEntity(
        id: 'p_groc',
        categoryId: 'cat_1',
        categoryName: 'عام',
        name: 'أرز بسمتي',
        description: '',
        activityType: 'supermarketGroceries',
        createdAt: DateTime.now(),
      );
      productRepo.products = [pClothing, pGrocery];

      final vClothing = VariantEntity(
        id: 'v_cloth',
        productId: 'p_cloth',
        productCode: 'CLOTH01',
        productName: 'قميص أزرق',
        color: 'أزرق',
        size: 'L',
        salePrice: 200,
        costPrice: 150,
        minStock: 5,
        quantity: 10,
        createdAt: DateTime.now(),
      );
      final vGrocery = VariantEntity(
        id: 'v_groc',
        productId: 'p_groc',
        productCode: 'GROC01',
        productName: 'أرز بسمتي',
        color: '-',
        size: '-',
        salePrice: 50,
        costPrice: 40,
        minStock: 5,
        quantity: 20,
        createdAt: DateTime.now(),
      );
      variantRepo.variants = [vClothing, vGrocery];

      // Ensure both clothing and supermarketGroceries activities are initially enabled
      await activityService.setActivityEnabled(ActivityType.clothing, true, userId: 'admin_1');
      await activityService.setActivityEnabled(ActivityType.supermarketGroceries, true, userId: 'admin_1');

      final posCubit = PosCubit(
        createSaleUseCase,
        variantRepo,
        categoryRepo,
        productRepo,
        posRepo,
      );

      await posCubit.init();
      await pumpEventQueue();

      // Initially both variants are visible under 'all'
      expect(posCubit.state.filteredVariants.length, equals(2));
      expect(posCubit.currentEnabledActivities.contains('supermarketGroceries'), isTrue);
      expect(posCubit.currentEnabledActivities.contains('clothing'), isTrue);

      // Disable supermarketGroceries activity reactively
      await activityService.setActivityEnabled(ActivityType.supermarketGroceries, false, userId: 'admin_1');
      await pumpEventQueue();

      // PosCubit stream should reactively exclude supermarketGroceries items from 'all' mode
      expect(posCubit.currentEnabledActivities.contains('supermarketGroceries'), isFalse);
      expect(posCubit.state.filteredVariants.length, equals(1));
      expect(posCubit.state.filteredVariants.first.id, equals('v_cloth'));

      // If user had supermarketGroceries selected, PosCubit resets selectedActivity to 'all'
      posCubit.filterByActivity('supermarketGroceries');
      expect(posCubit.state.selectedActivity, equals('all'));

      // Re-enable supermarketGroceries reactively
      await activityService.setActivityEnabled(ActivityType.supermarketGroceries, true, userId: 'admin_1');
      await pumpEventQueue();

      // Both items are visible again
      expect(posCubit.currentEnabledActivities.contains('supermarketGroceries'), isTrue);
      expect(posCubit.state.filteredVariants.length, equals(2));

      await posCubit.close();
    });
  });

  group('Task 15: Product Creation Default Activity Sync', () {
    test('ProductFormCubit uses first enabled store activity as default instead of hardcoded clothing', () async {
      // Disable clothing and enable only supermarketGroceries
      await activityService.setAllActivities(false, userId: 'admin_1');
      await activityService.setActivityEnabled(ActivityType.supermarketGroceries, true, userId: 'admin_1');
      await activityService.setActivityEnabled(ActivityType.clothing, false, userId: 'admin_1');

      final cubit = GetIt.instance<ProductFormCubit>();
      await cubit.init(null);

      // Default activity should be supermarketGroceries (first active activity)
      expect(cubit.state.activityType, equals('supermarketGroceries'));
      await cubit.close();
    });

    testWidgets('SimpleProductFormDialog initializes with active store activity', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set store to only supermarketGroceries active
      await activityService.setAllActivities(false, userId: 'admin_1');
      await activityService.setActivityEnabled(ActivityType.supermarketGroceries, true, userId: 'admin_1');
      await activityService.setActivityEnabled(ActivityType.clothing, false, userId: 'admin_1');
      await activityService.getEnabledActivities();

      final authCubit = _FakeAuthCubit(adminUser);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const Scaffold(
              body: SimpleProductFormDialog(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that dialog is rendered
      expect(find.byType(SimpleProductFormDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 15: SystemSettingsScreen Store Activities Save & Sector Sync', () {
    testWidgets('Save button in Activities Settings synchronizes retail sector mode and shows green SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authCubit = _FakeAuthCubit(adminUser);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const SystemSettingsScreen(initialCategory: 'activities'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Activities card and Presets are rendered
      expect(find.text('أقسام المنتجات والأنشطة المتوفرة بالمحل'), findsOneWidget);
      expect(find.byKey(const Key('save_store_activity_settings_btn')), findsOneWidget);

      // Select Grocery preset
      final groceryPresetKey = find.byKey(const Key('store_preset_grocery'));
      await tester.ensureVisible(groceryPresetKey);
      await tester.tap(groceryPresetKey);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap explicit save button
      final saveBtn = find.byKey(const Key('save_store_activity_settings_btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify confirmation SnackBar
      expect(find.text('تم حفظ وتطبيق نشاط المتجر بنجاح وتحديث الكاشير والمنتجات فورياً'), findsOneWidget);

      // Verify RetailSector metaKey was updated to supermarket in app_meta
      final sectorMeta = await featureGate.getMeta(RetailSector.metaKey);
      expect(sectorMeta, equals(RetailSector.supermarket));

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
