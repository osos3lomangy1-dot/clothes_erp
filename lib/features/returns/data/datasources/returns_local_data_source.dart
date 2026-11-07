import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../inventory/data/datasources/inventory_local_data_source.dart';
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
          if (item.qty <= 0) {
            throw Exception('Return item quantity must be greater than zero');
          }

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

          // 3. Single-quantity path rule: applyStockMovement with type return_
          await _inventory.applyStockMovement(
            variantId: item.variantId,
            qtyDelta: item.qty, // Restores stock
            type: StockMovementType.return_,
            reason: reason,
            userId: userId,
            refType: 'return',
            refId: returnId,
          );
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
          ..where((s) => s.deletedAt.isNull())
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
}

