import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/rest_sync_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/customers/data/services/customer_ledger_service.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/customers/presentation/widgets/customer_profile_dialog.dart';
import 'package:clothes_erp/features/dashboard/domain/entities/dashboard_stats_entity.dart';
import 'package:clothes_erp/features/dashboard/domain/usecases/get_dashboard_stats_usecase.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart';
import 'package:clothes_erp/features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_summary.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/installments_report_cubit.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/installments_report_section.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:dartz/dartz.dart';
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

void main() {
  late AppDatabase db;
  late FeatureGate featureGate;
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    final authDs = _FakeAuthLocalDataSource();
    authDs.setUser(UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'a@a.a',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    ));

    final tx = TxWriter(db);
    final branch = BranchProvider(db);
    featureGate = FeatureGate(db, authDs, tx, branch);
    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<FeatureGate>(featureGate);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  group('Credit Payment Settings & Cubit Tests', () {
    test('SettingsCubit loads creditPaymentEnabled as true by default and toggles correctly', () async {
      final cubit = SettingsCubit(featureGate);
      cubit.start();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.creditPaymentEnabled, isTrue);

      final err = await cubit.setPaymentMethod('payment.credit', false, 'admin-1');
      expect(err, isNull);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.creditPaymentEnabled, isFalse);

      final err2 = await cubit.setPaymentMethod('payment.credit', true, 'admin-1');
      expect(err2, isNull);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.creditPaymentEnabled, isTrue);

      await cubit.close();
    });

    test('SettingsCubit blocks disabling all payment methods including credit', () async {
      final cubit = SettingsCubit(featureGate);
      cubit.start();
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.setPaymentMethod('payment.cash', false, 'admin-1');
      await cubit.setPaymentMethod('payment.card', false, 'admin-1');
      await cubit.setPaymentMethod('payment.installment', false, 'admin-1');
      await Future.delayed(const Duration(milliseconds: 50));

      final err = await cubit.setPaymentMethod('payment.credit', false, 'admin-1');
      expect(err, contains('يجب تفعيل طريقة دفع واحدة على الأقل'));

      await cubit.close();
    });
  });

  group('Customer Profile Dialog — Conditional Installments Visibility Tests', () {
    testWidgets('Installments tab & KPI are hidden when feature disabled and customer has NO active installment',
        (tester) async {
      await featureGate.setFeatureEnabled(FeatureKeys.installments, false, userId: 'admin-1');

      final customer = CustomerEntity(
        id: 'cust-1',
        name: 'أحمد محمود',
        phone: '01000000001',
        createdAt: DateTime.now(),
      );

      final statement = CustomerStatement(
        summary: CustomerFinancialSummary(
          totalSpentPiasters: 50000,
          invoiceCount: 2,
          installmentsRemainingPiasters: 0,
          activeInstallmentsCount: 0,
          creditDebtPiasters: 0,
        ),
        sales: const [],
        installments: const [],
        payments: const [],
        loyaltyLogs: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showCustomerProfileDialog(
                    ctx,
                    customer: customer,
                    ledgerOverride: _MockCustomerLedgerService(statement),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify "التقسيط" Tab is NOT displayed
      expect(find.textContaining('التقسيط'), findsNothing);
      // Verify "متبقي الأقساط" KPI box is NOT displayed
      expect(find.text('متبقي الأقساط'), findsNothing);
      // Verify other tabs are present
      expect(find.text('الفواتير (0)'), findsOneWidget);
      expect(find.text('سداد الآجل (0)'), findsOneWidget);
      expect(find.text('نقاط الولاء (0)'), findsOneWidget);
    });

    testWidgets('Installments tab & KPI remain visible when customer HAS an active installment even if feature is disabled',
        (tester) async {
      await featureGate.setFeatureEnabled(FeatureKeys.installments, false, userId: 'admin-1');

      final customer = CustomerEntity(
        id: 'cust-2',
        name: 'سيف الدين',
        phone: '01000000002',
        createdAt: DateTime.now(),
      );

      final activeInstallment = CustomerInstallment(
        id: 'inst-1',
        branchId: 'b-1',
        customerId: 'cust-2',
        saleId: 'sale-1',
        planId: 'plan-1',
        totalPiasters: 100000,
        downPaymentPiasters: 20000,
        principalPiasters: 80000,
        interestBp: 0,
        remainingPiasters: 80000,
        durationMonths: 4,
        monthlyAmountPiasters: 20000,
        status: 'active',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 120)),
        createdBy: 'admin-1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final statement = CustomerStatement(
        summary: CustomerFinancialSummary(
          totalSpentPiasters: 100000,
          invoiceCount: 1,
          installmentsRemainingPiasters: 80000,
          activeInstallmentsCount: 1,
          creditDebtPiasters: 0,
        ),
        sales: const [],
        installments: [activeInstallment],
        payments: const [],
        loyaltyLogs: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showCustomerProfileDialog(
                    ctx,
                    customer: customer,
                    ledgerOverride: _MockCustomerLedgerService(statement),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Because customer has an active installment, it MUST be visible so the merchant can collect!
      expect(find.textContaining('التقسيط (1)'), findsOneWidget);
      expect(find.text('متبقي الأقساط'), findsOneWidget);
    });

    testWidgets('Credit banner & Tab are hidden when credit disabled and customer has NO active debt/payments',
        (tester) async {
      await featureGate.setMeta('payment.credit', '0', userId: 'admin-1');

      final customer = CustomerEntity(
        id: 'cust-3',
        name: 'عميل بدون آجل',
        phone: '01000000003',
        createdAt: DateTime.now(),
      );

      final statement = CustomerStatement(
        summary: CustomerFinancialSummary(
          totalSpentPiasters: 20000,
          invoiceCount: 1,
          installmentsRemainingPiasters: 0,
          activeInstallmentsCount: 0,
          creditDebtPiasters: 0,
        ),
        sales: const [],
        installments: const [],
        payments: const [],
        loyaltyLogs: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showCustomerProfileDialog(
                    ctx,
                    customer: customer,
                    ledgerOverride: _MockCustomerLedgerService(statement),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify Credit banner and tab are NOT displayed
      expect(find.textContaining('مديونية الحساب الآجل'), findsNothing);
      expect(find.textContaining('سداد الآجل'), findsNothing);
    });

    testWidgets('Credit banner & Tab remain visible when customer HAS active credit debt even if credit is disabled in settings',
        (tester) async {
      await featureGate.setMeta('payment.credit', '0', userId: 'admin-1');

      final customer = CustomerEntity(
        id: 'cust-4',
        name: 'عميل عليه دين آجل',
        phone: '01000000004',
        createdAt: DateTime.now(),
      );

      final statement = CustomerStatement(
        summary: CustomerFinancialSummary(
          totalSpentPiasters: 50000,
          invoiceCount: 1,
          installmentsRemainingPiasters: 0,
          activeInstallmentsCount: 0,
          creditDebtPiasters: 35000, // 350 EGP debt
        ),
        sales: const [],
        installments: const [],
        payments: const [],
        loyaltyLogs: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showCustomerProfileDialog(
                    ctx,
                    customer: customer,
                    ledgerOverride: _MockCustomerLedgerService(statement),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Because customer owes credit debt, merchant MUST be able to see and collect it!
      expect(find.textContaining('مديونية الحساب الآجل'), findsOneWidget);
      expect(find.textContaining('سداد الآجل'), findsOneWidget);
    });
  });

  group('POS Cart Overflow Resilience Tests', () {
    testWidgets('Empty cart widget does not overflow under constrained height (e.g. 60px)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 60, // Exactly the tight space where 37px overflow happened
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final iconSize = (constraints.maxHeight * 0.32).clamp(24.0, 56.0);
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: iconSize,
                                  color: Colors.grey.shade300,
                                ),
                                if (constraints.maxHeight >= 60) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'سلة المشتريات فارغة',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: Colors.grey.shade500,
                                      fontSize: constraints.maxHeight < 90 ? 11.5 : 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      // No overflow exceptions thrown!
      expect(find.text('سلة المشتريات فارغة'), findsOneWidget);
    });
  });

  group('Reports Installments Section — Conditional Visibility Tests', () {
    testWidgets('InstallmentsReportSection is hidden when feature is disabled AND summary has 0 debt',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Disable installments
      await featureGate.setFeatureEnabled(FeatureKeys.installments, false, userId: 'admin-1');

      final fakeFacade = _FakeInstallmentsFacade(const InstallmentSummary(
        totalOutstanding: 0,
        monthlyCollected: 0,
        overdueTotal: 0,
        overdueCount: 0,
      ));
      getIt.registerFactory<InstallmentsReportCubit>(() => InstallmentsReportCubit(fakeFacade));

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(child: InstallmentsReportSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Section should be hidden (SizedBox.shrink)
      expect(find.text('التقسيط'), findsNothing);
      expect(find.text('إجمالي المتبقي'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('InstallmentsReportSection remains visible when feature is disabled BUT summary has outstanding debt',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Disable installments
      await featureGate.setFeatureEnabled(FeatureKeys.installments, false, userId: 'admin-1');

      final fakeFacade = _FakeInstallmentsFacade(const InstallmentSummary(
        totalOutstanding: 75000,
        monthlyCollected: 20000,
        overdueTotal: 15000,
        overdueCount: 2,
      ));
      getIt.registerFactory<InstallmentsReportCubit>(() => InstallmentsReportCubit(fakeFacade));

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(child: InstallmentsReportSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Section must remain visible to allow collecting pending amounts!
      expect(find.text('التقسيط'), findsOneWidget);
      expect(find.text('إجمالي المتبقي'), findsOneWidget);
      expect(find.text('750.00'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Admin Dashboard Action Center — Conditional Visibility Tests', () {
    Widget buildDashboardWidget(UserModel adminUser) {
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider<AuthCubit>.value(
            value: _FakeAuthCubit(adminUser),
            child: const AdminDashboardScreen(),
          ),
        ),
      );
    }

    testWidgets('Overdue installments card is hidden when feature is disabled AND overdue count/amount is 0',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adminUser = UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      getIt.registerSingleton<RestSyncService>(_FakeRestSyncService());
      await featureGate.setFeatureEnabled(FeatureKeys.installments, false, userId: 'admin-1');

      const stats = DashboardStatsEntity(
        lowStockCount: 2,
        overdueInstallmentsCount: 0,
        overdueInstallmentsAmount: 0,
        totalCustomerCreditDebts: 0,
        totalSupplierDebts: 0,
      );
      getIt.registerFactory<DashboardCubit>(() => DashboardCubit(_FakeDashboardStatsUseCase(stats)));

      await tester.pumpWidget(buildDashboardWidget(adminUser));
      await tester.pumpAndSettle();

      expect(find.text('نواقص المخزون'), findsOneWidget);
      expect(find.text('أقساط متأخرة'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Overdue installments card is visible when overdue count > 0 even if feature is disabled',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adminUser = UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      getIt.registerSingleton<RestSyncService>(_FakeRestSyncService());
      await featureGate.setFeatureEnabled(FeatureKeys.installments, false, userId: 'admin-1');

      const stats = DashboardStatsEntity(
        lowStockCount: 2,
        overdueInstallmentsCount: 3,
        overdueInstallmentsAmount: 15000,
        totalCustomerCreditDebts: 0,
        totalSupplierDebts: 0,
      );
      getIt.registerFactory<DashboardCubit>(() => DashboardCubit(_FakeDashboardStatsUseCase(stats)));

      await tester.pumpWidget(buildDashboardWidget(adminUser));
      await tester.pumpAndSettle();

      expect(find.text('نواقص المخزون'), findsOneWidget);
      expect(find.text('أقساط متأخرة'), findsOneWidget);
      expect(find.text('3 عقد'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Customer credit debts card is hidden when credit is disabled AND customer debts is 0',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adminUser = UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      getIt.registerSingleton<RestSyncService>(_FakeRestSyncService());
      final cubit = SettingsCubit(featureGate);
      await cubit.setPaymentMethod('payment.credit', false, 'admin-1');
      await cubit.close();

      const stats = DashboardStatsEntity(
        lowStockCount: 2,
        overdueInstallmentsCount: 0,
        overdueInstallmentsAmount: 0,
        totalCustomerCreditDebts: 0,
        totalSupplierDebts: 0,
      );
      getIt.registerFactory<DashboardCubit>(() => DashboardCubit(_FakeDashboardStatsUseCase(stats)));

      await tester.pumpWidget(buildDashboardWidget(adminUser));
      await tester.pumpAndSettle();

      expect(find.text('مديونيات العملاء الآجلة'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Customer credit debts card is visible when customer debts > 0 even if credit is disabled',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adminUser = UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      getIt.registerSingleton<RestSyncService>(_FakeRestSyncService());
      final cubit = SettingsCubit(featureGate);
      await cubit.setPaymentMethod('payment.credit', false, 'admin-1');
      await cubit.close();

      const stats = DashboardStatsEntity(
        lowStockCount: 2,
        overdueInstallmentsCount: 0,
        overdueInstallmentsAmount: 0,
        totalCustomerCreditDebts: 45000,
        totalSupplierDebts: 0,
      );
      getIt.registerFactory<DashboardCubit>(() => DashboardCubit(_FakeDashboardStatsUseCase(stats)));

      await tester.pumpWidget(buildDashboardWidget(adminUser));
      await tester.pumpAndSettle();

      expect(find.text('مديونيات العملاء الآجلة'), findsOneWidget);
      expect(find.text('450.00 ج.م'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}

class _FakeRestSyncService implements RestSyncService {
  @override
  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {}
  @override
  void stopAutoSync() {}
  @override
  Stream<bool> get isSyncingStream => Stream.value(false);
  @override
  Stream<int> watchPendingCount() => Stream.value(0);
  @override
  bool get isSyncing => false;
  @override
  Future<SyncResult> syncPendingData() async => const SyncResult(total: 0, synced: 0, failed: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _FakeDashboardStatsUseCase implements GetDashboardStatsUseCase {
  final DashboardStatsEntity stats;
  _FakeDashboardStatsUseCase(this.stats);

  @override
  Future<Either<Failure, DashboardStatsEntity>> call() async => Right(stats);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInstallmentsFacade implements InstallmentsFacade {
  final InstallmentSummary summary;
  _FakeInstallmentsFacade(this.summary);

  @override
  Future<Either<Failure, InstallmentSummary>> getSummary({DateTime? now}) async {
    return Right(summary);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockCustomerLedgerService extends CustomerLedgerService {
  final CustomerStatement mockStatement;
  _MockCustomerLedgerService(this.mockStatement)
      : super(GetIt.instance<AppDatabase>());

  @override
  Future<CustomerStatement> getCustomerStatement(String customerId) async {
    return mockStatement;
  }
}
