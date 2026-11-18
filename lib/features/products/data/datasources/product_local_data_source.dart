import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/utils/arabic_text_helper.dart';

import 'package:flutter/foundation.dart' hide Category;

class ProductWithVariants {
  final Product product;
  final String categoryName;
  final List<ProductVariant> variants;

  ProductWithVariants({
    required this.product,
    required this.categoryName,
    required this.variants,
  });
}

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

  Stream<List<Product>> watchAllProducts() {
    return (_db.select(_db.products)..where((t) => t.deletedAt.isNull())).watch();
  }

  Stream<List<ProductWithVariants>> watchAllProductsWithVariants() {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productVariants,
        _db.productVariants.productId.equalsExp(_db.products.id) &
            _db.productVariants.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.products.categoryId),
      ),
    ])..where(_db.products.deletedAt.isNull());

    return query.watch().map((rows) => _groupProductsWithVariants(rows));
  }

  Future<List<ProductWithVariants>> getProductsWithVariants() async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productVariants,
        _db.productVariants.productId.equalsExp(_db.products.id) &
            _db.productVariants.deletedAt.isNull(),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.products.categoryId),
      ),
    ])..where(_db.products.deletedAt.isNull());

    final rows = await query.get();
    return _groupProductsWithVariants(rows);
  }

  List<ProductWithVariants> _groupProductsWithVariants(List<TypedResult> rows) {
    final map = <String, ProductWithVariants>{};
    for (final row in rows) {
      final product = row.readTable(_db.products);
      final variant = row.readTableOrNull(_db.productVariants);
      final category = row.readTableOrNull(_db.categories);

      final existing = map[product.id];
      if (existing == null) {
        map[product.id] = ProductWithVariants(
          product: product,
          categoryName: category?.name ?? '',
          variants: [?variant],
        );
      } else if (variant != null) {
        existing.variants.add(variant);
      }
    }
    return map.values.toList();
  }

  Stream<List<Product>> watchActiveProducts() {
    return (_db
          .select(_db.products)
          ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true)))
        .watch();
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

    final existingProducts = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    for (final p in existingProducts) {
      if (ArabicTextHelper.isExactMatch(name, p.name)) {
        throw Exception('يوجد منتج مسجل بالفعل بهذا الاسم ("${p.name}")');
      }
    }

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

    final existingProducts = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    for (final p in existingProducts) {
      if (ArabicTextHelper.isExactMatch(name, p.name)) {
        throw Exception('يوجد منتج مسجل بالفعل بهذا الاسم ("${p.name}")');
      }
    }

    // Validate SKU uniqueness within batch and against existing active variants
    final seenBatchSkus = <String>{};
    final activeVariants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull()))
        .get();
    final existingSkusLower =
        activeVariants.map((v) => v.sku.trim().toLowerCase()).toSet();

    for (final v in variants) {
      final cleanSku = v.sku.trim();
      if (cleanSku.isEmpty) {
        throw Exception('كود المنتج (SKU) مطلوب لكل مقاس');
      }
      final lower = cleanSku.toLowerCase();
      if (!seenBatchSkus.add(lower)) {
        throw Exception(
          'عفواً، الكود ("$cleanSku") مكرر أكثر من مرة داخل جدول المقاسات.',
        );
      }
      if (existingSkusLower.contains(lower)) {
        throw Exception(
          'عفواً، الكود ("$cleanSku") مسجل بالفعل في النظام لصنف آخر. لا يمكن تكرار الأكواد.',
        );
      }
    }

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.products).insert(ProductsCompanion.insert(
          id: id,
          branchId: branchId,
          name: name.trim(),
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
            sku: v.sku.trim(),
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

    if (name != null) {
      final existingProducts = await (_db.select(_db.products)
            ..where((p) => p.id.isNotValue(id) & p.deletedAt.isNull()))
          .get();
      for (final p in existingProducts) {
        if (ArabicTextHelper.isExactMatch(name, p.name)) {
          throw Exception('يوجد منتج آخر مسجل بالفعل بهذا الاسم ("${p.name}")');
        }
      }
    }

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
    // Check if product has active (non-cancelled, non-deleted) sales history
    final variantIds = await (_db.select(_db.productVariants)
          ..where((v) => v.productId.equals(id)))
        .map((v) => v.id)
        .get();
    if (variantIds.isNotEmpty) {
      final activeSaleItems = await (_db.select(_db.saleItems).join([
        innerJoin(
          _db.sales,
          _db.sales.id.equalsExp(_db.saleItems.saleId),
        ),
      ])
            ..where(
              _db.saleItems.variantId.isIn(variantIds) &
                  _db.sales.deletedAt.isNull() &
                  _db.sales.status.isNotValue('cancelled'),
            ))
          .get();
      if (activeSaleItems.isNotEmpty) {
        throw Exception(
          'لا يمكن حذف هذا المنتج لوجود فواتير مبيعات مرتبطة به. يمكنك تعطيله (إخفاؤه من نقطة البيع) بدلاً من الحذف للحفاظ على سجل المبيعات.',
        );
      }
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
