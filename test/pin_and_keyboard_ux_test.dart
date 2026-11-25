import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:clothes_erp/features/auth/domain/usecases/get_auth_status_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/login_usecase.dart';
import 'package:clothes_erp/features/auth/domain/usecases/logout_usecase.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/presentation/screens/login_screen.dart';
import 'package:clothes_erp/features/employees/data/datasources/employee_local_data_source.dart';
import 'package:clothes_erp/features/employees/data/repositories/employee_repository_impl.dart';
import 'package:clothes_erp/features/employees/domain/entities/employee_entity.dart';
import 'package:clothes_erp/features/employees/domain/repositories/employee_repository.dart';
import 'package:clothes_erp/features/employees/domain/usecases/add_employee_usecase.dart';
import 'package:clothes_erp/features/employees/domain/usecases/delete_employee_usecase.dart';
import 'package:clothes_erp/features/employees/domain/usecases/get_employees_usecase.dart';
import 'package:clothes_erp/features/employees/domain/usecases/update_employee_status_usecase.dart';
import 'package:clothes_erp/features/employees/domain/usecases/update_employee_usecase.dart';
import 'package:clothes_erp/features/employees/presentation/cubits/employee_cubit.dart';
import 'package:clothes_erp/features/employees/presentation/screens/employee_list_screen.dart';
import 'package:clothes_erp/features/onboarding/presentation/screens/first_launch_setup_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sl = GetIt.instance;

  late AppDatabase db;
  late FeatureGate gate;
  late AuthCubit authCubit;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    final authLocalDs = _FakeAuthLocalDataSource();
    await authLocalDs.cacheUser(
      UserModel(
        id: 'admin',
        name: 'المدير العام',
        email: 'admin',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    gate = FeatureGate(db, authLocalDs, TxWriter(db), _FakeBranchProvider());
    await gate.setFeatureEnabled(FeatureKeys.employees, true, userId: 'system');
    final activityService = ActivitySettingsService(db, gate);
    final authRepo = AuthRepositoryImpl(
      _FakeAuthRemoteDs(),
      authLocalDs,
      db,
    );
    authCubit = AuthCubit(
      LoginUseCase(authRepo),
      LogoutUseCase(authRepo),
      GetAuthStatusUseCase(authRepo),
      db,
    );

    final empDs = EmployeeLocalDataSourceImpl(
      db,
      _FakeBranchProvider(),
      TxWriter(db),
    );
    final empRepo = EmployeeRepositoryImpl(empDs, gate);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerSingleton<EmployeeLocalDataSource>(empDs);
    sl.registerSingleton<EmployeeRepository>(empRepo);
    sl.registerFactory<EmployeeCubit>(
      () => EmployeeCubit(
        GetEmployeesUseCase(empRepo),
        AddEmployeeUseCase(empRepo),
        UpdateEmployeeUseCase(empRepo),
        UpdateEmployeeStatusUseCase(empRepo),
        DeleteEmployeeUseCase(empRepo),
      ),
    );

    final now = DateTime(2026, 11, 1);
    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: 'cashier1',
        branchId: 'branch-1',
        username: 'cashier1',
        displayName: 'أحمد الكاشير',
        role: 'cashier',
        passwordHash: 'hash_1234',
        passwordSalt: 'salt',
        pinHash: const drift.Value('1234'),
        isActive: const drift.Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await authCubit.close();
    await sl.reset();
    await db.close();
  });

  group('4-Digit PIN & Physical Keyboard UX', () {
    testWidgets(
      'LoginScreen Quick PIN mode accepts physical keyboard digits, backspace, escape, and auto-submits at 4 digits',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider.value(
              value: authCubit,
              child: const LoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('login_mode_pin_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pin_user_cashier1')));
        await tester.pumpAndSettle();

        // Incomplete submit shows 4-digit guidance
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('pin_submit_button')));
        await tester.tap(find.byKey(const Key('pin_submit_button')));
        await tester.pump();
        expect(find.text('يرجى إدخال رمز PIN المكوّن من 4 أرقام'), findsOneWidget);

        // Escape clears input, then numpad + digit keys + backspace authenticate
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad9);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
        await tester.pumpAndSettle();

        expect(authCubit.state, isA<AuthAuthenticated>());
        expect((authCubit.state as AuthAuthenticated).user.email, 'cashier1');
      },
    );

    testWidgets(
      'FirstLaunchSetupScreen enforces 4-digit PINs for admin (optional) and cashier, saving pinHash in DB',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: FirstLaunchSetupScreen(onSetupCompleted: () {}),
            ),
          ),
        );
        await tester.pump();

        // Step 0 -> Step 1 -> Step 2
        await tester.enterText(
          find.byKey(const Key('setup_store_name_field')),
          'متجر التجربة',
        );
        await tester.tap(find.byKey(const Key('setup_next_step_button')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('setup_next_step_button')));
        await tester.pump();

        // Step 2: Invalid 2-digit admin PIN rejected, 4-digit accepted
        await tester.enterText(
          find.byKey(const Key('setup_admin_password_field')),
          'pass123',
        );
        await tester.enterText(
          find.byKey(const Key('setup_admin_confirm_password_field')),
          'pass123',
        );
        await tester.enterText(
          find.byKey(const Key('setup_admin_pin_field')),
          '12',
        );
        await tester.tap(find.byKey(const Key('setup_next_step_button')));
        await tester.pump();
        expect(find.text('رمز PIN للآدمن يجب أن يتكون من 4 أرقام.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('setup_admin_pin_field')),
          '4455',
        );
        await tester.tap(find.byKey(const Key('setup_next_step_button')));
        await tester.pump();

        // Step 3: Invalid 2-digit cashier PIN rejected, 4-digit accepted
        await tester.enterText(
          find.byKey(const Key('setup_cashier_pin_field')),
          '99',
        );
        await tester.tap(find.byKey(const Key('setup_next_step_button')));
        await tester.pump();
        expect(find.text('رمز PIN للكاشير يجب أن يتكون من 4 أرقام.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('setup_cashier_pin_field')),
          '7788',
        );
        await tester.tap(find.byKey(const Key('setup_next_step_button')));
        await tester.pump();

        // Step 4: Finish setup
        await tester.tap(find.byKey(const Key('setup_finish_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final adminUser = await (db.select(db.users)
              ..where((u) => u.id.equals('admin_user')))
            .getSingle();
        final cashierUser = await (db.select(db.users)
              ..where((u) => u.id.equals('cashier_1')))
            .getSingle();
        expect(adminUser.pinHash, '4455');
        expect(cashierUser.pinHash, '7788');
      },
    );

    testWidgets(
      'EmployeeListScreen saves and displays 4-digit PIN and authenticates via switchCashierWithPin',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: EmployeeListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('إضافة موظف'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'الاسم الكامل *'),
          'سارة الكاشير',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'اسم المستخدم / كود الدخول *'),
          'sara_pos',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'كلمة المرور *'),
          'saraPass1',
        );
        await tester.enterText(
          find.byKey(const Key('employee_dialog_pin_field')),
          '2468',
        );
        await tester.tap(find.text('إضافة الموظف'));
        await tester.pumpAndSettle();

        expect(find.text('سارة الكاشير'), findsOneWidget);
        expect(find.text('PIN سريع مُفعّل'), findsWidgets);

        final ok = await authCubit.switchCashierWithPin(
          usernameOrId: 'sara_pos',
          pin: '2468',
        );
        expect(ok, isTrue);

        // Updating employee PIN works too
        final ds = sl<EmployeeLocalDataSource>();
        final sara = (await ds.getEmployees()).firstWhere((e) => e.username == 'sara_pos');
        expect(sara.pinCode, '2468');
        await ds.updateEmployee(
          EmployeeEntity(
            id: sara.id,
            displayName: sara.displayName,
            username: sara.username,
            role: sara.role,
            isActive: sara.isActive,
            salary: sara.salary,
            pinCode: '1357',
            createdAt: sara.createdAt,
          ),
          pinCode: '1357',
        );
        expect(
          await authCubit.switchCashierWithPin(usernameOrId: 'sara_pos', pin: '1357'),
          isTrue,
        );
      },
    );
  });
}
