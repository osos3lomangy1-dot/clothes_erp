import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/sales_report_entity.dart';

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

    // 1. Fetch sales within date range (excluding soft-deleted)
    final salesQuery = _db.select(_db.sales)
      ..where((s) =>
          s.date.isBiggerOrEqualValue(start) &
          s.date.isSmallerOrEqualValue(end) &
          s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm.desc(s.date)]);

    final salesRows = await salesQuery.get();

    int totalRevenue = 0;
    final Map<String, int> paymentBreakdown = {};
    final List<String> saleIds = [];

    for (final s in salesRows) {
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

    final totalProfit = totalRevenue - totalCost;

    // 3. Calculate expenses in this period
    final expensesQuery = _db.select(_db.expenses)
      ..where((e) =>
          e.expenseDate.isBiggerOrEqualValue(start) &
          e.expenseDate.isSmallerOrEqualValue(end) &
          e.deletedAt.isNull());
    final expenseRows = await expensesQuery.get();
    final totalExpenses = expenseRows.fold<int>(0, (sum, e) => sum + e.amount);

    return SalesReportEntity(
      startDate: startDate,
      endDate: endDate,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      totalProfit: totalProfit,
      totalExpenses: totalExpenses,
      totalTransactions: salesRows.length,
      paymentMethodBreakdown: paymentBreakdown,
    );
  }
}
