import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
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
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/onboarding/presentation/screens/first_launch_setup_screen.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<LocalBackupService>(_FakeBackupService(db, featureGate));

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

  group('Task 27: First Launch Onboarding Polish & Presets', () {
    test('StorePreset.custom includes all 18 activities and does not reset or empty activities', () async {
      expect(StorePreset.custom.activities.length, equals(18));
      for (final activity in ActivityType.values) {
        expect(
          StorePreset.custom.activities.contains(activity),
          isTrue,
          reason: 'Activity $activity must be included in StorePreset.custom',
        );
      }

      // Fresh state has all activities enabled
      final initialActivities = await activityService.getEnabledActivities();
      expect(initialActivities.length, equals(18));

      // Applying StorePreset.custom preserves all activities without resetting or emptying
      await activityService.applyStorePreset(StorePreset.custom, userId: 'admin_user');
      final enabledActivities = await activityService.getEnabledActivities();
      expect(enabledActivities.length, equals(18));
      for (final activity in ActivityType.values) {
        expect(enabledActivities.contains(activity), isTrue);
      }
    });

    testWidgets('StorePreset.fashion enables delivery by default and allows setup completion with currency and branch name', (tester) async {
      tester.view.physicalSize = const Size(1280, 950);
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

      // 1. Verify Step 0: Store details and Currency dropdown
      final storeNameField = find.byKey(const Key('setup_store_name_field'));
      expect(storeNameField, findsOneWidget);
      await tester.enterText(storeNameField, 'متجر النور');
      await tester.pump();

      // Select SAR currency ('ر.س') from dropdown
      final currencyDropdown = find.byKey(const Key('setup_store_currency_dropdown'));
      expect(currencyDropdown, findsOneWidget);
      await tester.tap(currencyDropdown);
      await tester.pumpAndSettle();

      final sarOption = find.text('ر.س — ريال سعودي').last;
      await tester.tap(sarOption);
      await tester.pumpAndSettle();

      // Move to Step 1 (Preset & Operational Features)
      final nextBtn = find.byKey(const Key('setup_next_step_button'));
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 2. Verify StorePreset.fashion enables delivery by default
      final deliverySwitchFinder = find.byKey(const Key('setup_feature_delivery_switch'));
      expect(deliverySwitchFinder, findsOneWidget);
      final deliverySwitch = tester.widget<Switch>(deliverySwitchFinder);
      expect(deliverySwitch.value, isTrue, reason: 'Delivery switch should be enabled by default for fashion');

      // Tapping fashion preset explicitly keeps delivery enabled
      final fashionPreset = find.byKey(const Key('preset_card_fashion'));
      await tester.ensureVisible(fashionPreset);
      await tester.tap(fashionPreset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final fashionDeliverySwitch = tester.widget<Switch>(deliverySwitchFinder);
      expect(fashionDeliverySwitch.value, isTrue);

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

      // Finish setup
      final finishBtn = find.byKey(const Key('setup_finish_button'));
      await tester.ensureVisible(finishBtn);
      await tester.tap(finishBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(setupFinished, isTrue);

      // 3. Verify app_meta records
      final currencyMeta = await (db.select(db.appMeta)..where((t) => t.key.equals('store.currency'))).getSingleOrNull();
      expect(currencyMeta, isNotNull);
      expect(currencyMeta!.value, equals('ر.س'));

      final branchMeta = await (db.select(db.appMeta)..where((t) => t.key.equals('branch_name'))).getSingleOrNull();
      expect(branchMeta, isNotNull);
      expect(branchMeta!.value, equals('الفرع الرئيسي - متجر النور'));

      // Verify delivery feature enabled
      expect(await featureGate.isEnabled(FeatureKeys.delivery), isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
