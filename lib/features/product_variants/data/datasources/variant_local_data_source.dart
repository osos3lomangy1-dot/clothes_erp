import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';

@lazySingleton
class VariantLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  @visibleForTesting
  Future<void> Function()? beforeAuditWrite;

  VariantLocalDataSource(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  Future<List<ProductVariant>> getVariants(String productId) async {
    return (_db.select(_db.productVariants)..where((t) => t.productId.equals(productId) & t.deletedAt.isNull())).get();
  }

  Future<String> autoGenerateSku(String productName, String color, String size) async {
    final base = '${productName.substring(0, 1).toUpperCase()}${color.substring(0, 1).toUpperCase()}${size.substring(0, 1).toUpperCase()}';
    String sku = base;
    int suffix = 1;
    while (true) {
      final existing = await (_db.select(_db.productVariants)..where((t) => t.sku.equals(sku) & t.deletedAt.isNull())).get();
      if (existing.isEmpty) break;
      sku = '$base$suffix';
      suffix++;
    }
    return sku;
  }

  Future<void> createVariant({
    required String productId,
    required String sku,
    required String color,
    required String size,
    required int costPrice,
    required int sellPrice,
    int quantity = 0,
    
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final branchId = await _branchId();
    final now = DateTime.now();
    await _tx.write(
      writeFn: () async {
        await _db.into(_db.productVariants).insert(ProductVariantsCompanion.insert(
          id: id,
          branchId: branchId,
          productId: productId,
          sku: sku,
          color: color,
          size: size,
          quantity: Value(quantity),
          costPrice: costPrice,
          sellPrice: sellPrice,
          
          createdAt: now,
          updatedAt: now,
        ));
      },
      branchId: branchId,
      entity: 'variant',
      entityId: id,
      operation: 'insert',
      userId: 'system',
    );
  }

  Future<void> updateVariant(String id, {int? costPrice, int? sellPrice, int? quantity}) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    // Get old values for audit
    final existing = await (_db.select(_db.productVariants)..where((t) => t.id.equals(id))).getSingleOrNull();
    String? oldValue;
    String? newValue;
    if (existing != null && (costPrice != null || sellPrice != null)) {
      oldValue = 'cost:${existing.costPrice},sell:${existing.sellPrice}';
      newValue = 'cost:${costPrice ?? existing.costPrice},sell:${sellPrice ?? existing.sellPrice}';
    }
    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.productVariants)..where((t) => t.id.equals(id))).write(
          ProductVariantsCompanion(
            costPrice: costPrice != null ? Value(costPrice) : const Value.absent(),
            sellPrice: sellPrice != null ? Value(sellPrice) : const Value.absent(),
            quantity: quantity != null ? Value(quantity) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'variant',
      entityId: id,
      operation: 'update',
      userId: 'system',
      oldValue: oldValue,
      newValue: newValue,
    );
  }

  Future<void> softDeleteVariant(String id) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.productVariants)..where((t) => t.id.equals(id))).write(
          ProductVariantsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      },
      branchId: branchId,
      entity: 'variant',
      entityId: id,
      operation: 'delete',
      userId: 'system',
    );
  }

  Future<void> injectFailure() async {
    if (beforeAuditWrite != null) await beforeAuditWrite!();
  }
}



