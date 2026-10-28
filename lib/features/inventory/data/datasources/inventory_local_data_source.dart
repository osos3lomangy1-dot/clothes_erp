import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';

enum StockMovementType { sale, return_, receive, adjustment, stocktake }

@lazySingleton
class InventoryLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  Future<void> Function()? beforeAuditWrite;

  InventoryLocalDataSource(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  Future<void> applyStockMovement({
    required String variantId,
    required int qtyDelta,
    required StockMovementType type,
    required String reason,
    required String userId,
    String? refType,
    String? refId,
  }) async {
    // reason required for receive and adjustment
    if ((type == StockMovementType.receive || type == StockMovementType.adjustment) && reason.trim().isEmpty) {
      throw Exception('Reason is required for receive and adjustment');
    }
    final now = DateTime.now();
    final branchId = await _branchId();
    final variant = await (_db.select(_db.productVariants)..where((t) => t.id.equals(variantId))).getSingleOrNull();
    if (variant == null) throw Exception('Variant not found');
    final newQty = variant.quantity + qtyDelta;
    if (newQty < 0) throw Exception('Insufficient stock');
    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.productVariants)..where((t) => t.id.equals(variantId))).write(
          ProductVariantsCompanion(quantity: Value(newQty), updatedAt: Value(now)),
        );
        await _db.into(_db.inventoryLogs).insert(InventoryLogsCompanion.insert(
          id: _uuid.v4(),
          branchId: branchId,
          variantId: variantId,
          type: type.name,
          qtyDelta: qtyDelta,
          reason: Value(reason),
          refType: refType ?? '',
          refId: Value(refId),
          userId: userId,
          createdAt: now,
        ));
      },
      branchId: branchId,
      entity: 'inventory',
      entityId: variantId,
      operation: type.name,
      userId: userId,
    );
  }

  Future<List<ProductVariant>> stockList({String? search, String filter = 'all', int limit = 50, int offset = 0}) async {
    var query = _db.select(_db.productVariants).join([
      innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
    ]);
    query = query..where(_db.productVariants.deletedAt.isNull());
    if (search != null && search.isNotEmpty) {
      query = query..where(_db.products.name.contains(search) | _db.productVariants.sku.contains(search) | _db.productVariants.color.contains(search) | _db.productVariants.size.contains(search));
    }
    if (filter == 'low') {
      query = query..where(_db.productVariants.quantity.isBiggerThanValue(0) & _db.productVariants.quantity.isSmallerOrEqualValue(5));
    } else if (filter == 'out') {
      query = query..where(_db.productVariants.quantity.equals(0));
    }
    query = query..orderBy([OrderingTerm.asc(_db.products.name)])..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.productVariants)).toList();
  }

  Future<Map<String, int>> counters() async {
    final variants = await (_db.select(_db.productVariants)..where((t) => t.deletedAt.isNull())).get();
    int total = 0, low = 0, out = 0;
    for (final v in variants) {
      total += v.quantity;
      if (v.quantity == 0) out++;
      // minStock check requires product; simplified
    }
    return {'total': total, 'low': low, 'out': out};
  }
}



