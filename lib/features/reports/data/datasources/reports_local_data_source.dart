import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../../dashboard/domain/entities/sales_chart_point_entity.dart';
import '../../domain/entities/sales_report_entity.dart';
import '../../domain/entities/top_product_report_entity.dart';
import '../../domain/services/date_range_presets.dart';

abstract class ReportsLocalDataSource {
  Future<SalesReportEntity> getSalesReport({
    required DateTime startDate,
    required DateTime endDate,
  });
}

@LazySingleton(as: ReportsLocalDataSource)
class ReportsLocalDataSourceImpl implements ReportsLocalDataSource {
  final AppDatabase _db;

  ReportsLocalDataSourceImpl(this._db);

  @override
  Future<SalesReportEntity> getSalesReport({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    // 1. Fetch sales within date range (excluding soft-deleted and cancelled)
    final salesQuery = _db.select(_db.sales)
      ..where((s) =>
          s.date.isBiggerOrEqualValue(start) &
          s.date.isSmallerOrEqualValue(end) &
          s.deletedAt.isNull() &
          s.status.isNotValue('cancelled'))
      ..orderBy([(s) => OrderingTerm.desc(s.date)]);

    final salesRows = await salesQuery.get();

    // Exclude installment-contract sales from P&L revenue & COGS
    final installmentSales = await (_db.select(_db.customerInstallments)
          ..where((ci) => ci.deletedAt.isNull()))
        .get();
    final installmentSaleIds = installmentSales.map((ci) => ci.saleId).toSet();

    final nonInstallmentSales = salesRows
        .where((s) => !installmentSaleIds.contains(s.id) && s.paymentMethod != 'installment')
        .toList();

    int totalRevenue = 0;
    final Map<String, int> paymentBreakdown = {};
    final List<String> saleIds = [];

    for (final s in nonInstallmentSales) {
      totalRevenue += s.total;
      final method = s.paymentMethod.isNotEmpty ? s.paymentMethod : 'cash';
      paymentBreakdown[method] = (paymentBreakdown[method] ?? 0) + s.total;
      saleIds.add(s.id);
    }

    // 2. Calculate total cost using costPrice from product_variants
    int totalCost = 0;
    if (saleIds.isNotEmpty) {
      final itemsQuery = _db.select(_db.saleItems).join([
        innerJoin(
          _db.productVariants,
          _db.productVariants.id.equalsExp(_db.saleItems.variantId),
        ),
      ])..where(_db.saleItems.saleId.isIn(saleIds));

      final itemsRows = await itemsQuery.get();
      for (final r in itemsRows) {
        final item = r.readTable(_db.saleItems);
        final variant = r.readTable(_db.productVariants);
        final unitCost = variant.costPrice > 0 ? variant.costPrice : item.costSnapshot;
        totalCost += unitCost * item.qty;
      }
    }

    final deliveredRepairs = await (_db.select(_db.repairTickets)
          ..where((r) =>
              r.status.equals('delivered') &
              r.deliveredAt.isBiggerOrEqualValue(start) &
              r.deliveredAt.isSmallerOrEqualValue(end) &
              r.deletedAt.isNull()))
        .get();
    final int repairRevenue =
        deliveredRepairs.fold<int>(0, (sum, r) => sum + r.finalCost);
    final int repairPartsCost =
        deliveredRepairs.fold<int>(0, (sum, r) => sum + r.partsCost);

    final int effectiveTotalRevenue = totalRevenue + repairRevenue;
    final int effectiveTotalCost = totalCost + repairPartsCost;
    final totalProfit = effectiveTotalRevenue - effectiveTotalCost;

    // 3. Calculate expenses in this period (operating expenses only)
    final expensesQuery = _db.select(_db.expenses)
      ..where((e) =>
          e.kind.equals('operating') &
          e.expenseDate.isBiggerOrEqualValue(start) &
          e.expenseDate.isSmallerOrEqualValue(end) &
          e.deletedAt.isNull());
    final expenseRows = await expensesQuery.get();
    final totalExpenses = expenseRows.fold<int>(0, (sum, e) => sum + e.amount);

    // 4. Calculate top 5 best selling products, most profitable products & category breakdown
    final List<TopProductReportEntity> topSellingProducts = [];
    final List<TopProductReportEntity> mostProfitableProducts = [];
    final Map<String, int> categoryRevenueBreakdown = {};
    if (saleIds.isNotEmpty) {
      final topQuery = _db.select(_db.saleItems).join([
        innerJoin(_db.productVariants, _db.productVariants.id.equalsExp(_db.saleItems.variantId)),
        innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
        leftOuterJoin(_db.categories, _db.categories.id.equalsExp(_db.products.categoryId)),
      ])..where(_db.saleItems.saleId.isIn(saleIds));

      final topRows = await topQuery.get();
      final Map<String, ({
        String productName,
        String sku,
        String color,
        String size,
        int qty,
        int totalRevenue,
        int netProfit,
      })> variantMap = {};

      for (final r in topRows) {
        final item = r.readTable(_db.saleItems);
        final variant = r.readTable(_db.productVariants);
        final product = r.readTable(_db.products);
        final category = r.readTableOrNull(_db.categories);

        final catName = (category != null && category.name.trim().isNotEmpty)
            ? category.name.trim()
            : 'غير مصنف';
        categoryRevenueBreakdown[catName] =
            (categoryRevenueBreakdown[catName] ?? 0) + item.lineTotal;

        final revenue = item.lineTotal;
        final unitCost = variant.costPrice > 0 ? variant.costPrice : item.costSnapshot;
        final meterMatch =
            RegExp(r'•\s*([\d.]+)\s*م').firstMatch(item.size) ??
            RegExp(r'([\d.]+)\s*م').allMatches(item.size).lastOrNull;
        final effQty = meterMatch != null
            ? (double.tryParse(meterMatch.group(1)!) ?? item.qty.toDouble())
            : item.qty.toDouble();
        final lineProfit = revenue - (unitCost * effQty).round();

        final existing = variantMap[variant.id];
        if (existing == null) {
          variantMap[variant.id] = (
            productName: product.name,
            sku: variant.sku,
            color: variant.color,
            size: variant.size,
            qty: item.qty,
            totalRevenue: revenue,
            netProfit: lineProfit,
          );
        } else {
          variantMap[variant.id] = (
            productName: existing.productName,
            sku: existing.sku,
            color: existing.color,
            size: existing.size,
            qty: existing.qty + item.qty,
            totalRevenue: existing.totalRevenue + revenue,
            netProfit: existing.netProfit + lineProfit,
          );
        }
      }

      final sortedByQty = variantMap.entries.toList()
        ..sort((a, b) => b.value.qty.compareTo(a.value.qty));

      topSellingProducts.addAll(
        sortedByQty.take(5).map(
              (e) => TopProductReportEntity(
                variantId: e.key,
                productName: e.value.productName,
                sku: e.value.sku,
                color: e.value.color,
                size: e.value.size,
                quantitySold: e.value.qty,
                totalRevenue: e.value.totalRevenue,
                netProfitPiasters: e.value.netProfit,
              ),
            ),
      );

      final sortedByProfit = variantMap.entries.toList()
        ..sort((a, b) => b.value.netProfit.compareTo(a.value.netProfit));

      mostProfitableProducts.addAll(
        sortedByProfit.take(5).map(
              (e) => TopProductReportEntity(
                variantId: e.key,
                productName: e.value.productName,
                sku: e.value.sku,
                color: e.value.color,
                size: e.value.size,
                quantitySold: e.value.qty,
                totalRevenue: e.value.totalRevenue,
                netProfitPiasters: e.value.netProfit,
              ),
            ),
      );
    }

    // 4b. Daily sales trend & Hourly distribution for the selected period
    final Map<String, ({int total, int count})> dayTotals = {};
    final Map<int, ({int total, int count})> hourMap = {};
    for (final s in nonInstallmentSales) {
      final key =
          '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
      final curDay = dayTotals[key] ?? (total: 0, count: 0);
      dayTotals[key] = (total: curDay.total + s.total, count: curDay.count + 1);

      final h = s.date.hour;
      final curHour = hourMap[h] ?? (total: 0, count: 0);
      hourMap[h] = (total: curHour.total + s.total, count: curHour.count + 1);
    }

    final List<DailySalesPointEntity> dailySalesTrend = [];
    final startDayOnly = DateTime(start.year, start.month, start.day);
    final endDayOnly = DateTime(end.year, end.month, end.day);
    final totalDays = endDayOnly.difference(startDayOnly).inDays + 1;
    for (int i = 0; i < totalDays; i++) {
      final d = startDayOnly.add(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final stats = dayTotals[key] ?? (total: 0, count: 0);
      dailySalesTrend.add(DailySalesPointEntity(
        date: d,
        dayLabel: '${d.day}/${d.month}',
        totalAmount: stats.total,
        transactionsCount: stats.count,
      ));
    }

    final List<HourlySalesPointEntity> hourlySalesDistribution = [];
    for (int h = 0; h < 24; h++) {
      final stats = hourMap[h] ?? (total: 0, count: 0);
      hourlySalesDistribution.add(HourlySalesPointEntity(
        hour: h,
        hourLabel: _formatHourLabel(h),
        totalAmount: stats.total,
        transactionsCount: stats.count,
      ));
    }

    // 4c. Previous comparable period (Period-over-Period Growth)
    final prevRange = DateRangeEngine.previousComparableRange(start, end);
    final prevSalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(prevRange.start) &
              s.date.isSmallerOrEqualValue(prevRange.end) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final prevNonInstallment = prevSalesRows
        .where((s) => !installmentSaleIds.contains(s.id) && s.paymentMethod != 'installment')
        .toList();
    final int previousTotalRevenue =
        prevNonInstallment.fold<int>(0, (sum, s) => sum + s.total);
    final int previousTotalTransactions = prevNonInstallment.length;
    final prevSaleIds = prevNonInstallment.map((s) => s.id).toList();

    int prevCost = 0;
    if (prevSaleIds.isNotEmpty) {
      final prevItemsRows = await (_db.select(_db.saleItems).join([
        innerJoin(
          _db.productVariants,
          _db.productVariants.id.equalsExp(_db.saleItems.variantId),
        ),
      ])..where(_db.saleItems.saleId.isIn(prevSaleIds))).get();
      for (final r in prevItemsRows) {
        final item = r.readTable(_db.saleItems);
        final variant = r.readTable(_db.productVariants);
        final unitCost = variant.costPrice > 0 ? variant.costPrice : item.costSnapshot;
        prevCost += unitCost * item.qty;
      }
    }
    final prevExpenseRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(prevRange.start) &
              e.expenseDate.isSmallerOrEqualValue(prevRange.end) &
              e.deletedAt.isNull()))
        .get();
    final int prevExpenses = prevExpenseRows.fold<int>(0, (sum, e) => sum + e.amount);
    final prevDeliveredRepairs = await (_db.select(_db.repairTickets)
          ..where((r) =>
              r.status.equals('delivered') &
              r.deliveredAt.isBiggerOrEqualValue(prevRange.start) &
              r.deliveredAt.isSmallerOrEqualValue(prevRange.end) &
              r.deletedAt.isNull()))
        .get();
    final int prevRepairProfit = prevDeliveredRepairs.fold<int>(
      0,
      (sum, r) => sum + (r.finalCost - r.partsCost),
    );
    final int previousNetProfit =
        previousTotalRevenue - prevCost - prevExpenses + prevRepairProfit;

    // 4d. Inventory cost capital (active stock * costPrice)
    final stockRows = await (_db.select(_db.productVariants).join([
      innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
    ])..where(_db.productVariants.deletedAt.isNull() & _db.products.deletedAt.isNull()))
        .get();
    int inventoryCostCapitalPiasters = 0;
    for (final r in stockRows) {
      final v = r.readTable(_db.productVariants);
      if (v.quantity > 0 && v.costPrice > 0) {
        inventoryCostCapitalPiasters += v.quantity * v.costPrice;
      }
    }

    // 5. Total returns in period
    final returnsQuery = _db.select(_db.returns)
      ..where((r) =>
          r.date.isBiggerOrEqualValue(start) &
          r.date.isSmallerOrEqualValue(end) &
          r.deletedAt.isNull());
    final returnsRows = await returnsQuery.get();
    final int totalReturns = returnsRows.fold<int>(0, (sum, r) => sum + r.refundAmount);

    // 5. Two-Section Financial Report: Cash Flow section from cash_movements
    final startSec = start.millisecondsSinceEpoch ~/ 1000;
    final endSec = end.millisecondsSinceEpoch ~/ 1000;

    final cashMovementsQuery = _db.select(_db.cashMovements)
      ..where((cm) =>
          cm.createdAt.isBiggerOrEqualValue(startSec) &
          cm.createdAt.isSmallerOrEqualValue(endSec) &
          cm.deletedAt.isNull());
    final movementRows = await cashMovementsQuery.get();

    int cashFlowIn = 0;
    int cashFlowOut = 0;
    final Map<String, int> cashFlowInByMethod = {};
    final Map<String, int> cashFlowOutByMethod = {};

    for (final m in movementRows) {
      final method = m.method.isNotEmpty ? m.method : 'cash';
      if (m.direction == 'in') {
        cashFlowIn += m.amountPiasters;
        cashFlowInByMethod[method] = (cashFlowInByMethod[method] ?? 0) + m.amountPiasters;
      } else if (m.direction == 'out') {
        cashFlowOut += m.amountPiasters;
        cashFlowOutByMethod[method] = (cashFlowOutByMethod[method] ?? 0) + m.amountPiasters;
      }
    }

    return SalesReportEntity(
      startDate: startDate,
      endDate: endDate,
      totalRevenue: effectiveTotalRevenue,
      totalCost: effectiveTotalCost,
      totalProfit: totalProfit,
      totalExpenses: totalExpenses,
      totalReturns: totalReturns,
      totalTransactions: nonInstallmentSales.length,
      paymentMethodBreakdown: paymentBreakdown,
      topSellingProducts: topSellingProducts,
      cashFlowIn: cashFlowIn,
      cashFlowOut: cashFlowOut,
      cashFlowInByMethod: cashFlowInByMethod,
      cashFlowOutByMethod: cashFlowOutByMethod,
      previousTotalRevenue: previousTotalRevenue,
      previousNetProfit: previousNetProfit,
      previousTotalTransactions: previousTotalTransactions,
      inventoryCostCapitalPiasters: inventoryCostCapitalPiasters,
      dailySalesTrend: dailySalesTrend,
      hourlySalesDistribution: hourlySalesDistribution,
      categoryRevenueBreakdown: categoryRevenueBreakdown,
      mostProfitableProducts: mostProfitableProducts,
    );
  }

  String _formatHourLabel(int hour) {
    if (hour == 0) return '12 ص';
    if (hour < 12) return '$hour ص';
    if (hour == 12) return '12 م';
    return '${hour - 12} م';
  }
}
