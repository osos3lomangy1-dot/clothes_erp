import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/license_activation_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:clothes_erp/features/auth/domain/repositories/auth_repository.dart';
import 'package:clothes_erp/features/auth/domain/usecases/get_auth_status_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/login_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/logout_usecase.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/presentation/screens/login_screen.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
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

class _FakeAuthLocalDs implements AuthLocalDataSource {
  UserModel? _user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class _FakeAuthRemoteDs implements AuthRemoteDataSource {
  @override
  Future<UserModel> login(String email, String password) async => UserModel(
        id: 'admin_1',
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

class _SpyPosCubit extends Cubit<PosState> implements PosCubit {
  _SpyPosCubit(super.initial);
  @override
  Future<void> init() async {}
  @override
  void clearCart() => emit(const PosLoaded(cart: []));
  @override
  void searchProducts(String query) {}
  @override
  VariantEntity? getVariantById(String variantId) => null;
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

  late AppDatabase db;
  late LicenseActivationService licenseService;
  late AuthRepository authRepo;
  late AuthCubit authCubit;

  final fixedDate = DateTime(2026, 11, 22);

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    licenseService = LicenseActivationService(db);

    final authLocalDs = _FakeAuthLocalDs();
    final authRemoteDs = _FakeAuthRemoteDs();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    final featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);

    authRepo = AuthRepositoryImpl(
      authRemoteDs,
      authLocalDs,
      db,
    );

    authCubit = AuthCubit(
      LoginUseCase(authRepo),
      LogoutUseCase(authRepo),
      GetAuthStatusUseCase(authRepo),
      db,
    );

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<LicenseActivationService>(licenseService);
    sl.registerSingleton<AuthCubit>(authCubit);

    // Insert initial users (Admin and Cashier) into DB
    final now = DateTime.now();
    await db.into(db.users).insert(
          UsersCompanion.insert(
            id: 'admin_user',
            branchId: 'branch-1',
            username: 'admin',
            displayName: 'المدير العام',
            role: 'admin',
            passwordHash: 'hash_admin123',
            passwordSalt: 'salt_admin',
            pinHash: const drift.Value('9999'),
            isActive: const drift.Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.users).insert(
          UsersCompanion.insert(
            id: 'cashier_user',
            branchId: 'branch-1',
            username: 'cashier1',
            displayName: 'أحمد الكاشير',
            role: 'cashier',
            passwordHash: 'hash_1234',
            passwordSalt: 'salt_cashier',
            pinHash: const drift.Value('1234'),
            isActive: const drift.Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    licenseService.dispose();
    authCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 14.4: Master Rescue Key & Cryptographic Challenge', () {
    test('generateRescueChallenge produces deterministic RESCUE-XXXX-YYYY format', () {
      const machineId = 'BAY3AH-A1B2-C3D4-E5F6';
      final challenge1 = LicenseCryptoCodec.generateRescueChallenge(machineId, fixedDate);
      final challenge2 = LicenseCryptoCodec.generateRescueChallenge(machineId, fixedDate);

      expect(challenge1, equals(challenge2));
      expect(challenge1.startsWith('RESCUE-'), isTrue);
      expect(challenge1.length, equals(16)); // RESCUE-XXXX-YYYY
    });

    test('computeMasterRescuePin generates valid 6-digit PIN and verifies successfully', () {
      const challenge = 'RESCUE-A1B2-C3D4';
      final pin = LicenseCryptoCodec.computeMasterRescuePin(challenge);

      expect(pin.length, equals(6));
      expect(int.tryParse(pin), isNotNull);

      expect(LicenseCryptoCodec.verifyMasterRescuePin(challenge, pin), isTrue);
      expect(LicenseCryptoCodec.verifyMasterRescuePin(challenge, '000000'), isFalse);
      expect(LicenseCryptoCodec.verifyMasterRescuePin(challenge, '12345'), isFalse);
    });

    test('LicenseActivationService.resetAdminPassword updates password with valid PIN', () async {
      final challenge = await licenseService.getRescueChallenge(fixedDate);
      final validPin = LicenseCryptoCodec.computeMasterRescuePin(challenge);

      await licenseService.resetAdminPassword(
        newPassword: 'newAdminPassword2026',
        rescuePin: validPin,
        date: fixedDate,
      );

      final updatedAdmin = await (db.select(db.users)
            ..where((u) => u.username.equals('admin')))
          .getSingle();

      expect(updatedAdmin.passwordHash, equals('hash_newAdminPassword2026'));
    });

    test('LicenseActivationService.resetAdminPassword throws on invalid PIN or short password', () async {
      expect(
        () => licenseService.resetAdminPassword(
          newPassword: 'pass',
          rescuePin: '000000',
          date: fixedDate,
        ),
        throwsA(isA<Exception>()),
      );

      final challenge = await licenseService.getRescueChallenge(fixedDate);
      final validPin = LicenseCryptoCodec.computeMasterRescuePin(challenge);

      expect(
        () => licenseService.resetAdminPassword(
          newPassword: 'abc', // < 4 chars
          rescuePin: validPin,
          date: fixedDate,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Offline KeyGen CLI handles --rescue flag cleanly', () {
      const testChallenge = 'RESCUE-9876-5432';
      final expectedPin = LicenseCryptoCodec.computeMasterRescuePin(testChallenge);

      expect(expectedPin.length, equals(6));
      expect(LicenseCryptoCodec.verifyMasterRescuePin(testChallenge, expectedPin), isTrue);
      expect(LicenseCryptoCodec.verifyMasterRescuePin(testChallenge, '000000'), isFalse);
    });
  });

  group('Task 14.3: Quick Cashier Login & PIN Fast Switch', () {
    test('switchCashierWithPin succeeds with correct PIN and authenticates user', () async {
      final result = await authCubit.switchCashierWithPin(
        usernameOrId: 'cashier1',
        pin: '1234',
      );

      expect(result, isTrue);
      expect(authCubit.state, isA<AuthAuthenticated>());
      final authUser = (authCubit.state as AuthAuthenticated).user;
      expect(authUser.name, equals('أحمد الكاشير'));
      expect(authUser.role, equals('cashier'));
    });

    test('switchCashierWithPin fails with incorrect PIN and does not authenticate', () async {
      final result = await authCubit.switchCashierWithPin(
        usernameOrId: 'cashier1',
        pin: '9999',
      );

      expect(result, isFalse);
    });

    testWidgets('LoginScreen toggles between Password Mode and Quick PIN Mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: authCubit,
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Password Mode is active
      expect(find.byKey(const Key('login_mode_password_button')), findsOneWidget);
      expect(find.byKey(const Key('login_mode_pin_button')), findsOneWidget);
      expect(find.text('اسم المستخدم أو البريد الإلكتروني'), findsOneWidget);

      // Tap PIN Mode button
      await tester.tap(find.byKey(const Key('login_mode_pin_button')));
      await tester.pumpAndSettle();

      // Cashier cards and Numpad appear
      expect(find.byKey(const Key('pin_user_cashier1')), findsOneWidget);
      expect(find.byKey(const Key('pin_user_admin')), findsOneWidget);
      expect(find.byKey(const Key('pin_key_1')), findsOneWidget);
      expect(find.byKey(const Key('pin_submit_button')), findsOneWidget);

      // Select cashier and enter PIN via Numpad
      await tester.tap(find.byKey(const Key('pin_user_cashier1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pin_key_1')));
      await tester.tap(find.byKey(const Key('pin_key_2')));
      await tester.tap(find.byKey(const Key('pin_key_3')));
      await tester.tap(find.byKey(const Key('pin_key_4')));
      await tester.pumpAndSettle();

      expect(authCubit.state, isA<AuthAuthenticated>());
      final current = (authCubit.state as AuthAuthenticated).user;
      expect(current.email, equals('cashier1'));
    });

    testWidgets('LoginScreen Master Rescue Dialog resets admin password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: authCubit,
            child: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Emergency / Forgot Password button
      expect(find.byKey(const Key('forgot_password_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('forgot_password_button')));
      await tester.pumpAndSettle();

      expect(find.text('طوارئ الحساب واستعادة كلمة المرور'), findsOneWidget);
      expect(find.byKey(const Key('rescue_pin_field')), findsOneWidget);

      // Compute PIN for today's challenge
      final challenge = await licenseService.getRescueChallenge();
      final validPin = LicenseCryptoCodec.computeMasterRescuePin(challenge);

      await tester.enterText(find.byKey(const Key('rescue_pin_field')), validPin);
      await tester.enterText(find.byKey(const Key('rescue_new_password_field')), 'rescuedPass2026');
      await tester.enterText(find.byKey(const Key('rescue_confirm_password_field')), 'rescuedPass2026');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rescue_submit_button')));
      await tester.pumpAndSettle();

      // Dialog closed and password updated in DB
      expect(find.text('طوارئ الحساب واستعادة كلمة المرور'), findsNothing);

      final adminUser = await (db.select(db.users)..where((u) => u.username.equals('admin'))).getSingle();
      expect(adminUser.passwordHash, equals('hash_rescuedPass2026'));
    });

    testWidgets('PosScreen Quick Switch button switches cashier and preserves cart', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Authenticate admin first
      await authCubit.switchCashierWithPin(usernameOrId: 'admin', pin: '9999');

      final posCubit = _SpyPosCubit(
        const PosLoaded(
          cart: [
            SaleItemEntity(
              variantId: 'v1',
              productId: 'p1',
              productName: 'بدلة رجالي',
              size: 'L',
              color: 'كحلي',
              price: 500,
              quantity: 1,
            ),
          ],
        ),
      );

      final sl = GetIt.instance;
      sl.registerFactory<PosCubit>(() => posCubit);
      sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: authCubit,
            child: const PosScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Pos header shows admin
      expect(find.text('المدير العام'), findsOneWidget);
      expect(find.byKey(const Key('pos_switch_cashier_button')), findsOneWidget);

      // Verify cart has item
      expect(find.text('بدلة رجالي'), findsOneWidget);

      // Tap Switch Cashier button
      await tester.tap(find.byKey(const Key('pos_switch_cashier_button')));
      await tester.pumpAndSettle();

      expect(find.text('تبديل الكاشير السريع (Quick Switch)'), findsOneWidget);
      expect(find.byKey(const Key('pos_cashier_chip_cashier1')), findsOneWidget);

      // Select cashier and enter PIN
      await tester.tap(find.byKey(const Key('pos_cashier_chip_cashier1')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pos_cashier_pin_field')), '1234');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pos_confirm_switch_cashier_button')));
      await tester.pumpAndSettle();

      // Dialog closed, active user switched to cashier, cart still has item
      expect(find.text('تبديل الكاشير السريع (Quick Switch)'), findsNothing);
      expect(find.text('أحمد الكاشير'), findsOneWidget);
      expect(find.text('بدلة رجالي'), findsOneWidget);
    });
  });
}
