import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/dashboard/domain/entities/sales_chart_point_entity.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';
import 'package:clothes_erp/features/reports/domain/entities/top_product_report_entity.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/category_breakdown_donut_chart.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/daily_trend_line_chart.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/most_profitable_products_widget.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 32: Advanced Visual Analytics Data & Widgets', () {
    test('ReportsLocalDataSource computes dailyTrend, hourlyDist, categoryBreakdown & mostProfitableProducts by net profit', () async {
      final now = DateTime.now();
      final day1 = DateTime(now.year, now.month, now.day, 11, 0);
      final day0 = day1.subtract(const Duration(days: 1));
      final reportsDs = ReportsLocalDataSourceImpl(db);

      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat_high_qty',
        branchId: branchId,
        name: 'إكسسوارات',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat_high_profit',
        branchId: branchId,
        name: 'أجهزة كهربائية',
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p_low_margin',
        branchId: branchId,
        name: 'كابل شحن',
        categoryId: 'cat_high_qty',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p_high_margin',
        branchId: branchId,
        name: 'ثلاجة ديجيتال',
        categoryId: 'cat_high_profit',
        createdAt: now,
        updatedAt: now,
      ));

      // High qty (10 pcs), tiny profit: 10 * (1200 - 1000) = 2000 piasters profit
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v_cable',
        branchId: branchId,
        productId: 'p_low_margin',
        sku: 'CAB-1',
        color: 'أسود',
        size: '1م',
        quantity: const Value(50),
        costPrice: 1000,
        sellPrice: 1200,
        createdAt: now,
        updatedAt: now,
      ));

      // Low qty (1 pc), huge profit: 1 * (500000 - 300000) = 200000 piasters profit
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v_fridge',
        branchId: branchId,
        productId: 'p_high_margin',
        sku: 'FRG-1',
        color: 'فضي',
        size: '18 قدم',
        quantity: const Value(4),
        costPrice: 300000,
        sellPrice: 500000,
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 's_d0',
        branchId: branchId,
        shortRef: 'SD0',
        cashierId: 'c1',
        subtotal: 12000,
        discountType: 'none',
        total: 12000,
        paymentMethod: 'cash',
        status: const Value('completed'),
        date: day0,
        createdAt: day0,
        updatedAt: day0,
      ));
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'si_d0',
        branchId: branchId,
        saleId: 's_d0',
        variantId: 'v_cable',
        productName: 'كابل شحن',
        color: 'أسود',
        size: '1م',
        qty: 10,
        priceSnapshot: 1200,
        costSnapshot: 1000,
        lineTotal: 12000,
        createdAt: day0,
      ));

      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 's_d1',
        branchId: branchId,
        shortRef: 'SD1',
        cashierId: 'c1',
        subtotal: 500000,
        discountType: 'none',
        total: 500000,
        paymentMethod: 'card',
        status: const Value('completed'),
        date: day1,
        createdAt: day1,
        updatedAt: day1,
      ));
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'si_d1',
        branchId: branchId,
        saleId: 's_d1',
        variantId: 'v_fridge',
        productName: 'ثلاجة ديجيتال',
        color: 'فضي',
        size: '18 قدم',
        qty: 1,
        priceSnapshot: 500000,
        costSnapshot: 300000,
        lineTotal: 500000,
        createdAt: day1,
      ));

      final report = await reportsDs.getSalesReport(
        startDate: DateTime(day0.year, day0.month, day0.day, 0, 0, 0),
        endDate: DateTime(day1.year, day1.month, day1.day, 23, 59, 59, 999),
      );

      // 2 days in dailySalesTrend
      expect(report.dailySalesTrend.length, 2);
      expect(report.dailySalesTrend[0].totalAmount, 12000);
      expect(report.dailySalesTrend[1].totalAmount, 500000);

      // 24 hours distribution, hour 11 has 512000
      expect(report.hourlySalesDistribution.length, 24);
      expect(report.hourlySalesDistribution[11].totalAmount, 512000);

      // Category breakdown
      expect(report.categoryRevenueBreakdown['إكسسوارات'], 12000);
      expect(report.categoryRevenueBreakdown['أجهزة كهربائية'], 500000);

      // topSellingProducts is sorted by QTY -> cable first
      expect(report.topSellingProducts.first.variantId, 'v_cable');

      // mostProfitableProducts is sorted by NET PROFIT -> fridge first!
      expect(report.mostProfitableProducts.first.variantId, 'v_fridge');
      expect(report.mostProfitableProducts.first.netProfitPiasters, 200000);
    });

    testWidgets('Task 32 chart widgets render cleanly on narrow width without overflow', (tester) async {
      tester.view.physicalSize = const Size(380, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListView(
                children: [
                  DailyTrendLineChart(
                    points: [
                      DailySalesPointEntity(
                        date: DateTime(2026, 11, 23),
                        dayLabel: '23/11',
                        totalAmount: 100000,
                        transactionsCount: 3,
                      ),
                      DailySalesPointEntity(
                        date: DateTime(2026, 11, 24),
                        dayLabel: '24/11',
                        totalAmount: 250000,
                        transactionsCount: 5,
                      ),
                    ],
                  ),
                  const CategoryBreakdownDonutChart(
                    categoryBreakdown: {
                      'أجهزة كهربائية': 500000,
                      'مفروشات وستائر': 250000,
                    },
                  ),
                  const MostProfitableProductsWidget(
                    products: [
                      TopProductReportEntity(
                        variantId: 'v1',
                        productName: 'ثلاجة ديجيتال',
                        sku: 'FRG-1',
                        color: 'فضي',
                        size: '18 قدم',
                        quantitySold: 1,
                        totalRevenue: 500000,
                        netProfitPiasters: 200000,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ثلاجة ديجيتال'), findsOneWidget);
      expect(find.text('أجهزة كهربائية'), findsOneWidget);
    });
  });
}

