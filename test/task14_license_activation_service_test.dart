import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/database_reset_service.dart';
import 'package:clothes_erp/core/services/license_activation_service.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

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

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'default';
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
      filePath: 'E:/backups/test.sqlite',
      sizeBytes: 1024,
      createdAt: DateTime.now(),
    );
  }
}

class _FakeAuthDs implements AuthLocalDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LicenseActivationService licenseService;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    licenseService = LicenseActivationService(db);

    final authDs = _FakeAuthDs();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    final featureGate = FeatureGate(db, authDs, txWriter, branchProvider);
    final backupService = _FakeBackupService(db, featureGate);
    final resetService = DatabaseResetService(db, backupService);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<DatabaseResetService>(resetService);
    sl.registerSingleton<LocalBackupService>(backupService);
    sl.registerSingleton<LicenseActivationService>(licenseService);
    sl.registerLazySingleton<ActivitySettingsService>(() => ActivitySettingsService(db, featureGate));
    sl.registerLazySingleton<ManagerPinService>(() => ManagerPinService(db, txWriter, branchProvider, authDs, featureGate));
    sl.registerFactory<SettingsCubit>(() => _FakeSettingsCubit());
  });

  tearDown(() async {
    licenseService.dispose();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 14.2: LicenseCryptoCodec Offline Key Cryptography Tests', () {
    test('generateKey produces valid format with B3H- prefix and HMAC signature', () {
      final key = LicenseCryptoCodec.generateKey(
        machineId: 'BAY3AH-A1B2-C3D4-E5F6',
        type: 'lifetime',
        tier: 'enterprise',
      );

      expect(key, startsWith('B3H-'));
      expect(key.split('-').length, greaterThanOrEqualTo(3));
    });

    test('verifyKey successfully decodes valid lifetime key for matching machine ID', () {
      const machineId = 'BAY3AH-1111-2222-3333';
      final key = LicenseCryptoCodec.generateKey(
        machineId: machineId,
        type: 'lifetime',
        tier: 'pro',
      );

      final decoded = LicenseCryptoCodec.verifyKey(key, expectedMachineId: machineId);
      expect(decoded, isNotNull);
      expect(decoded!.machineId, equals(machineId));
      expect(decoded.type, equals('lifetime'));
      expect(decoded.tier, equals('pro'));
      expect(decoded.expiryDate, isNull);
    });

    test('verifyKey successfully decodes expiring license with expiry date', () {
      const machineId = 'BAY3AH-4444-5555-6666';
      final expiry = DateTime(2027, 12, 31, 23, 59, 59);
      final key = LicenseCryptoCodec.generateKey(
        machineId: machineId,
        type: 'annual',
        tier: 'enterprise',
        expiryDate: expiry,
      );

      final decoded = LicenseCryptoCodec.verifyKey(key, expectedMachineId: machineId);
      expect(decoded, isNotNull);
      expect(decoded!.machineId, equals(machineId));
      expect(decoded.type, equals('annual'));
      expect(decoded.tier, equals('enterprise'));
      expect(decoded.expiryDate, isNotNull);
      expect(decoded.expiryDate!.year, equals(2027));
      expect(decoded.expiryDate!.month, equals(12));
    });

    test('verifyKey rejects key if Machine ID does not match expected', () {
      final key = LicenseCryptoCodec.generateKey(
        machineId: 'BAY3AH-AAAA-BBBB-CCCC',
        type: 'lifetime',
        tier: 'enterprise',
      );

      final decoded = LicenseCryptoCodec.verifyKey(
        key,
        expectedMachineId: 'BAY3AH-XXXX-YYYY-ZZZZ',
      );
      expect(decoded, isNull);
    });

    test('verifyKey rejects tampered signature', () {
      final key = LicenseCryptoCodec.generateKey(
        machineId: 'BAY3AH-AAAA-BBBB-CCCC',
        type: 'lifetime',
        tier: 'enterprise',
      );

      final tamperedKey = '${key.substring(0, key.length - 2)}99';
      final decoded = LicenseCryptoCodec.verifyKey(tamperedKey);
      expect(decoded, isNull);
    });

    test('verifyKey rejects malformed non-license strings', () {
      expect(LicenseCryptoCodec.verifyKey('INVALID-KEY-STRING'), isNull);
      expect(LicenseCryptoCodec.verifyKey(''), isNull);
      expect(LicenseCryptoCodec.verifyKey('B3H-SHORT'), isNull);
    });
  });

  group('Task 14.2: LicenseActivationService Lifecycle & Activation Tests', () {
    test('getMachineId returns persistent BAY3AH-XXXX-YYYY-ZZZZ formatted identifier', () async {
      final machineId1 = await licenseService.getMachineId();
      expect(machineId1, startsWith('BAY3AH-'));
      expect(machineId1.split('-').length, equals(4));

      final machineId2 = await licenseService.getMachineId();
      expect(machineId2, equals(machineId1));
    });

    test('checkLicenseStatus initializes 14-day free trial on first run', () async {
      final status = await licenseService.checkLicenseStatus();

      expect(status.state, equals(LicenseState.trialActive));
      expect(status.daysRemaining, inInclusiveRange(13, 14));
      expect(status.isActivated, isFalse);
      expect(status.isValid, isTrue);
      expect(status.statusMessage, contains('النسخة التجريبية'));
    });

    test('checkLicenseStatus detects anti-clock rollback tampering', () async {
      // 1. Initial status records last_seen_date
      await licenseService.checkLicenseStatus();

      // 2. Simulate clock moved forward in the past (e.g. tomorrow)
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await db.into(db.appMeta).insert(
            AppMetaCompanion.insert(
              key: 'license.last_seen_date',
              value: tomorrow.toIso8601String(),
              updatedAt: tomorrow,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );

      // 3. Now check status -> detects clock is before last_seen_date
      final tamperedStatus = await licenseService.checkLicenseStatus();
      expect(tamperedStatus.state, equals(LicenseState.clockTampered));
      expect(tamperedStatus.isValid, isFalse);
      expect(tamperedStatus.statusMessage, contains('تلاعب في ساعة النظام'));
    });

    test('activateLicense rejects invalid or mismatched key', () async {
      expect(
        () => licenseService.activateLicense('INVALID_KEY'),
        throwsA(isA<Exception>()),
      );

      final otherMachineKey = LicenseCryptoCodec.generateKey(
        machineId: 'BAY3AH-9999-8888-7777',
        type: 'lifetime',
        tier: 'enterprise',
      );

      expect(
        () => licenseService.activateLicense(otherMachineKey),
        throwsA(isA<Exception>()),
      );
    });

    test('activateLicense rejects expired license key', () async {
      final mid = await licenseService.getMachineId();
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      final expiredKey = LicenseCryptoCodec.generateKey(
        machineId: mid,
        type: 'annual',
        tier: 'enterprise',
        expiryDate: pastDate,
      );

      expect(
        () => licenseService.activateLicense(expiredKey),
        throwsA(isA<Exception>()),
      );
    });

    test('activateLicense successfully activates lifetime license key', () async {
      final mid = await licenseService.getMachineId();
      final validKey = LicenseCryptoCodec.generateKey(
        machineId: mid,
        type: 'lifetime',
        tier: 'enterprise',
      );

      final result = await licenseService.activateLicense(validKey);

      expect(result.state, equals(LicenseState.licensedLifetime));
      expect(result.isActivated, isTrue);
      expect(result.isValid, isTrue);
      expect(result.daysRemaining, equals(9999));
      expect(result.licenseType, equals('lifetime'));
      expect(result.tier, equals('enterprise'));
      expect(result.statusMessage, contains('مدى الحياة'));

      // Check subsequent checkLicenseStatus
      final recheck = await licenseService.checkLicenseStatus();
      expect(recheck.state, equals(LicenseState.licensedLifetime));
      expect(recheck.isActivated, isTrue);
    });

    test('activateLicense successfully activates valid annual license key', () async {
      final mid = await licenseService.getMachineId();
      final futureDate = DateTime.now().add(const Duration(days: 180));
      final annualKey = LicenseCryptoCodec.generateKey(
        machineId: mid,
        type: 'annual',
        tier: 'pro',
        expiryDate: futureDate,
      );

      final result = await licenseService.activateLicense(annualKey);

      expect(result.state, equals(LicenseState.licensedExpiring));
      expect(result.isActivated, isTrue);
      expect(result.isValid, isTrue);
      expect(result.daysRemaining, inInclusiveRange(178, 180));
      expect(result.tier, equals('pro'));
    });
  });

  group('Task 14.2: UI Settings License Activation Card Tests', () {
    testWidgets('LicenseActivationCard displays machine ID, status, and activation elements',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final adminUser = UserModel(
        id: 'admin_1',
        name: 'Master Admin',
        email: 'admin@bay3ah.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      final authCubit = _FakeAuthCubit(adminUser);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const SystemSettingsScreen(initialCategory: 'backup'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify License Card is rendered
      expect(find.textContaining('حالة ترخيص وتفعيل النظام'), findsOneWidget);
      expect(find.byKey(const Key('copy_machine_id_button')), findsOneWidget);
      expect(find.byKey(const Key('license_key_field')), findsOneWidget);
      expect(find.byKey(const Key('activate_license_button')), findsOneWidget);

      // Verify Initial Trial Status
      expect(find.textContaining('النسخة التجريبية'), findsOneWidget);

      // Generate a lifetime key and activate via the UI
      final mid = await licenseService.getMachineId();
      final validKey = LicenseCryptoCodec.generateKey(
        machineId: mid,
        type: 'lifetime',
        tier: 'enterprise',
      );

      await tester.ensureVisible(find.byKey(const Key('license_key_field')));
      await tester.enterText(find.byKey(const Key('license_key_field')), validKey);
      await tester.ensureVisible(find.byKey(const Key('activate_license_button')));
      await tester.tap(find.byKey(const Key('activate_license_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify Activated Lifetime Status and SnackBar
      expect(find.textContaining('تم تفعيل النظام بنجاح'), findsOneWidget);
      expect(find.text('نسخة مرخصة ومدفوعة رسمياً مدى الحياة'), findsOneWidget);
    });
  });
}
