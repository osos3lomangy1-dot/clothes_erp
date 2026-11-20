import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/smart_inventory_entities.dart';
import '../../domain/repositories/smart_inventory_repository.dart';

@LazySingleton(as: SmartInventoryRepository)
class SmartInventoryRepositoryImpl implements SmartInventoryRepository {
  final AppDatabase _db;

  SmartInventoryRepositoryImpl(this._db);

  @override
  Future<Either<Failure, List<ReorderSuggestionEntity>>> getReorderSuggestions({
    int days = 30,
  }) async {
    try {
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: days));

      // 1. Fetch all active variants joined with products and categories
      final query = _db.select(_db.productVariants).join([
        innerJoin(
          _db.products,
          _db.products.id.equalsExp(_db.productVariants.productId),
        ),
        leftOuterJoin(
          _db.categories,
          _db.categories.id.equalsExp(_db.products.categoryId),
        ),
      ])..where(_db.productVariants.deletedAt.isNull() & _db.products.deletedAt.isNull());

      final rows = await query.get();

      // 2. Fetch sales volume in the last N days
      final salesQuery = _db.select(_db.saleItems).join([
        innerJoin(
          _db.sales,
          _db.sales.id.equalsExp(_db.saleItems.saleId),
        ),
      ])..where(
          _db.sales.date.isBiggerOrEqualValue(cutoffDate) &
          _db.sales.deletedAt.isNull(),
        );

      final salesRows = await salesQuery.get();
      final salesMap = <String, int>{};
      for (final r in salesRows) {
        final item = r.readTable(_db.saleItems);
        salesMap[item.variantId] = (salesMap[item.variantId] ?? 0) + item.qty;
      }

      // 3. Filter low stock variants and calculate suggestions
      final suggestions = <ReorderSuggestionEntity>[];

      for (final r in rows) {
        final variant = r.readTable(_db.productVariants);
        final product = r.readTable(_db.products);
        final category = r.readTableOrNull(_db.categories);

        final minStock = product.minStock > 0 ? product.minStock : 5;
        if (variant.quantity <= minStock) {
          final sold = salesMap[variant.id] ?? 0;
          final dailyRate = sold / (days > 0 ? days : 30);

          // Suggested: target safety stock (minStock * 2 or projected 30-day demand) minus current
          var suggested = (minStock * 2) - variant.quantity;
          final projectedDemand = (dailyRate * 30).ceil();
          if (projectedDemand > suggested) {
            suggested = projectedDemand - variant.quantity;
          }
          if (suggested < 1) suggested = minStock;

          final cost = variant.costPrice;
          final totalCost = suggested * cost;

          suggestions.add(
            ReorderSuggestionEntity(
              variantId: variant.id,
              productId: product.id,
              productName: product.name,
              sku: variant.sku,
              categoryName: category?.name ?? 'غير مصنف',
              color: variant.color,
              size: variant.size,
              currentStock: variant.quantity,
              minStock: minStock,
              soldLast30Days: sold,
              dailySalesRate: dailyRate,
              suggestedReorderQty: suggested,
              costPricePiasters: cost,
              totalEstimatedCostPiasters: totalCost,
            ),
          );
        }
      }

      // Sort by current stock ascending (critical shortages first)
      suggestions.sort((a, b) => a.currentStock.compareTo(b.currentStock));

      return Right(suggestions);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل اقتراحات طلب الشراء: $e'));
    }
  }

  @override
  Future<Either<Failure, List<DeadStockItemEntity>>> getDeadStock({
    int dormantDays = 60,
  }) async {
    try {
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: dormantDays));

      // 1. Fetch all variants that currently have stock > 0
      final query = _db.select(_db.productVariants).join([
        innerJoin(
          _db.products,
          _db.products.id.equalsExp(_db.productVariants.productId),
        ),
        leftOuterJoin(
          _db.categories,
          _db.categories.id.equalsExp(_db.products.categoryId),
        ),
      ])..where(
          _db.productVariants.deletedAt.isNull() &
          _db.products.deletedAt.isNull() &
          _db.productVariants.quantity.isBiggerThanValue(0),
        );

      final rows = await query.get();

      // 2. Fetch all sales within the dormant window
      final recentSalesQuery = _db.select(_db.saleItems).join([
        innerJoin(
          _db.sales,
          _db.sales.id.equalsExp(_db.saleItems.saleId),
        ),
      ])..where(
          _db.sales.date.isBiggerOrEqualValue(cutoffDate) &
          _db.sales.deletedAt.isNull(),
        );

      final recentSales = await recentSalesQuery.get();
      final soldVariantIds = recentSales.map((r) => r.readTable(_db.saleItems).variantId).toSet();

      // 3. Filter for dormant variants (not sold in recent window)
      final deadStockItems = <DeadStockItemEntity>[];

      for (final r in rows) {
        final variant = r.readTable(_db.productVariants);
        if (soldVariantIds.contains(variant.id)) continue;

        final product = r.readTable(_db.products);
        final category = r.readTableOrNull(_db.categories);

        final frozenCapital = variant.quantity * variant.costPrice;
        final lostRevenue = variant.quantity * variant.sellPrice;

        deadStockItems.add(
          DeadStockItemEntity(
            variantId: variant.id,
            productId: product.id,
            productName: product.name,
            sku: variant.sku,
            categoryName: category?.name ?? 'غير مصنف',
            color: variant.color,
            size: variant.size,
            currentStock: variant.quantity,
            costPricePiasters: variant.costPrice,
            sellPricePiasters: variant.sellPrice,
            frozenCapitalPiasters: frozenCapital,
            lostRevenuePotentialPiasters: lostRevenue,
            daysWithoutSale: dormantDays,
          ),
        );
      }

      // Sort by frozen capital descending (highest stagnant money first)
      deadStockItems.sort((a, b) => b.frozenCapitalPiasters.compareTo(a.frozenCapitalPiasters));

      return Right(deadStockItems);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل تقرير البضاعة الراكدة: $e'));
    }
  }

  @override
  Future<Either<Failure, List<StockMovementCardItemEntity>>> getStockMovementCard(
    String variantId,
  ) async {
    try {
      final query = _db.select(_db.inventoryLogs).join([
        leftOuterJoin(
          _db.users,
          _db.users.id.equalsExp(_db.inventoryLogs.userId),
        ),
      ])
        ..where(_db.inventoryLogs.variantId.equals(variantId))
        ..orderBy([
          OrderingTerm(
            expression: _db.inventoryLogs.createdAt,
            mode: OrderingMode.asc,
          ),
        ]);

      final rows = await query.get();

      var runningBalance = 0;
      final items = <StockMovementCardItemEntity>[];

      for (final r in rows) {
        final log = r.readTable(_db.inventoryLogs);
        final user = r.readTableOrNull(_db.users);

        runningBalance += log.qtyDelta;

        String typeLabel;
        switch (log.type.toLowerCase()) {
          case 'sale':
            typeLabel = 'فاتورة مبيعات';
            break;
          case 'return':
          case 'return_':
          case 'sale_return':
            typeLabel = 'مرتجع مبيعات';
            break;
          case 'receive':
          case 'goods_receipt':
          case 'purchase':
            typeLabel = 'استلام / توريد بضاعة';
            break;
          case 'adjustment':
            typeLabel = 'تسوية رصيد جردي';
            break;
          case 'stocktake':
            typeLabel = 'جرد مخزني';
            break;
          case 'waste':
          case 'damage':
            typeLabel = 'هالك وتالف';
            break;
          default:
            typeLabel = log.type;
        }

        items.add(
          StockMovementCardItemEntity(
            logId: log.id,
            date: log.createdAt,
            type: log.type,
            typeLabel: typeLabel,
            qtyDelta: log.qtyDelta,
            runningBalance: runningBalance,
            refType: log.refType,
            refId: log.refId,
            reason: log.reason,
            userName: user?.displayName ?? user?.username ?? log.userId,
          ),
        );
      }

      // Return reverse chronological (newest transactions at the top)
      return Right(items.reversed.toList());
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل كارت حركة الصنف: $e'));
    }
  }

  @override
  Future<Either<Failure, List<({String id, String label, String sku})>>>
      getVariantsForCardPicker() async {
    try {
      final query = _db.select(_db.productVariants).join([
        innerJoin(
          _db.products,
          _db.products.id.equalsExp(_db.productVariants.productId),
        ),
      ])..where(_db.productVariants.deletedAt.isNull() & _db.products.deletedAt.isNull());

      final rows = await query.get();
      final list = rows.map((r) {
        final v = r.readTable(_db.productVariants);
        final p = r.readTable(_db.products);
        final label = '${p.name} (${v.color != '-' ? v.color : ''} ${v.size != '-' ? v.size : ''}) - رصيد: ${v.quantity}'.trim();
        return (id: v.id, label: label, sku: v.sku);
      }).toList();

      list.sort((a, b) => a.label.compareTo(b.label));
      return Right(list);
    } catch (e) {
      return Left(ServerFailure('تعذر تحميل قائمة الأصناف: $e'));
    }
  }
}

