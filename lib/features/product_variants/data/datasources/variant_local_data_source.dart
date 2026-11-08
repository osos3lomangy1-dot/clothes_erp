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

  Future<List<ProductVariant>> getAllVariants() async {
    return (_db.select(_db.productVariants)..where((t) => t.deletedAt.isNull())).get();
  }

  Future<List<ProductVariant>> getVariants(String productId) async {
    return (_db.select(_db.productVariants)
          ..where((t) => t.productId.equals(productId) & t.deletedAt.isNull()))
        .get();
  }

  Future<ProductVariant?> getVariantById(String id) async {
    return (_db.select(_db.productVariants)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<String> autoGenerateSku(String productName, String color, String size) async {
    final p = productName.isNotEmpty ? productName.substring(0, 1).toUpperCase() : 'P';
    final c = color.isNotEmpty ? color.substring(0, 1).toUpperCase() : 'C';
    final s = size.isNotEmpty ? size.substring(0, 1).toUpperCase() : 'S';
    final base = '$p$c$s';
    String sku = base;
    int suffix = 1;
    while (true) {
      final existing = await (_db.select(_db.productVariants)
            ..where((t) => t.sku.equals(sku) & t.deletedAt.isNull()))
          .get();
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
    int wholesalePrice = 0,
    int quantity = 0,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final branchId = await _branchId();
    await _tx.write(
      writeFn: () async {
        await _db.into(_db.productVariants).insert(ProductVariantsCompanion.insert(
          id: id,
          branchId: branchId,
          productId: productId,
          sku: sku,
          color: color,
          size: size,
          quantity: const Value(0),
          costPrice: costPrice,
          sellPrice: sellPrice,
          wholesalePrice: Value(wholesalePrice),
          createdAt: now,
          updatedAt: now,
        ));
        if (quantity > 0) {
          await (_db.update(_db.productVariants)..where((t) => t.id.equals(id))).write(
            ProductVariantsCompanion(quantity: Value(quantity), updatedAt: Value(now)),
          );
          await _db.into(_db.inventoryLogs).insert(InventoryLogsCompanion.insert(
            id: _uuid.v4(),
            branchId: branchId,
            variantId: id,
            type: 'receive',
            qtyDelta: quantity,
            reason: const Value('opening stock'),
            refType: '',
            refId: const Value.absent(),
            userId: 'system',
            createdAt: now,
          ));
        }
      },
      branchId: branchId,
      entity: 'variant',
      entityId: id,
      operation: 'insert',
      userId: 'system',
    );
  }

  Future<void> updateVariant(
    String id, {
    int? costPrice,
    int? sellPrice,
    int? wholesalePrice,
    int? quantity,
    String? sku,
    String? color,
    String? size,
    String? reason,
    String userId = 'system',
  }) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    final existing = await (_db.select(_db.productVariants)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) throw Exception('المقاس غير موجود');

    final qtyDelta = quantity != null ? (quantity - existing.quantity) : 0;
    final oldValue = 'qty:${existing.quantity},cost:${existing.costPrice},sell:${existing.sellPrice},wholesale:${existing.wholesalePrice}';
    final newValue = 'qty:${quantity ?? existing.quantity},cost:${costPrice ?? existing.costPrice},sell:${sellPrice ?? existing.sellPrice},wholesale:${wholesalePrice ?? existing.wholesalePrice}';

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.productVariants)..where((t) => t.id.equals(id))).write(
          ProductVariantsCompanion(
            costPrice: costPrice != null ? Value(costPrice) : const Value.absent(),
            sellPrice: sellPrice != null ? Value(sellPrice) : const Value.absent(),
            wholesalePrice: wholesalePrice != null ? Value(wholesalePrice) : const Value.absent(),
            quantity: quantity != null ? Value(quantity) : const Value.absent(),
            sku: sku != null ? Value(sku) : const Value.absent(),
            color: color != null ? Value(color) : const Value.absent(),
            size: size != null ? Value(size) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );

        if (qtyDelta != 0) {
          await _db.into(_db.inventoryLogs).insert(InventoryLogsCompanion.insert(
            id: _uuid.v4(),
            branchId: branchId,
            variantId: id,
            type: 'adjustment',
            qtyDelta: qtyDelta,
            reason: Value(reason ?? 'تعديل يدوي للمخزون (تسوية جردية / تصحيح خطأ إدخال)'),
            refType: 'manual_adjustment',
            refId: const Value.absent(),
            userId: userId,
            createdAt: now,
          ));
        }
      },
      branchId: branchId,
      entity: 'variant',
      entityId: id,
      operation: 'update',
      userId: userId,
      oldValue: oldValue,
      newValue: newValue,
    );
  }

  Future<void> adjustStockQuantity(
    String id, {
    required int newQuantity,
    required String reason,
    String userId = 'admin',
  }) async {
    await updateVariant(
      id,
      quantity: newQuantity,
      reason: reason,
      userId: userId,
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
