import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late FakeAuthLocalDataSource authDs;
  late UserModel admin;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    authDs = FakeAuthLocalDataSource();
    admin = UserModel(id: 'admin-1', name: 'Admin', email: 'a@a.a', role: 'admin', isActive: true, createdAt: DateTime(2026, 1, 1));
    authDs.setUser(admin);
    final tx = TxWriter(db);
    final branch = BranchProvider(db);
    gate = FeatureGate(db, authDs, tx, branch);
    final pin = ManagerPinService(db, tx, branch, authDs, gate);
    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<ManagerPinService>(pin);
    sl.registerFactory<SettingsCubit>(() => SettingsCubit(gate));
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: BlocProvider<AuthCubit>.value(
        value: FakeAuthCubit(admin),
        child: child,
      ),
    );
  }

  testWidgets('Installment Settings section hidden when feature.installments disabled', (tester) async {
    await tester.pumpWidget(wrap(const SystemSettingsScreen(initialCategory: 'pos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('installment_settings_section')), findsNothing);
    expect(find.byKey(const Key('payment_installment_toggle')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Installment Settings section visible and payment installment toggle functional when enabled', (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: admin.id);
    await tester.pumpWidget(wrap(const SystemSettingsScreen(initialCategory: 'pos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('installment_settings_section')), findsOneWidget);
    expect(find.byKey(const Key('payment_installment_toggle')), findsOneWidget);

    // toggle payment.installment ON
    await tester.tap(find.byKey(const Key('payment_installment_toggle')));
    await tester.pumpAndSettle();
    final meta = await gate.getMeta('payment.installment');
    expect(meta, '1');

    // PIN required toggle present and can be switched
    expect(find.byKey(const Key('installment_pin_required_toggle')), findsOneWidget);
    await tester.tap(find.byKey(const Key('installment_pin_required_toggle')));
    await tester.pumpAndSettle();
    final pinSvc = sl<ManagerPinService>();
    expect(await pinSvc.isPinRequired(), false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
