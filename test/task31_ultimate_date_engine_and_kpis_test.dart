import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';
import 'package:clothes_erp/features/reports/domain/entities/sales_report_entity.dart';
import 'package:clothes_erp/features/reports/domain/services/date_range_presets.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/reports_cubit.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/reports_state.dart';
import 'package:clothes_erp/features/reports/presentation/screens/reports_screen.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeReportsCubit extends Cubit<ReportsState> implements ReportsCubit {
  final List<DateTimeRange> requestedRanges = [];

  _FakeReportsCubit(super.initialState);

  @override
  Future<void> loadReport(DateTime startDate, DateTime endDate) async {
    requestedRanges.add(DateTimeRange(start: startDate, end: endDate));
  }
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 31: DateRangeEngine & Presets', () {
    test('All 8 presets resolve exact 00:00:00 to 23:59:59.999 ranges', () {
      final fixedNow = DateTime(2026, 11, 24, 15, 30); // Tuesday

      final today = DateRangeEngine.resolveRange(QuickDatePreset.today, now: fixedNow);
      expect(today.start, DateTime(2026, 11, 24, 0, 0, 0));
      expect(today.end, DateTime(2026, 11, 24, 23, 59, 59, 999));

      final yesterday = DateRangeEngine.resolveRange(QuickDatePreset.yesterday, now: fixedNow);
      expect(yesterday.start, DateTime(2026, 11, 23, 0, 0, 0));
      expect(yesterday.end, DateTime(2026, 11, 23, 23, 59, 59, 999));

      final thisWeek = DateRangeEngine.resolveRange(QuickDatePreset.thisWeek, now: fixedNow);
      // Tuesday -> Saturday Nov 21
      expect(thisWeek.start, DateTime(2026, 11, 21, 0, 0, 0));
      expect(thisWeek.end, DateTime(2026, 11, 24, 23, 59, 59, 999));

      final thisMonth = DateRangeEngine.resolveRange(QuickDatePreset.thisMonth, now: fixedNow);
      expect(thisMonth.start, DateTime(2026, 11, 1, 0, 0, 0));
      expect(thisMonth.end, DateTime(2026, 11, 24, 23, 59, 59, 999));

      final lastMonth = DateRangeEngine.resolveRange(QuickDatePreset.lastMonth, now: fixedNow);
      expect(lastMonth.start, DateTime(2026, 10, 1, 0, 0, 0));
      expect(lastMonth.end, DateTime(2026, 10, 31, 23, 59, 59, 999));

      final last30 = DateRangeEngine.resolveRange(QuickDatePreset.last30Days, now: fixedNow);
      expect(last30.start, DateTime(2026, 10, 26, 0, 0, 0));
      expect(last30.end, DateTime(2026, 11, 24, 23, 59, 59, 999));

      final thisYear = DateRangeEngine.resolveRange(QuickDatePreset.thisYear, now: fixedNow);
      expect(thisYear.start, DateTime(2026, 1, 1, 0, 0, 0));
      expect(thisYear.end, DateTime(2026, 11, 24, 23, 59, 59, 999));

      expect(QuickDatePreset.values.length, 8);
    });

    test('previousComparableRange computes exact prior period', () {
      final todayRange = DateRangeEngine.resolveRange(
        QuickDatePreset.today,
        now: DateTime(2026, 11, 24, 12, 0),
      );
      final prevToday = DateRangeEngine.previousComparableRange(todayRange.start, todayRange.end);
      expect(prevToday.start, DateTime(2026, 11, 23, 0, 0, 0));
      expect(prevToday.end, DateTime(2026, 11, 23, 23, 59, 59, 999));

      final octFull = DateRangeEngine.resolveRange(
        QuickDatePreset.lastMonth,
        now: DateTime(2026, 11, 24, 12, 0),
      );
      final prevMonth = DateRangeEngine.previousComparableRange(octFull.start, octFull.end);
      expect(prevMonth.start, DateTime(2026, 9, 1, 0, 0, 0));
      expect(prevMonth.end, DateTime(2026, 9, 30, 23, 59, 59, 999));
    });
  });

  group('Task 31: Period Growth, Margin %, AOV & Inventory Capital', () {
    test('ReportsLocalDataSource computes growth %, AOV, margin % & inventory capital', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 14, 0);
      final yesterday = today.subtract(const Duration(days: 1));
      final reportsDs = ReportsLocalDataSourceImpl(db);

      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat1',
        branchId: branchId,
        name: 'أجهزة',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod1',
        branchId: branchId,
        name: 'مروحة',
        categoryId: 'cat1',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v1',
        branchId: branchId,
        productId: 'prod1',
        sku: 'FAN-01',
        color: 'أبيض',
        size: 'قياسي',
        quantity: const Value(5),
        costPrice: 40000, // 5 * 400.00 = 2000.00 EGP (200000 piasters)
        sellPrice: 60000,
        createdAt: now,
        updatedAt: now,
      ));

      // Yesterday sale: 1000.00 EGP, cost 400.00 -> profit 600.00
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 's_prev',
        branchId: branchId,
        shortRef: 'S_PREV',
        cashierId: 'c1',
        subtotal: 100000,
        discountType: 'none',
        total: 100000,
        paymentMethod: 'cash',
        status: const Value('completed'),
        date: yesterday,
        createdAt: yesterday,
        updatedAt: yesterday,
      ));
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'si_prev',
        branchId: branchId,
        saleId: 's_prev',
        variantId: 'v1',
        productName: 'مروحة',
        color: 'أبيض',
        size: 'قياسي',
        qty: 1,
        priceSnapshot: 100000,
        costSnapshot: 40000,
        lineTotal: 100000,
        createdAt: yesterday,
      ));

      // Today 2 sales totaling 1500.00 EGP, cost 800.00 -> netProfit 700.00 -> +50% rev growth
      for (int i = 1; i <= 2; i++) {
        await db.into(db.sales).insert(SalesCompanion.insert(
          id: 's_today_$i',
          branchId: branchId,
          shortRef: 'ST$i',
          cashierId: 'c1',
          subtotal: 75000,
          discountType: 'none',
          total: 75000,
          paymentMethod: 'cash',
          status: const Value('completed'),
          date: today,
          createdAt: today,
          updatedAt: today,
        ));
        await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
          id: 'si_today_$i',
          branchId: branchId,
          saleId: 's_today_$i',
          variantId: 'v1',
          productName: 'مروحة',
          color: 'أبيض',
          size: 'قياسي',
          qty: 1,
          priceSnapshot: 75000,
          costSnapshot: 40000,
          lineTotal: 75000,
          createdAt: today,
        ));
      }

      final report = await reportsDs.getSalesReport(
        startDate: DateTime(today.year, today.month, today.day, 0, 0, 0),
        endDate: DateTime(today.year, today.month, today.day, 23, 59, 59, 999),
      );

      expect(report.totalRevenue, 150000);
      expect(report.previousTotalRevenue, 100000);
      expect(report.revenueGrowthPercent, closeTo(50.0, 0.01));
      expect(report.netProfit, 70000);
      expect(report.previousNetProfit, 60000);
      expect(report.averageOrderValuePiasters, 75000);
      expect(report.profitMarginPercent, closeTo((70000 / 150000) * 100, 0.01));
      expect(report.inventoryCostCapitalPiasters, 200000);

      // Dashboard also computes yesterday comparison & inventory capital
      final dashboardDs = DashboardLocalDataSourceImpl(db);
      final dashStats = await dashboardDs.getDashboardStats();
      expect(dashStats.todaySales, 150000);
      expect(dashStats.yesterdaySales, 100000);
      expect(dashStats.todaySalesGrowthPercent, closeTo(50.0, 0.01));
      expect(dashStats.inventoryCostCapitalPiasters, 200000);
    });

    testWidgets('QuickDateRangeBar in ReportsScreen triggers loadReport on chip tap', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeCubit = _FakeReportsCubit(
        ReportsLoaded(
          SalesReportEntity(
            startDate: DateTime(2026, 11, 1),
            endDate: DateTime(2026, 11, 24),
            totalRevenue: 150000,
            totalCost: 80000,
            totalProfit: 70000,
            totalTransactions: 2,
            paymentMethodBreakdown: const {'cash': 150000},
            previousTotalRevenue: 100000,
            previousNetProfit: 50000,
            inventoryCostCapitalPiasters: 200000,
          ),
        ),
      );

      final fakeAuthCubit = _FakeAuthCubit(
        UserModel(
          id: 'admin_1',
          name: 'المدير العام',
          email: 'admin@test.com',
          role: 'admin',
          isActive: true,
          createdAt: DateTime(2026, 11, 1),
        ),
      );

      final sl = GetIt.instance;
      await sl.reset();
      sl.registerFactory<ReportsCubit>(() => fakeCubit);
      addTearDown(() async => sl.reset());

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: fakeAuthCubit,
              child: const ReportsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "اليوم" chip
      await tester.tap(find.byKey(const Key('quick_date_chip_today')));
      await tester.pumpAndSettle();

      expect(fakeCubit.requestedRanges.length, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });
  });
}

