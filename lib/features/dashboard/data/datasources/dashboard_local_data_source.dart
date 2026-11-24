import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../reports/domain/entities/top_product_report_entity.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../../domain/entities/sales_chart_point_entity.dart';

abstract class DashboardLocalDataSource {
  Future<DashboardStatsEntity> getDashboardStats();
  Stream<void> watchDashboardUpdates();
}

@LazySingleton(as: DashboardLocalDataSource)
class DashboardLocalDataSourceImpl implements DashboardLocalDataSource {
  final AppDatabase _db;

  DashboardLocalDataSourceImpl(this._db);

  @override
  Stream<void> watchDashboardUpdates() => _db.tableUpdates();

  @override
  Future<DashboardStatsEntity> getDashboardStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // 1. Today's sales from Drift (excluding cancelled invoices)
    final todaySalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(startOfDay) &
              s.date.isSmallerOrEqualValue(endOfDay) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    final int todaySales = todaySalesRows.fold<int>(0, (sum, s) => sum + s.total);
    final int todayTransactions = todaySalesRows.length;

    // Payment breakdown & sale IDs
    final Map<String, int> todayPaymentBreakdown = {};
    final List<String> todaySaleIds = [];
    for (final s in todaySalesRows) {
      final method = s.paymentMethod.isNotEmpty ? s.paymentMethod : 'cash';
      todayPaymentBreakdown[method] = (todayPaymentBreakdown[method] ?? 0) + s.total;
      todaySaleIds.add(s.id);
    }

    // 2. Today Cost (COGS) & Expenses -> Net Profit
    int todayCost = 0;
    if (todaySaleIds.isNotEmpty) {
      final itemsQuery = _db.select(_db.saleItems).join([
        innerJoin(
          _db.productVariants,
          _db.productVariants.id.equalsExp(_db.saleItems.variantId),
        ),
      ])..where(_db.saleItems.saleId.isIn(todaySaleIds));

      final itemsRows = await itemsQuery.get();
      for (final r in itemsRows) {
        final item = r.readTable(_db.saleItems);
        final variant = r.readTable(_db.productVariants);
        final unitCost = variant.costPrice > 0 ? variant.costPrice : item.costSnapshot;
        todayCost += unitCost * item.qty;
      }
    }

    final todayExpensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(startOfDay) &
              e.expenseDate.isSmallerOrEqualValue(endOfDay) &
              e.deletedAt.isNull()))
        .get();
    final int todayExpenses = todayExpensesRows.fold<int>(0, (sum, e) => sum + e.amount);
    final int todayEstimatedNetProfit = todaySales - todayCost - todayExpenses;

    // 3. Today Returns
    final returnRows = await (_db.select(_db.returns)
          ..where((r) =>
              r.date.isBiggerOrEqualValue(startOfDay) &
              r.date.isSmallerOrEqualValue(endOfDay) &
              r.deletedAt.isNull()))
        .get();
    final int todayReturnsTotal = returnRows.fold<int>(0, (sum, r) => sum + r.refundAmount);
    final int todayReturnsCount = returnRows.length;

    // 4. Low stock variants (quantity <= minStock)
    final lowStockQuery = _db.select(_db.productVariants).join([
      innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
    ])..where(_db.productVariants.deletedAt.isNull() &
        _db.products.deletedAt.isNull() &
        _db.productVariants.quantity.isSmallerOrEqual(_db.products.minStock));

    final lowStockRows = await lowStockQuery.get();
    final lowStockVariants = lowStockRows.map((r) {
      final v = r.readTable(_db.productVariants);
      final p = r.readTable(_db.products);
      return VariantEntity(
        id: v.id,
        productId: v.productId,
        productCode: v.sku,
        productName: p.name,
        color: v.color,
        size: v.size,
        quantity: v.quantity,
        costPrice: v.costPrice,
        salePrice: v.sellPrice,
        minStock: p.minStock,
        createdAt: v.createdAt,
      );
    }).toList();

    // 5. Last 7 Days Sales Trend (excluding cancelled invoices)
    final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final weekSalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(sevenDaysAgo) &
              s.date.isSmallerOrEqualValue(endOfDay) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    final Map<String, ({int total, int count})> dayTotals = {};
    for (final s in weekSalesRows) {
      final key = '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
      final current = dayTotals[key] ?? (total: 0, count: 0);
      dayTotals[key] = (total: current.total + s.total, count: current.count + 1);
    }

    final List<DailySalesPointEntity> last7DaysSales = [];
    for (int i = 0; i < 7; i++) {
      final dayDate = sevenDaysAgo.add(Duration(days: i));
      final key = '${dayDate.year}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}';
      final stats = dayTotals[key] ?? (total: 0, count: 0);
      last7DaysSales.add(DailySalesPointEntity(
        date: dayDate,
        dayLabel: _getArabicWeekday(dayDate.weekday),
        totalAmount: stats.total,
        transactionsCount: stats.count,
      ));
    }

    // 6. Today Hourly Sales Distribution (0 to 23)
    final Map<int, ({int total, int count})> hourMap = {};
    for (final s in todaySalesRows) {
      final h = s.date.hour;
      final current = hourMap[h] ?? (total: 0, count: 0);
      hourMap[h] = (total: current.total + s.total, count: current.count + 1);
    }

    final List<HourlySalesPointEntity> todayHourlySales = [];
    for (int h = 0; h < 24; h++) {
      final stats = hourMap[h] ?? (total: 0, count: 0);
      todayHourlySales.add(HourlySalesPointEntity(
        hour: h,
        hourLabel: _formatHourLabel(h),
        totalAmount: stats.total,
        transactionsCount: stats.count,
      ));
    }

    // 7. Today Top 5 Selling Products
    final List<TopProductReportEntity> todayTopProducts = [];
    if (todaySaleIds.isNotEmpty) {
      final topQuery = _db.select(_db.saleItems).join([
        innerJoin(_db.productVariants, _db.productVariants.id.equalsExp(_db.saleItems.variantId)),
        innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
      ])..where(_db.saleItems.saleId.isIn(todaySaleIds));

      final topRows = await topQuery.get();
      final Map<String, ({
        String productName,
        String sku,
        String color,
        String size,
        int qty,
        int totalRevenue,
      })> variantMap = {};

      for (final r in topRows) {
        final item = r.readTable(_db.saleItems);
        final variant = r.readTable(_db.productVariants);
        final product = r.readTable(_db.products);

        final revenue = item.lineTotal;
        final existing = variantMap[variant.id];
        if (existing == null) {
          variantMap[variant.id] = (
            productName: product.name,
            sku: variant.sku,
            color: variant.color,
            size: variant.size,
            qty: item.qty,
            totalRevenue: revenue,
          );
        } else {
          variantMap[variant.id] = (
            productName: existing.productName,
            sku: existing.sku,
            color: existing.color,
            size: existing.size,
            qty: existing.qty + item.qty,
            totalRevenue: existing.totalRevenue + revenue,
          );
        }
      }

      final sorted = variantMap.entries.toList()
        ..sort((a, b) => b.value.qty.compareTo(a.value.qty));

      for (final entry in sorted.take(5)) {
        final val = entry.value;
        todayTopProducts.add(TopProductReportEntity(
          variantId: entry.key,
          productName: val.productName,
          sku: val.sku,
          color: val.color,
          size: val.size,
          quantitySold: val.qty,
          totalRevenue: val.totalRevenue,
        ));
      }
    }

    // 8. Live Shift & Drawer Cash
    final activeShift = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();

    final bool hasActiveShift = activeShift != null;
    String? activeCashierName;
    if (activeShift != null) {
      final user = await (_db.select(_db.users)..where((u) => u.id.equals(activeShift.cashierId))).getSingleOrNull();
      activeCashierName = user?.displayName ?? user?.username ?? activeShift.cashierId;
    }
    final int activeShiftOpeningBalance = activeShift?.openingBalance ?? 0;

    int liveDrawerCash = 0;
    if (activeShift != null) {
      final openedAtSec = activeShift.openedAt.millisecondsSinceEpoch ~/ 1000;
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;

      final movements = await (_db.select(_db.cashMovements)
            ..where((m) =>
                (m.shiftId.equals(activeShift.id) |
                    (m.shiftId.isNull() &
                        m.createdAt.isBiggerOrEqualValue(openedAtSec) &
                        m.createdAt.isSmallerOrEqualValue(nowSec))) &
                m.deletedAt.isNull()))
          .get();

      if (movements.isNotEmpty) {
        final cashIn = movements
            .where((m) => m.method == 'cash' && m.direction == 'in')
            .fold<int>(0, (s, m) => s + m.amountPiasters);
        final cashOut = movements
            .where((m) => m.method == 'cash' && m.direction == 'out')
            .fold<int>(0, (s, m) => s + m.amountPiasters);
        liveDrawerCash = activeShift.openingBalance + cashIn - cashOut;
      } else {
        final cashSales = todaySalesRows
            .where((s) => s.paymentMethod.toLowerCase() == 'cash' || s.paymentMethod.contains('كاش'))
            .fold<int>(0, (s, row) => s + row.total);
        liveDrawerCash = activeShift.openingBalance + cashSales;
      }
    }

    // 9. Overdue Installments
    final overdueInstallmentsQuery = _db.select(_db.customerInstallments)
      ..where((ci) =>
          ci.status.equals('active') &
          ci.endDate.isSmallerThanValue(now) &
          ci.remainingPiasters.isBiggerThanValue(0) &
          ci.deletedAt.isNull());
    final overdueContracts = await overdueInstallmentsQuery.get();
    final int overdueInstallmentsCount = overdueContracts.length;
    final int overdueInstallmentsAmount = overdueContracts.fold<int>(0, (sum, c) => sum + c.remainingPiasters);

    // 10. Supplier Debts
    final suppliers = await (_db.select(_db.suppliers)..where((s) => s.deletedAt.isNull())).get();
    final int totalSupplierDebts = suppliers.fold<int>(0, (sum, s) => sum + s.balance);

    // 11. Customer Credit Debts
    final creditSales = await (_db.select(_db.sales)
          ..where((s) => s.paymentMethod.equals('credit') & s.status.isNotValue('cancelled') & s.deletedAt.isNull()))
        .get();

    final downPayments = await (_db.select(_db.salePayments)
          ..where((sp) => sp.deletedAt.isNull()))
        .get();
    final Map<String, int> saleToDownPayment = {};
    for (final sp in downPayments) {
      saleToDownPayment[sp.saleId] = (saleToDownPayment[sp.saleId] ?? 0) + sp.amountPiasters;
    }
    final totalCreditSales = creditSales.fold<int>(0, (sum, s) {
      final paidDown = saleToDownPayment[s.id] ?? 0;
      final creditPortion = s.total - paidDown;
      return sum + (creditPortion < 0 ? 0 : creditPortion);
    });

    final custPayments = await (_db.select(_db.customerPayments)..where((p) => p.deletedAt.isNull())).get();
    final totalCustPayments = custPayments.fold<int>(0, (sum, p) => sum + p.amount);

    final creditReturns = await (_db.select(_db.returns).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.returns.saleId)),
    ])..where(_db.returns.paymentMethod.equals('credit') & _db.returns.deletedAt.isNull())).get();
    final totalCreditReturns = creditReturns.fold<int>(0, (sum, r) => sum + r.readTable(_db.returns).refundAmount);

    final netCreditDebt = totalCreditSales - totalCustPayments - totalCreditReturns;
    final int totalCustomerCreditDebts = netCreditDebt < 0 ? 0 : netCreditDebt;

    // 12. Yesterday comparison & Inventory cost capital (Tasks 31 & 32)
    final yesterdayStart = startOfDay.subtract(const Duration(days: 1));
    final yesterdayEnd = endOfDay.subtract(const Duration(days: 1));
    final yesterdaySalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(yesterdayStart) &
              s.date.isSmallerOrEqualValue(yesterdayEnd) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final int yesterdaySales =
        yesterdaySalesRows.fold<int>(0, (sum, s) => sum + s.total);
    final yesterdaySaleIds = yesterdaySalesRows.map((s) => s.id).toList();
    int yesterdayCost = 0;
    if (yesterdaySaleIds.isNotEmpty) {
      final yItemsRows = await (_db.select(_db.saleItems).join([
        innerJoin(
          _db.productVariants,
          _db.productVariants.id.equalsExp(_db.saleItems.variantId),
        ),
      ])..where(_db.saleItems.saleId.isIn(yesterdaySaleIds))).get();
      for (final r in yItemsRows) {
        final item = r.readTable(_db.saleItems);
        final variant = r.readTable(_db.productVariants);
        final unitCost = variant.costPrice > 0 ? variant.costPrice : item.costSnapshot;
        yesterdayCost += unitCost * item.qty;
      }
    }
    final yesterdayExpensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(yesterdayStart) &
              e.expenseDate.isSmallerOrEqualValue(yesterdayEnd) &
              e.deletedAt.isNull()))
        .get();
    final int yesterdayExpenses =
        yesterdayExpensesRows.fold<int>(0, (sum, e) => sum + e.amount);
    final int yesterdayNetProfit = yesterdaySales - yesterdayCost - yesterdayExpenses;

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

    return DashboardStatsEntity(
      todaySales: todaySales,
      todayTransactions: todayTransactions,
      todayCost: todayCost,
      todayExpenses: todayExpenses,
      todayEstimatedNetProfit: todayEstimatedNetProfit,
      todayReturnsTotal: todayReturnsTotal,
      todayReturnsCount: todayReturnsCount,
      hasActiveShift: hasActiveShift,
      activeCashierName: activeCashierName,
      activeShiftOpeningBalance: activeShiftOpeningBalance,
      liveDrawerCash: liveDrawerCash,
      lowStockCount: lowStockVariants.length,
      lowStockVariants: lowStockVariants,
      overdueInstallmentsCount: overdueInstallmentsCount,
      overdueInstallmentsAmount: overdueInstallmentsAmount,
      totalSupplierDebts: totalSupplierDebts,
      totalCustomerCreditDebts: totalCustomerCreditDebts,
      last7DaysSales: last7DaysSales,
      todayHourlySales: todayHourlySales,
      todayPaymentBreakdown: todayPaymentBreakdown,
      todayTopProducts: todayTopProducts,
      yesterdaySales: yesterdaySales,
      yesterdayNetProfit: yesterdayNetProfit,
      inventoryCostCapitalPiasters: inventoryCostCapitalPiasters,
    );
  }

  String _getArabicWeekday(int weekday) {
    switch (weekday) {
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      case DateTime.monday:
        return 'الاثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      default:
        return '';
    }
  }

  String _formatHourLabel(int hour) {
    if (hour == 0) return '12 ص';
    if (hour < 12) return '$hour ص';
    if (hour == 12) return '12 م';
    return '${hour - 12} م';
  }
}
