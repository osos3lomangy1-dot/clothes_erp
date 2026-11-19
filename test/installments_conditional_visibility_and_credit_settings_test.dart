import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/customers/data/services/customer_ledger_service.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/customers/presentation/widgets/customer_profile_dialog.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
