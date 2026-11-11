import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../inventory/data/datasources/inventory_local_data_source.dart';
import '../../domain/entities/return_entity.dart';
import '../../domain/entities/return_item_entity.dart';

abstract class ReturnsLocalDataSource {
  Future<void> processReturn({
    required String saleId,
    required List<ReturnItemEntity> items,
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  });
  Future<List<Sale>> getRecentSales({int limit = 20});
  Future<List<SaleItem>> getSaleItems(String saleId);
  Future<Sale?> getSaleByIdOrRef(String query);
  Future<Map<String, int>> getAlreadyReturnedQuantities(String saleId);
  Future<List<ReturnEntity>> getReturnsHistory({int limit = 50});
}

@LazySingleton(as: ReturnsLocalDataSource)
class ReturnsLocalDataSourceImpl implements ReturnsLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final InventoryLocalDataSource _inventory;
  final _uuid = const Uuid();

  @visibleForTesting
  Future<void> Function()? onBeforeApplyStock;

  ReturnsLocalDataSourceImpl(this._db, this._branchProvider, this._tx, this._inventory);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<Map<String, int>> getAlreadyReturnedQuantities(String saleId) async {
    final query = _db.select(_db.returnItems).join([
      innerJoin(_db.returns, _db.returns.id.equalsExp(_db.returnItems.returnId)),
    ])..where(_db.returns.saleId.equals(saleId) & _db.returns.deletedAt.isNull());

    final rows = await query.get();
    final Map<String, int> returnedMap = {};
    for (final row in rows) {
      final item = row.readTable(_db.returnItems);
      if (item.saleItemId != null && item.saleItemId!.isNotEmpty) {
        returnedMap[item.saleItemId!] = (returnedMap[item.saleItemId!] ?? 0) + item.qty;
      }
      returnedMap[item.variantId] = (returnedMap[item.variantId] ?? 0) + item.qty;
    }
    return returnedMap;
  }

  @override
  Future<void> processReturn({
    required String saleId,
    required List<ReturnItemEntity> items,
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception('Return reason is required');
    }
    if (items.isEmpty) {
      throw Exception('At least one item is required for a return');
    }

    // 1. Verify returned quantities against remaining returnable
    final alreadyReturnedMap = await getAlreadyReturnedQuantities(saleId);
    final saleItems = await getSaleItems(saleId);
    final saleItemsMap = {for (final si in saleItems) si.id: si};

    for (final item in items) {
      if (item.qty <= 0) {
        throw Exception('الكمية المرتجعة يجب أن تكون أكبر من الصفر');
      }
      final si = saleItemsMap[item.saleItemId];
      if (si != null) {
        final alreadyReturned = alreadyReturnedMap[si.id] ?? alreadyReturnedMap[item.variantId] ?? 0;
        final maxAvailable = si.qty - alreadyReturned;
        if (item.qty > maxAvailable) {
          throw Exception(
            'لا يمكن إرجاع كمية (${item.qty}) تتجاوز الكمية المتبقية القابلة للإرجاع ($maxAvailable) للصنف: ${item.productName}',
          );
        }
      }
    }

    final now = DateTime.now();
    final branchId = await _branchId();
    final returnId = _uuid.v4();
    final totalRefund = items.fold<int>(0, (sum, item) => sum + (item.refundUnitPrice * item.qty));

    await _tx.write(
      writeFn: () async {
        // 1. Insert return record
        await _db.into(_db.returns).insert(ReturnsCompanion.insert(
          id: returnId,
          branchId: branchId,
          saleId: Value(saleId.isEmpty ? null : saleId),
          cashierId: userId,
          reason: reason,
          refundAmount: totalRefund,
          paymentMethod: paymentMethod,
          date: now,
          createdAt: now,
          updatedAt: now,
        ));

        // 2. Insert return_items & applyStockMovement for each returned item
        for (final item in items) {
          final returnItemId = _uuid.v4();
          await _db.into(_db.returnItems).insert(ReturnItemsCompanion.insert(
            id: returnItemId,
            branchId: branchId,
            returnId: returnId,
            saleItemId: Value(item.saleItemId),
            variantId: item.variantId,
            qty: item.qty,
            refundUnitPrice: item.refundUnitPrice,
            createdAt: now,
          ));

          if (onBeforeApplyStock != null) {
            await onBeforeApplyStock!();
          }

          // 3. Restores stock via applyStockMovement with type return_
          await _inventory.applyStockMovement(
            variantId: item.variantId,
            qtyDelta: item.qty,
            type: StockMovementType.return_,
            reason: reason,
            userId: userId,
            refType: 'return',
            refId: returnId,
          );
        }

        // 4. Update sale status to 'returned' or 'partially_returned'
        if (saleId.isNotEmpty) {
          if (saleItems.isNotEmpty) {
            final totalSoldQty = saleItems.fold<int>(0, (sum, si) => sum + si.qty);
            int totalReturnedQty = 0;
            for (final si in saleItems) {
              final prevReturned = alreadyReturnedMap[si.id] ?? alreadyReturnedMap[si.variantId] ?? 0;
              final newlyReturned = items
                  .where((it) => (it.saleItemId == si.id) || (it.saleItemId == null && it.variantId == si.variantId))
                  .fold<int>(0, (sum, it) => sum + it.qty);
              totalReturnedQty += (prevReturned + newlyReturned);
            }

            final newStatus = totalReturnedQty >= totalSoldQty ? 'returned' : 'partially_returned';
            await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
              SalesCompanion(
                status: Value(newStatus),
                updatedAt: Value(now),
              ),
            );
          } else {
            await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
              SalesCompanion(
                status: const Value('returned'),
                updatedAt: Value(now),
              ),
            );
          }
        }
      },
      branchId: branchId,
      entity: 'return',
      entityId: returnId,
      operation: 'insert',
      userId: userId,
    );
  }

  @override
  Future<List<Sale>> getRecentSales({int limit = 20}) async {
    return (_db.select(_db.sales)
          ..where((s) => s.deletedAt.isNull() & s.status.isNotIn(['returned']))
          ..orderBy([(s) => OrderingTerm.desc(s.date)])
          ..limit(limit))
        .get();
  }

  @override
  Future<List<SaleItem>> getSaleItems(String saleId) async {
    return (_db.select(_db.saleItems)..where((si) => si.saleId.equals(saleId))).get();
  }

  @override
  Future<Sale?> getSaleByIdOrRef(String query) async {
    return (_db.select(_db.sales)
          ..where((s) => (s.id.equals(query) | s.shortRef.equals(query)) & s.deletedAt.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<List<ReturnEntity>> getReturnsHistory({int limit = 50}) async {
    final query = _db.select(_db.returns).join([
      leftOuterJoin(_db.sales, _db.sales.id.equalsExp(_db.returns.saleId)),
      leftOuterJoin(_db.users, _db.users.id.equalsExp(_db.returns.cashierId)),
    ])..where(_db.returns.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(_db.returns.date)])
      ..limit(limit);

    final rows = await query.get();
    if (rows.isEmpty) return [];

    final returnIds = rows.map((r) => r.readTable(_db.returns).id).toList();

    final itemRows = await (_db.select(_db.returnItems)
          ..where((i) => i.returnId.isIn(returnIds)))
        .get();

    final variantIds = itemRows.map((i) => i.variantId).toSet().toList();
    final Map<String, ({String name, String color, String size})> variantInfoMap = {};
    if (variantIds.isNotEmpty) {
      final variantsWithProducts = await (_db.select(_db.productVariants).join([
        innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
      ])..where(_db.productVariants.id.isIn(variantIds))).get();

      for (final vwp in variantsWithProducts) {
        final v = vwp.readTable(_db.productVariants);
        final p = vwp.readTable(_db.products);
        variantInfoMap[v.id] = (name: p.name, color: v.color, size: v.size);
      }
    }

    final Map<String, List<ReturnItemEntity>> itemsByReturnId = {};
    for (final item in itemRows) {
      final info = variantInfoMap[item.variantId];
      final list = itemsByReturnId.putIfAbsent(item.returnId, () => []);
      list.add(ReturnItemEntity(
        id: item.id,
        saleItemId: item.saleItemId ?? '',
        variantId: item.variantId,
        productName: info?.name ?? '',
        color: info?.color ?? '',
        size: info?.size ?? '',
        maxQty: item.qty,
        qty: item.qty,
        refundUnitPrice: item.refundUnitPrice,
      ));
    }

    return rows.map((row) {
      final r = row.readTable(_db.returns);
      final s = row.readTableOrNull(_db.sales);
      final u = row.readTableOrNull(_db.users);

      return ReturnEntity(
        id: r.id,
        saleId: r.saleId,
        saleShortRef: s?.shortRef,
        cashierId: r.cashierId,
        cashierName: u?.displayName ?? r.cashierId,
        reason: r.reason,
        refundAmount: r.refundAmount,
        paymentMethod: r.paymentMethod,
        date: r.date,
        items: itemsByReturnId[r.id] ?? [],
      );
    }).toList();
  }
}
