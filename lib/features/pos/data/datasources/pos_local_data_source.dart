import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../features/inventory/data/datasources/inventory_local_data_source.dart';

@lazySingleton
class PosLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final InventoryLocalDataSource _inventory;
  final _uuid = const Uuid();

  PosLocalDataSource(this._db, this._branchProvider, this._tx, this._inventory);

  Future<String> _branchId() => _branchProvider.getBranchId();

  Future<String> getActiveCashierId() async {
    final user = await (_db.select(_db.users)..where((t) => t.isActive.equals(true) & t.deletedAt.isNull())).getSingleOrNull();
    if (user != null) return user.id;
    final meta = await (_db.select(_db.appMeta)..where((t) => t.key.equals('current_cashier_id'))).getSingleOrNull();
    if (meta != null && meta.value.isNotEmpty) return meta.value;
    final branchId = await _branchId();
    return 'cashier_$branchId';
  }

  Future<List<ProductVariant>> getVariantsForPos({String? search}) async {
    var q = _db.select(_db.productVariants).join([
      innerJoin(_db.products, _db.products.id.equalsExp(_db.productVariants.productId)),
    ]);
    q = q..where(_db.productVariants.deletedAt.isNull() & _db.productVariants.isActive.equals(true));
    if (search != null && search.isNotEmpty) {
      q = q..where(_db.products.name.contains(search) | _db.productVariants.sku.contains(search));
    }
    final rows = await q.get();
    return rows.map((r) => r.readTable(_db.productVariants)).toList();
  }

  Future<void> checkout({
    required List<Map<String, dynamic>> items,
    required int total,
    required String cashierId,
    String? customerId,
  }) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    final saleId = _uuid.v4();
    await _tx.write(
      writeFn: () async {
        await _db.into(_db.sales).insert(SalesCompanion.insert(
          id: saleId,
          branchId: branchId,
          shortRef: 'S${now.millisecondsSinceEpoch}',
          cashierId: cashierId,
          customerId: Value(customerId),
          subtotal: total,
          discountType: 'none',
          total: total,
          paymentMethod: 'cash',
          date: now,
          createdAt: now,
          updatedAt: now,
        ));
        for (final item in items) {
          await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
            id: _uuid.v4(),
            branchId: branchId,
            saleId: saleId,
            variantId: item['variantId'] as String,
            productName: item['name'] as String,
            color: item['color'] as String,
            size: item['size'] as String,
            qty: item['qty'] as int,
            priceSnapshot: item['price'] as int,
            costSnapshot: item['cost'] as int,
            lineTotal: (item['price'] as int) * (item['qty'] as int),
            createdAt: now,
          ));
          await _inventory.applyStockMovement(
            variantId: item['variantId'] as String,
            qtyDelta: -(item['qty'] as int),
            type: StockMovementType.sale,
            reason: 'sale',
            userId: cashierId,
            refType: 'sale',
            refId: saleId,
          );
        }
      },
      branchId: branchId,
      entity: 'sale',
      entityId: saleId,
      operation: 'insert',
      userId: cashierId,
    );
  }
}


