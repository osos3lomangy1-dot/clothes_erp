import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/installments/presentation/cubits/installment_plans_cubit.dart';
import 'package:clothes_erp/features/installments/presentation/screens/installment_plans_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late FakeAuthLocalDataSource authDs;
  late TxWriter tx;
  late BranchProvider branch;
  late ManagerPinService pin;
  late InstallmentsFacade facade;
  late UserModel admin;
  late UserModel cashier;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    authDs = FakeAuthLocalDataSource();
    admin = UserModel(id: 'admin-1', name: 'Admin', email: 'a@a.a', role: 'admin', isActive: true, createdAt: DateTime(2026, 1, 1));
    cashier = UserModel(id: 'cashier-1', name: 'Cashier', email: 'c@c.c', role: 'cashier', isActive: true, createdAt: DateTime(2026, 1, 1));
    authDs.setUser(admin);

    tx = TxWriter(db);
    branch = BranchProvider(db);
    gate = FeatureGate(db, authDs, tx, branch);
    pin = ManagerPinService(db, tx, branch, authDs, gate);

    facade = InstallmentsFacadeImpl(db, tx, branch, authDs, gate, pin);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<InstallmentsFacade>(facade);
    sl.registerFactory<InstallmentPlansCubit>(() => InstallmentPlansCubit(facade));

    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: admin.id);
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  Widget buildTestWidget() {
    return const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: InstallmentPlansScreen(),
      ),
    );
  }

  testWidgets('1. admin sees list of installment plans and add button', (tester) async {
    await facade.createPlan(
      name: 'خطة تقسيط 6 أشهر',
      durationMonths: 6,
      downPaymentPiasters: 10000,
      interestBp: 500,
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('خطط التقسيط'), findsOneWidget);
    expect(find.text('خطة تقسيط 6 أشهر'), findsOneWidget);
    expect(find.text('إضافة خطة جديدة'), findsOneWidget);
    expect(find.text('مفعلة'), findsOneWidget);
  });

  testWidgets('2. cashier is blocked/shown snackbar when opening plans screen', (tester) async {
    authDs.setUser(cashier);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('غير مصرح: إدارة خطط التقسيط متاحة للمدير فقط'), findsOneWidget);
  });

  testWidgets('3. admin can open dialog and create a new plan', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Click FAB
    await tester.tap(find.text('إضافة أول خطة'));
    await tester.pumpAndSettle();

    expect(find.text('إضافة خطة تقسيط جديدة'), findsOneWidget);

    // Enter name
    await tester.enterText(find.byType(TextField).first, 'خطة تقسيط VIP');
    await tester.pumpAndSettle();

    // Tap submit button in dialog
    await tester.tap(find.text('إضافة الخطة'));
    await tester.pumpAndSettle();

    // Plan should now appear in the list
    expect(find.text('خطة تقسيط VIP'), findsOneWidget);
  });
}

