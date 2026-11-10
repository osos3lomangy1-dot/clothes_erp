import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../../domain/entities/sales_chart_point_entity.dart';

abstract class DashboardLocalDataSource {
  Future<DashboardStatsEntity> getDashboardStats();
}

@LazySingleton(as: DashboardLocalDataSource)
class DashboardLocalDataSourceImpl implements DashboardLocalDataSource {
  final AppDatabase _db;

  DashboardLocalDataSourceImpl(this._db);

  @override
  Future<DashboardStatsEntity> getDashboardStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // 1. Today's sales from Drift
    final todaySalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(startOfDay) &
              s.date.isSmallerOrEqualValue(endOfDay) &
              s.deletedAt.isNull()))
        .get();

    final int todaySales = todaySalesRows.fold<int>(0, (sum, s) => sum + s.total);
    final int todayTransactions = todaySalesRows.length;

    // 2. Low stock variants (quantity <= minStock)
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
        color: v.color,
        size: v.size,
        quantity: v.quantity,
        costPrice: v.costPrice,
        salePrice: v.sellPrice,
        minStock: p.minStock,
        createdAt: v.createdAt,
      );
    }).toList();

    // 3. Last 7 Days Sales Trend
    final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final weekSalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(sevenDaysAgo) &
              s.date.isSmallerOrEqualValue(endOfDay) &
              s.deletedAt.isNull()))
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

    // 4. Today Hourly Sales Distribution (0 to 23)
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

    return DashboardStatsEntity(
      todaySales: todaySales,
      todayTransactions: todayTransactions,
      lowStockCount: lowStockVariants.length,
      lowStockVariants: lowStockVariants,
      last7DaysSales: last7DaysSales,
      todayHourlySales: todayHourlySales,
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
