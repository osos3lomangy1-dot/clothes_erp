import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:clothes_erp/features/auth/domain/repositories/auth_repository.dart';
import 'package:clothes_erp/features/auth/domain/usecases/get_auth_status_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/login_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/logout_usecase.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/onboarding/presentation/screens/first_launch_setup_screen.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
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

class _FakeAuthRemoteDs implements AuthRemoteDataSource {
  @override
  Future<UserModel> login(String email, String password) async => UserModel(
        id: 'admin_user',
        name: 'المدير العام',
        email: email,
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      );
  @override
  Future<void> logout() async {}
  @override
  Stream<UserModel?> get authStateChanges => Stream.value(null);
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

class _FakeShiftCubit extends Cubit<ShiftState> implements ShiftCubit {
  _FakeShiftCubit()
      : super(const ShiftState(shiftsEnabled: false, status: ShiftStatus.loaded));
  @override
  Future<void> loadShiftData() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  final FeatureGate _featureGate;
  _FakeSettingsCubit(this._featureGate) : super(const SettingsState());
  @override
  void start() {}
  @override
  Future<String?> toggleFeature(String key, bool enabled, String userId) async {
    try {
      await _featureGate.setFeatureEnabled(key, enabled, userId: userId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late AuthCubit authCubit;
  late AuthRepository authRepo;
  late UserModel adminUser;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final authLocalDs = _FakeAuthLocalDataSource();
    final authRemoteDs = _FakeAuthRemoteDs();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);

    adminUser = UserModel(
      id: 'admin_user',
      name: 'المدير العام',
      email: 'admin@bay3ah.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    authLocalDs.cacheUser(adminUser);

    featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    activityService = ActivitySettingsService(db, featureGate);

    authRepo = AuthRepositoryImpl(
      authRemoteDs,
      authLocalDs,
      db,
    );

    final loginUseCase = LoginUseCase(authRepo);
    final logoutUseCase = LogoutUseCase(authRepo);
    final getAuthStatusUseCase = GetAuthStatusUseCase(authRepo);

    authCubit = AuthCubit(
      loginUseCase,
      logoutUseCase,
      getAuthStatusUseCase,
      db,
    );

    final variantRepo = _FakeVariantRepo();
    final productRepo = _FakeProductRepo();
    final categoryRepo = _FakeCategoryRepo();
    final posRepo = _FakePosRepo();
    final createSaleUseCase = _FakeCreateSaleUseCase();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<LocalBackupService>(_FakeBackupService(db, featureGate));
    sl.registerFactory<PosCubit>(() => PosCubit(
      createSaleUseCase,
      variantRepo,
      categoryRepo,
      productRepo,
      posRepo,
    ));
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());
    sl.registerFactory<SettingsCubit>(() => _FakeSettingsCubit(featureGate));

    AppBranding.apply(AppBrandingConfig.defaults);
    ReceiptSettingsService.notifier.value = ReceiptSettingsService.current.copyWith(
      storeName: 'بيعة',
    );
  });

  tearDown(() async {
    await authCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 16: FeatureGate Default States & Gating Verification', () {
    test('Delivery and Pre-Orders are disabled by default for fresh installations', () async {
      // 1. Delivery should be false by default
      final isDeliveryOn = await featureGate.isEnabled(FeatureKeys.delivery);
      expect(isDeliveryOn, isFalse);

      // 2. Pre-Orders should be false by default
      final isPreOrdersOn = await featureGate.isEnabled(FeatureKeys.preOrders);
      expect(isPreOrdersOn, isFalse);

      // 3. Installments should be false by default
      final isInstallmentsOn = await featureGate.isEnabled(FeatureKeys.installments);
      expect(isInstallmentsOn, isFalse);

      // 4. Manually enabling delivery updates status
      await featureGate.setFeatureEnabled(FeatureKeys.delivery, true, userId: 'admin_user');
      expect(await featureGate.isEnabled(FeatureKeys.delivery), isTrue);

      // 5. ActivitySettingsService helpers verify delivery status and stream
      expect(await activityService.isDeliveryEnabled(), isTrue);
      await activityService.setDeliveryEnabled(false, userId: 'admin_user');
      expect(await activityService.isDeliveryEnabled(), isFalse);
    });
  });

  group('Task 16: MainLayout & PosScreen Delivery Gating', () {
    testWidgets('MainLayout hides delivery navigation item when feature is disabled, and shows it when enabled', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Ensure delivery is initially disabled
      await featureGate.setFeatureEnabled(FeatureKeys.delivery, false, userId: 'admin_user');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const MainLayout(
              currentRoute: '/dashboard',
              child: Scaffold(body: Text('لوحة التحكم')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Delivery navigation item should be hidden
      expect(find.text('إدارة الدليفري والطيارين'), findsNothing);

      // Enable delivery feature
      await featureGate.setFeatureEnabled(FeatureKeys.delivery, true, userId: 'admin_user');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Delivery navigation item should now appear in the sidebar
      expect(find.text('إدارة الدليفري والطيارين'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('PosScreen hides delivery buttons when feature is disabled, and shows them when enabled', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Ensure delivery is initially disabled
      await featureGate.setFeatureEnabled(FeatureKeys.delivery, false, userId: 'admin_user');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Neither header button nor cart delivery button should be visible
      expect(find.byKey(const Key('pos_delivery_header_btn')), findsNothing);
      expect(find.byKey(const Key('pos_cart_delivery_btn')), findsNothing);

      // Enable delivery feature
      await featureGate.setFeatureEnabled(FeatureKeys.delivery, true, userId: 'admin_user');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Delivery buttons should now appear
      expect(find.byKey(const Key('pos_delivery_header_btn')), findsOneWidget);
      expect(find.byKey(const Key('pos_cart_delivery_btn')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 16: FirstLaunchSetupScreen Modular Operational Features', () {
    testWidgets('FirstLaunchSetupScreen allows selecting modular features and saves them atomically in FeatureGate', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool setupFinished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FirstLaunchSetupScreen(
              onSetupCompleted: () => setupFinished = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Step 0: Fill store name
      final storeNameField = find.byKey(const Key('setup_store_name_field'));
      expect(storeNameField, findsOneWidget);
      await tester.enterText(storeNameField, 'مطعم ومأكولات السعادة');
      await tester.pump();

      // Go to Step 1 (Preset & Operational Features)
      final nextBtn = find.byKey(const Key('setup_next_step_button'));
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Step 1: Presets & Operational Features are visible
      expect(find.text('الخطوة 2: اختر نوع النشاط التجاري لمتجرك'), findsOneWidget);
      expect(find.byKey(const Key('setup_feature_delivery_switch')), findsOneWidget);
      expect(find.byKey(const Key('setup_feature_preorders_switch')), findsOneWidget);
      expect(find.byKey(const Key('setup_feature_installments_switch')), findsOneWidget);

      // Initially delivery is false
      final deliverySwitch = tester.widget<Switch>(find.byKey(const Key('setup_feature_delivery_switch')));
      expect(deliverySwitch.value, isFalse);

      // Tap Hospitality preset -> should suggest delivery = true
      final hospitalityPreset = find.byKey(const Key('preset_card_hospitality'));
      await tester.ensureVisible(hospitalityPreset);
      await tester.tap(hospitalityPreset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final updatedDeliverySwitch = tester.widget<Switch>(find.byKey(const Key('setup_feature_delivery_switch')));
      expect(updatedDeliverySwitch.value, isTrue);

      // Also manually enable Pre-Orders switch
      final preOrdersSwitchFinder = find.byKey(const Key('setup_feature_preorders_switch'));
      await tester.ensureVisible(preOrdersSwitchFinder);
      await tester.tap(preOrdersSwitchFinder);
      await tester.pump();

      final updatedPreOrdersSwitch = tester.widget<Switch>(preOrdersSwitchFinder);
      expect(updatedPreOrdersSwitch.value, isTrue);

      // Move to Step 2 (Admin Account)
      await tester.ensureVisible(nextBtn);
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Fill admin password
      final passField = find.byKey(const Key('setup_admin_password_field'));
      final confirmField = find.byKey(const Key('setup_admin_confirm_password_field'));
      await tester.enterText(passField, 'admin123');
      await tester.enterText(confirmField, 'admin123');
      await tester.pump();

      // Move to Step 3 (First Cashier)
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Move to Step 4 (Review)
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('الخطوة 5: مراجعة وتأكيد إعداد النظام'), findsOneWidget);
      expect(find.text('الدليفري • الحجز المسبق'), findsOneWidget);

      // Finish setup
      final finishBtn = find.byKey(const Key('setup_finish_button'));
      await tester.ensureVisible(finishBtn);
      await tester.tap(finishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(setupFinished, isTrue);

      // Verify FeatureGate has saved merchant's operational features
      expect(await featureGate.isEnabled(FeatureKeys.delivery), isTrue);
      expect(await featureGate.isEnabled(FeatureKeys.preOrders), isTrue);
      expect(await featureGate.isEnabled(FeatureKeys.installments), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Task 16: SystemSettingsScreen Delivery Feature Toggle', () {
    testWidgets('Manager can toggle delivery feature on and off in SystemSettingsScreen', (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Start with delivery disabled
      await featureGate.setFeatureEnabled(FeatureKeys.delivery, false, userId: 'admin_user');

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const SystemSettingsScreen(initialCategory: 'features'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expand delivery module accordion (Task 26 modular structure)
      final module2Header = find.byKey(const Key('module_header_2'));
      if (module2Header.evaluate().isNotEmpty) {
        await tester.ensureVisible(module2Header);
        await tester.tap(module2Header);
        await tester.pumpAndSettle();
      }

      final deliveryToggle = find.byKey(const Key('feature_delivery_toggle'));
      expect(deliveryToggle, findsOneWidget);

      // Verify it's initially off
      final switchWidget = tester.widget<Switch>(deliveryToggle);
      expect(switchWidget.value, isFalse);

      // Toggle delivery on
      await tester.ensureVisible(deliveryToggle);
      await tester.tap(deliveryToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify in FeatureGate that delivery is now enabled
      expect(await featureGate.isEnabled(FeatureKeys.delivery), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
