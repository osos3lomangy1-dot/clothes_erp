import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/core/services/store_presets_engine.dart';
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
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/onboarding/presentation/screens/first_launch_setup_screen.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/main.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late AuthCubit authCubit;
  late AuthRepository authRepo;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    final authLocalDs = _FakeAuthLocalDataSource();
    final authRemoteDs = _FakeAuthRemoteDs();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);

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

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<LocalBackupService>(_FakeBackupService(db, featureGate));

    // Reset Branding and Receipt Config to clean defaults
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

  group('Task 14.1: StorePresetsEngine Unit Tests', () {
    test('applyPreset for Grocery activates supermarket activities and sector mode', () async {
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.grocery,
        featureGate: featureGate,
        activityService: activityService,
      );

      final sectorMode = await featureGate.getMeta(RetailSector.metaKey);
      expect(sectorMode, equals(RetailSector.supermarket));

      final isGroceriesEnabled = await activityService.isActivityEnabled(ActivityType.supermarketGroceries);
      final isSpicesEnabled = await activityService.isActivityEnabled(ActivityType.spicesNuts);
      final isClothingEnabled = await activityService.isActivityEnabled(ActivityType.clothing);

      expect(isGroceriesEnabled, isTrue);
      expect(isSpicesEnabled, isTrue);
      expect(isClothingEnabled, isFalse);
    });

    test('applyPreset for Electronics enables installments and houseware mode', () async {
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.electronics,
        featureGate: featureGate,
        activityService: activityService,
      );

      final sectorMode = await featureGate.getMeta(RetailSector.metaKey);
      expect(sectorMode, equals(RetailSector.houseware));

      final isInstallmentsEnabled = await featureGate.isEnabled(FeatureKeys.installments);
      expect(isInstallmentsEnabled, isTrue);

      final isMobilesEnabled = await activityService.isActivityEnabled(ActivityType.electronicsMobiles);
      expect(isMobilesEnabled, isTrue);
    });

    test('applyPreset for Fashion sets apparel sector mode', () async {
      await StorePresetsEngine.applyPreset(
        preset: StorePreset.fashion,
        featureGate: featureGate,
        activityService: activityService,
      );

      final sectorMode = await featureGate.getMeta(RetailSector.metaKey);
      expect(sectorMode, equals(RetailSector.apparel));

      final isClothingEnabled = await activityService.isActivityEnabled(ActivityType.clothing);
      expect(isClothingEnabled, isTrue);
    });
  });

  group('Task 14.1: FirstLaunchSetupScreen & MyApp Flow Tests', () {
    testWidgets('MyApp routes to FirstLaunchSetupScreen when isSetupCompleted is false',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
          ],
          child: const MyApp(isSetupCompleted: false),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FirstLaunchSetupScreen), findsOneWidget);
      expect(find.textContaining('معالج التهيئة والإعداد الأول'), findsOneWidget);
    });

    testWidgets('Full 5-step wizard flow saves settings, admin, cashier, and completes setup',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool setupCallbackInvoked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
            ],
            child: FirstLaunchSetupScreen(
              onSetupCompleted: () {
                setupCallbackInvoked = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // ─── Step 0: Store Details Validation ───
      // Try next with empty store name
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      expect(find.textContaining('يرجى إدخال اسم المتجر'), findsOneWidget);

      // Fill valid store details
      await tester.enterText(find.byKey(const Key('setup_store_name_field')), 'بوتيك النجوم');
      await tester.enterText(find.byKey(const Key('setup_store_phone_field')), '01099887766');
      await tester.enterText(find.byKey(const Key('setup_store_address_field')), 'الإسكندرية - سموحة');

      // Proceed to Step 1 (Activity Presets)
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ─── Step 1: Preset Selection ───
      expect(find.textContaining('الخطوة 2: اختر نوع النشاط التجاري'), findsOneWidget);
      expect(find.byKey(const Key('preset_card_grocery')), findsOneWidget);
      expect(find.byKey(const Key('preset_card_electronics')), findsOneWidget);

      // Select Grocery preset
      await tester.tap(find.byKey(const Key('preset_card_grocery')));
      await tester.pump();

      // Proceed to Step 2 (Admin Account)
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ─── Step 2: Admin Account Validation ───
      expect(find.textContaining('الخطوة 3: إنشاء حساب مالك ومدير النظام'), findsOneWidget);

      // Try with short password
      await tester.enterText(find.byKey(const Key('setup_admin_password_field')), '12');
      await tester.enterText(find.byKey(const Key('setup_admin_confirm_password_field')), '12');
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      expect(find.textContaining('ألا تقل عن 4 محارف'), findsOneWidget);

      // Try with mismatched confirm password
      await tester.enterText(find.byKey(const Key('setup_admin_password_field')), 'admin2026');
      await tester.enterText(find.byKey(const Key('setup_admin_confirm_password_field')), 'different123');
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      expect(find.textContaining('غير متطابقين'), findsOneWidget);

      // Valid admin password
      await tester.enterText(find.byKey(const Key('setup_admin_password_field')), 'admin2026');
      await tester.enterText(find.byKey(const Key('setup_admin_confirm_password_field')), 'admin2026');

      // Proceed to Step 3 (First Cashier)
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ─── Step 3: First Cashier ───
      expect(find.textContaining('الخطوة 4: حساب أول كاشير'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('setup_cashier_name_field')), 'محمد أحمد');
      await tester.enterText(find.byKey(const Key('setup_cashier_pin_field')), '5566');

      // Proceed to Step 4 (Review)
      await tester.tap(find.byKey(const Key('setup_next_step_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ─── Step 4: Review and Finish ───
      expect(find.textContaining('الخطوة 5: مراجعة وتأكيد إعداد النظام'), findsOneWidget);
      expect(find.textContaining('بوتيك النجوم'), findsOneWidget);
      expect(find.textContaining('سوبرماركت وبقالة'), findsOneWidget);
      expect(find.textContaining('محمد أحمد (PIN: 5566)'), findsOneWidget);

      // Finish setup
      await tester.tap(find.byKey(const Key('setup_finish_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify Database & Service Changes
      final setupCompletedMeta = await (db.select(db.appMeta)
            ..where((m) => m.key.equals('setup.completed')))
          .getSingleOrNull();
      expect(setupCompletedMeta?.value, equals('1'));

      // Verify Admin in DB
      final adminUser = await (db.select(db.users)
            ..where((u) => u.username.equals('admin')))
          .getSingleOrNull();
      expect(adminUser, isNotNull);
      expect(adminUser!.role, equals('admin'));
      expect(adminUser.passwordHash, equals('hash_admin2026'));

      // Verify Cashier in DB
      final cashierUser = await (db.select(db.users)
            ..where((u) => u.username.equals('cashier')))
          .getSingleOrNull();
      expect(cashierUser, isNotNull);
      expect(cashierUser!.displayName, equals('محمد أحمد'));
      expect(cashierUser.pinHash, equals('5566'));

      // Verify Branding & Receipt Config
      expect(AppBranding.current.appName, equals('بوتيك النجوم'));
      expect(ReceiptSettingsService.current.storeName, equals('بوتيك النجوم'));
      expect(ReceiptSettingsService.current.storePhone, equals('01099887766'));

      // Verify Callback Invoked
      expect(setupCallbackInvoked, isTrue);
    });
  });
}
