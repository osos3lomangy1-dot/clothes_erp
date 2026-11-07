import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../domain/entities/dashboard_stats_entity.dart';

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

    return DashboardStatsEntity(
      todaySales: todaySales,
      todayTransactions: todayTransactions,
      lowStockCount: lowStockVariants.length,
      lowStockVariants: lowStockVariants,
    );
  }
}
