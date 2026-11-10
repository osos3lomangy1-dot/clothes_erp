import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/sales_report_entity.dart';
import '../../domain/entities/top_product_report_entity.dart';

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

    // 4. Calculate top 5 best selling products
    final List<TopProductReportEntity> topSellingProducts = [];
    if (saleIds.isNotEmpty) {
      final topQuery = _db.select(_db.saleItems).join([
        innerJoin(_db.productVariants, _db.productVariants.id.equalsExp(_db.saleItems.variantId)),
        innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
      ])..where(_db.saleItems.saleId.isIn(saleIds));

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

        final revenue = item.priceSnapshot * item.qty;
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

      final sortedList = variantMap.entries.toList()
        ..sort((a, b) => b.value.qty.compareTo(a.value.qty));

      topSellingProducts.addAll(
        sortedList.take(5).map(
              (e) => TopProductReportEntity(
                variantId: e.key,
                productName: e.value.productName,
                sku: e.value.sku,
                color: e.value.color,
                size: e.value.size,
                quantitySold: e.value.qty,
                totalRevenue: e.value.totalRevenue,
              ),
            ),
      );
    }

    return SalesReportEntity(
      startDate: startDate,
      endDate: endDate,
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      totalProfit: totalProfit,
      totalExpenses: totalExpenses,
      totalTransactions: salesRows.length,
      paymentMethodBreakdown: paymentBreakdown,
      topSellingProducts: topSellingProducts,
    );
  }
}
