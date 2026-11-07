import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';

import 'package:flutter/foundation.dart' hide Category;

@lazySingleton
class ProductLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  @visibleForTesting
  Future<void> Function()? beforeAuditWrite;

  ProductLocalDataSource(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  Future<List<Product>> getProducts() async {
    return (_db.select(_db.products)..where((t) => t.deletedAt.isNull())).get();
  }

  Future<Product?> getProduct(String id) async {
    return (_db.select(_db.products)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> createProduct({
    required String name,
    required String categoryId,
    String? description,
    int minStock = 5,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final branchId = await _branchId();
    await _tx.write(
      writeFn: () async {
        await _db.into(_db.products).insert(ProductsCompanion.insert(
          id: id,
          branchId: branchId,
          name: name,
          categoryId: categoryId,
          description: Value(description),
          minStock: Value(minStock),
          createdAt: now,
          updatedAt: now,
        ));
      },
      branchId: branchId,
      entity: 'product',
      entityId: id,
      operation: 'insert',
      userId: 'system',
    );
  }

  Future<String> createProductWithVariants({
    required String name,
    required String categoryId,
    String? description,
    int minStock = 5,
    required List<VariantInput> variants,
    String userId = 'system',
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final branchId = await _branchId();

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.products).insert(ProductsCompanion.insert(
          id: id,
          branchId: branchId,
          name: name,
          categoryId: categoryId,
          description: Value(description),
          minStock: Value(minStock),
          createdAt: now,
          updatedAt: now,
        ));

        for (final v in variants) {
          final variantId = _uuid.v4();
          await _db.into(_db.productVariants).insert(ProductVariantsCompanion.insert(
            id: variantId,
            branchId: branchId,
            productId: id,
            sku: v.sku,
            color: v.color,
            size: v.size,
            costPrice: v.costPrice,
            sellPrice: v.sellPrice,
            quantity: Value(v.quantity),
            createdAt: now,
            updatedAt: now,
          ));

          if (v.quantity > 0) {
            await _db.into(_db.inventoryLogs).insert(InventoryLogsCompanion.insert(
              id: _uuid.v4(),
              branchId: branchId,
              variantId: variantId,
              type: 'receive',
              qtyDelta: v.quantity,
              reason: const Value('رصيد افتتاحي / إضافة منتج جديد'),
              refType: 'opening_stock',
              refId: const Value.absent(),
              userId: userId,
              createdAt: now,
            ));
          }
        }
      },
      branchId: branchId,
      entity: 'product',
      entityId: id,
      operation: 'insert_with_variants',
      userId: userId,
    );

    return id;
  }

  Future<void> updateProduct(String id, {String? name, String? description, int? minStock, bool? isActive}) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
          ProductsCompanion(
            name: name != null ? Value(name) : const Value.absent(),
            description: description != null ? Value(description) : const Value.absent(),
            minStock: minStock != null ? Value(minStock) : const Value.absent(),
            isActive: isActive != null ? Value(isActive) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'product',
      entityId: id,
      operation: 'update',
      userId: 'system',
    );
  }

  Future<void> deactivateProduct(String id) async {
    await updateProduct(id, isActive: false);
  }

  Future<void> softDeleteProduct(String id) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    // Check if product has sales
    final variantIds = await (_db.select(_db.productVariants)..where((v) => v.productId.equals(id))).map((v) => v.id).get();
    final saleItems = await (_db.select(_db.saleItems)..where((t) => t.variantId.isIn(variantIds))).get();
    if (saleItems.isNotEmpty) {
      throw Exception('Cannot delete product with sales history. Deactivate instead.');
    }
    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
          ProductsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
        await (_db.update(_db.productVariants)..where((t) => t.productId.equals(id))).write(
          ProductVariantsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      },
      branchId: branchId,
      entity: 'product',
      entityId: id,
      operation: 'delete',
      userId: 'system',
    );
  }

  Future<List<Product>> cashierProducts() async {
    return (_db.select(_db.products)
          ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true)))
        .get();
  }
}

class VariantInput {
  final String sku;
  final String color;
  final String size;
  final int costPrice;
  final int sellPrice;
  final int quantity;

  const VariantInput({
    required this.sku,
    required this.color,
    required this.size,
    required this.costPrice,
    required this.sellPrice,
    required this.quantity,
  });
}
