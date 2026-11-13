import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../domain/entities/goods_receipt_entity.dart';

enum StockMovementType { sale, return_, receive, adjustment, stocktake }

class GoodsReceiptDraftItem {
  final String variantId;
  final int quantity;

  const GoodsReceiptDraftItem({
    required this.variantId,
    required this.quantity,
  });
}

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
    if ((type == StockMovementType.receive ||
            type == StockMovementType.adjustment) &&
        reason.trim().isEmpty) {
      throw Exception('Reason is required for receive and adjustment');
    }
    final now = DateTime.now();
    final branchId = await _branchId();
    final variant = await (_db.select(
      _db.productVariants,
    )..where((t) => t.id.equals(variantId))).getSingleOrNull();
    if (variant == null) throw Exception('Variant not found');
    final newQty = variant.quantity + qtyDelta;
    if (newQty < 0) throw Exception('Insufficient stock');
    await _tx.write(
      writeFn: () async {
        await (_db.update(
          _db.productVariants,
        )..where((t) => t.id.equals(variantId))).write(
          ProductVariantsCompanion(
            quantity: Value(newQty),
            updatedAt: Value(now),
          ),
        );
        await _db
            .into(_db.inventoryLogs)
            .insert(
              InventoryLogsCompanion.insert(
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
              ),
            );
      },
      branchId: branchId,
      entity: 'inventory',
      entityId: variantId,
      operation: type.name,
      userId: userId,
    );
  }

  Future<List<ProductVariant>> stockList({
    String? search,
    String filter = 'all',
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _db.select(_db.productVariants).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ]);
    query = query..where(_db.productVariants.deletedAt.isNull());
    if (search != null && search.isNotEmpty) {
      query = query
        ..where(
          _db.products.name.contains(search) |
              _db.productVariants.sku.contains(search) |
              _db.productVariants.color.contains(search) |
              _db.productVariants.size.contains(search),
        );
    }
    if (filter == 'low') {
      query = query
        ..where(
          _db.productVariants.quantity.isBiggerThanValue(0) &
              _db.productVariants.quantity.isSmallerOrEqualValue(5),
        );
    } else if (filter == 'out') {
      query = query..where(_db.productVariants.quantity.equals(0));
    }
    query = query
      ..orderBy([OrderingTerm.asc(_db.products.name)])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.productVariants)).toList();
  }

  Future<Map<String, int>> counters() async {
    final variants = await (_db.select(
      _db.productVariants,
    )..where((t) => t.deletedAt.isNull())).get();
    int total = 0, low = 0, out = 0;
    for (final v in variants) {
      total += v.quantity;
      if (v.quantity == 0) out++;
      // minStock check requires product; simplified
    }
    return {'total': total, 'low': low, 'out': out};
  }

  Future<List<InventoryItemDetail>> getInventoryDetails({
    String? search,
    bool lowStockOnly = false,
  }) async {
    var query = _db.select(_db.productVariants).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ]);
    query = query..where(_db.productVariants.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query
        ..where(
          _db.products.name.contains(s) |
              _db.productVariants.sku.contains(s) |
              _db.productVariants.color.contains(s) |
              _db.productVariants.size.contains(s),
        );
    }
    if (lowStockOnly) {
      query = query
        ..where(_db.productVariants.quantity.isSmallerOrEqualValue(5));
    }
    query = query..orderBy([OrderingTerm.asc(_db.products.name)]);
    final rows = await query.get();
    return rows.map((r) {
      final variant = r.readTable(_db.productVariants);
      final product = r.readTable(_db.products);
      return InventoryItemDetail(
        variantId: variant.id,
        productId: variant.productId,
        sku: variant.sku,
        color: variant.color,
        size: variant.size,
        quantity: variant.quantity,
        costPrice: variant.costPrice,
        sellPrice: variant.sellPrice,
        productName: product.name,
      );
    }).toList();
  }

  Future<List<Category>> getCategories() async {
    return (_db.select(_db.categories)..where((t) => t.deletedAt.isNull())).get();
  }

  Future<InventoryItemDetail> quickCreateProductAndReceive({
    required String productName,
    required String categoryId,
    required String sku,
    required String color,
    required String size,
    required int costPrice,
    required int sellPrice,
    required int quantity,
    required String reason,
    String userId = 'admin',
  }) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    final prodId = _uuid.v4();
    final variantId = _uuid.v4();

    await _tx.write(
      writeFn: () async {
        // 1. Insert product
        await _db.into(_db.products).insert(ProductsCompanion.insert(
          id: prodId,
          branchId: branchId,
          name: productName,
          categoryId: categoryId,
          createdAt: now,
          updatedAt: now,
        ));

        // 2. Insert variant
        await _db.into(_db.productVariants).insert(ProductVariantsCompanion.insert(
          id: variantId,
          branchId: branchId,
          productId: prodId,
          sku: sku,
          color: color,
          size: size,
          costPrice: costPrice,
          sellPrice: sellPrice,
          quantity: Value(quantity),
          createdAt: now,
          updatedAt: now,
        ));

        // 3. Insert inventory log
        if (quantity > 0) {
          await _db.into(_db.inventoryLogs).insert(InventoryLogsCompanion.insert(
            id: _uuid.v4(),
            branchId: branchId,
            variantId: variantId,
            type: 'receive',
            qtyDelta: quantity,
            reason: Value(reason),
            refType: 'purchase',
            refId: const Value.absent(),
            userId: userId,
            createdAt: now,
          ));
        }
      },
      branchId: branchId,
      entity: 'inventory',
      entityId: variantId,
      operation: 'receive_new',
      userId: userId,
    );

    return InventoryItemDetail(
      variantId: variantId,
      productId: prodId,
      sku: sku,
      color: color,
      size: size,
      quantity: quantity,
      costPrice: costPrice,
      sellPrice: sellPrice,
      productName: productName,
    );
  }

  // ==========================================
  // BLIND GOODS RECEIPTS (الكاشير والمدير)
  // ==========================================

  Future<GoodsReceiptEntity> createGoodsReceipt({
    required List<GoodsReceiptDraftItem> items,
    required String cashierId,
    String? notes,
    DateTime? receivedAt,
  }) async {
    if (items.isEmpty) {
      throw Exception('لا يمكن إنشاء استلام مخزني فارغ');
    }

    final branchId = await _branchId();
    final receiptId = _uuid.v4();
    final now = receivedAt ?? DateTime.now();
    final totalItems = items.fold(0, (sum, it) => sum + it.quantity);

    // 1. First record receipt header and items, and write audit via TxWriter
    await _tx.write(
      writeFn: () async {
        await _db.into(_db.goodsReceipts).insert(
              GoodsReceiptsCompanion.insert(
                id: receiptId,
                branchId: branchId,
                cashierId: cashierId,
                receivedAt: now,
                status: const Value('pending'),
                totalItems: Value(totalItems),
                notes: Value(notes?.trim()),
                createdAt: now,
                updatedAt: now,
              ),
            );

        for (final it in items) {
          final itemId = _uuid.v4();
          await _db.into(_db.goodsReceiptItems).insert(
                GoodsReceiptItemsCompanion.insert(
                  id: itemId,
                  receiptId: receiptId,
                  variantId: it.variantId,
                  quantity: it.quantity,
                  createdAt: now,
                ),
              );
        }
      },
      branchId: branchId,
      entity: 'goods_receipt',
      entityId: receiptId,
      operation: 'insert',
      userId: cashierId,
    );

    // 2. Increase stock immediately via applyStockMovement for every item
    for (final it in items) {
      await applyStockMovement(
        variantId: it.variantId,
        qtyDelta: it.quantity,
        type: StockMovementType.receive,
        reason: 'استلام بضاعة شحنة معلقة #$receiptId',
        userId: cashierId,
        refType: 'goods_receipt',
        refId: receiptId,
      );
    }

    final created = await getGoodsReceiptById(receiptId);
    return created!;
  }

  Future<List<GoodsReceiptEntity>> getGoodsReceipts({String? status}) async {
    var query = _db.select(_db.goodsReceipts);
    if (status != null && status.isNotEmpty) {
      query = query..where((r) => r.status.equals(status));
    }
    query = query..orderBy([(r) => OrderingTerm.desc(r.receivedAt)]);

    final rows = await query.get();
    final result = <GoodsReceiptEntity>[];
    for (final r in rows) {
      final items = await _getItemsForReceipt(r.id);
      result.add(
        GoodsReceiptEntity(
          id: r.id,
          branchId: r.branchId,
          cashierId: r.cashierId,
          receivedAt: r.receivedAt,
          status: r.status,
          totalItems: r.totalItems,
          notes: r.notes,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
          items: items,
        ),
      );
    }
    return result;
  }

  Future<GoodsReceiptEntity?> getGoodsReceiptById(String receiptId) async {
    final r = await (_db.select(_db.goodsReceipts)
          ..where((g) => g.id.equals(receiptId)))
        .getSingleOrNull();
    if (r == null) return null;

    final items = await _getItemsForReceipt(r.id);
    return GoodsReceiptEntity(
      id: r.id,
      branchId: r.branchId,
      cashierId: r.cashierId,
      receivedAt: r.receivedAt,
      status: r.status,
      totalItems: r.totalItems,
      notes: r.notes,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      items: items,
    );
  }

  Future<void> updateGoodsReceiptStatus({
    required String receiptId,
    required String newStatus,
    required String userId,
  }) async {
    final branchId = await _branchId();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.goodsReceipts)..where((g) => g.id.equals(receiptId)))
            .write(
          GoodsReceiptsCompanion(
            status: Value(newStatus),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'goods_receipt',
      entityId: receiptId,
      operation: 'update_status',
      userId: userId,
    );
  }

  Future<List<GoodsReceiptItemEntity>> _getItemsForReceipt(String receiptId) async {
    final query = _db.select(_db.goodsReceiptItems).join([
      innerJoin(
        _db.productVariants,
        _db.productVariants.id.equalsExp(_db.goodsReceiptItems.variantId),
      ),
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])..where(_db.goodsReceiptItems.receiptId.equals(receiptId));

    final rows = await query.get();

    return rows.map((r) {
      final item = r.readTable(_db.goodsReceiptItems);
      final variant = r.readTable(_db.productVariants);
      final product = r.readTable(_db.products);

      return GoodsReceiptItemEntity(
        id: item.id,
        receiptId: item.receiptId,
        variantId: item.variantId,
        productName: product.name,
        sku: variant.sku,
        color: variant.color,
        size: variant.size,
        quantity: item.quantity,
        createdAt: item.createdAt,
      );
    }).toList();
  }
}

class InventoryItemDetail {
  final String variantId;
  final String productId;
  final String sku;
  final String color;
  final String size;
  final int quantity;
  final int costPrice;
  final int sellPrice;
  final String productName;

  const InventoryItemDetail({
    required this.variantId,
    required this.productId,
    required this.sku,
    required this.color,
    required this.size,
    required this.quantity,
    required this.costPrice,
    required this.sellPrice,
    required this.productName,
  });
}
