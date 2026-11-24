import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/purchase_item_entity.dart';
import '../../domain/entities/purchase_return_entity.dart';
import '../../domain/entities/supplier_entity.dart';
import '../../domain/entities/supplier_payment_entity.dart';

class PurchaseItemDraft {
  final String variantId;
  final int qty;
  final int costPrice; // in piasters

  const PurchaseItemDraft({
    required this.variantId,
    required this.qty,
    required this.costPrice,
  });
}

class PurchaseReturnItemDraft {
  final String variantId;
  final String productName;
  final String variantInfo;
  final String sku;
  final int qty;
  final int costPrice; // in piasters

  const PurchaseReturnItemDraft({
    required this.variantId,
    required this.productName,
    required this.variantInfo,
    required this.sku,
    required this.qty,
    required this.costPrice,
  });
}

abstract class PurchasesLocalDataSource {
  // Suppliers
  Future<List<SupplierEntity>> getSuppliers();
  Future<SupplierEntity?> getSupplierById(String id);
  Future<SupplierEntity> addSupplier({
    required String name,
    String? phone,
    String? companyName,
    String? address,
  });
  Future<SupplierEntity> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? companyName,
    String? address,
  });
  Future<void> deleteSupplier(String id);

  // Purchases
  Future<List<PurchaseEntity>> getPurchases({
    String? supplierId,
    String? paymentStatus,
  });
  Future<PurchaseEntity?> getPurchaseById(String id);
  Future<PurchaseEntity> createPurchaseInvoice({
    required String supplierId,
    String? invoiceNumber,
    required DateTime purchaseDate,
    required int paidAmount,
    String? notes,
    required List<PurchaseItemDraft> items,
    required String userId,
    String? goodsReceiptId,
  });

  // Supplier Payments
  Future<SupplierPaymentEntity> addSupplierPayment({
    required String supplierId,
    String? purchaseId,
    required int amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? referenceNumber,
    String? notes,
    required String userId,
  });
  Future<List<SupplierPaymentEntity>> getSupplierPayments({
    String? supplierId,
    String? purchaseId,
  });

  // Purchase Returns
  Future<PurchaseReturnEntity> createPurchaseReturn({
    required String supplierId,
    String? purchaseId,
    required List<PurchaseReturnItemDraft> items,
    required String refundType, // 'credit' or 'cash'
    String? reason,
    required String userId,
  });
  Future<List<PurchaseReturnEntity>> getPurchaseReturns({
    String? supplierId,
    String? purchaseId,
  });
}

@LazySingleton(as: PurchasesLocalDataSource)
class PurchasesLocalDataSourceImpl implements PurchasesLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final _uuid = const Uuid();

  PurchasesLocalDataSourceImpl(this._db, this._branchProvider);

  Future<String> _branchId() => _branchProvider.getBranchId();

  // ─────────────────────────────────────────────────────────────────────────
  // SUPPLIERS
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<List<SupplierEntity>> getSuppliers() async {
    final rows =
        await (_db.select(_db.suppliers)
              ..where((s) => s.deletedAt.isNull())
              ..orderBy([(s) => OrderingTerm.asc(s.name)]))
            .get();

    return rows.map(_mapSupplier).toList();
  }

  @override
  Future<SupplierEntity?> getSupplierById(String id) async {
    final row = await (_db.select(
      _db.suppliers,
    )..where((s) => s.id.equals(id) & s.deletedAt.isNull())).getSingleOrNull();

    return row != null ? _mapSupplier(row) : null;
  }

  @override
  Future<SupplierEntity> addSupplier({
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) async {
    final branchId = await _branchId();
    final now = DateTime.now();
    final id = _uuid.v4();

    await _db
        .into(_db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: id,
            branchId: branchId,
            name: name.trim(),
            phone: Value(phone?.trim()),
            companyName: Value(companyName?.trim()),
            address: Value(address?.trim()),
            balance: const Value(0),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await _queueSync('suppliers', id, 'insert', branchId);

    return SupplierEntity(
      id: id,
      branchId: branchId,
      name: name.trim(),
      phone: phone?.trim(),
      companyName: companyName?.trim(),
      address: address?.trim(),
      balance: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<SupplierEntity> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) async {
    final now = DateTime.now();
    final branchId = await _branchId();

    await (_db.update(_db.suppliers)..where((s) => s.id.equals(id))).write(
      SuppliersCompanion(
        name: Value(name.trim()),
        phone: Value(phone?.trim()),
        companyName: Value(companyName?.trim()),
        address: Value(address?.trim()),
        updatedAt: Value(now),
      ),
    );

    await _queueSync('suppliers', id, 'update', branchId);

    final updated = await getSupplierById(id);
    return updated!;
  }

  @override
  Future<void> deleteSupplier(String id) async {
    final now = DateTime.now();
    final branchId = await _branchId();

    await (_db.update(_db.suppliers)..where((s) => s.id.equals(id))).write(
      SuppliersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );

    await _queueSync('suppliers', id, 'delete', branchId);
  }

  SupplierEntity _mapSupplier(Supplier row) {
    return SupplierEntity(
      id: row.id,
      branchId: row.branchId,
      name: row.name,
      phone: row.phone,
      companyName: row.companyName,
      address: row.address,
      balance: row.balance,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PURCHASES (فواتير المشتريات)
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<List<PurchaseEntity>> getPurchases({
    String? supplierId,
    String? paymentStatus,
  }) async {
    var query = _db.select(_db.purchases)..where((p) => p.deletedAt.isNull());

    if (supplierId != null && supplierId.isNotEmpty) {
      query = query..where((p) => p.supplierId.equals(supplierId));
    }
    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      query = query..where((p) => p.paymentStatus.equals(paymentStatus));
    }

    query = query..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]);
    final purchaseRows = await query.get();

    final result = <PurchaseEntity>[];
    for (final row in purchaseRows) {
      final supplier = await getSupplierById(row.supplierId);
      final items = await _getItemsForPurchase(row.id);

      result.add(
        PurchaseEntity(
          id: row.id,
          branchId: row.branchId,
          supplierId: row.supplierId,
          supplierName: supplier?.name,
          invoiceNumber: row.invoiceNumber,
          purchaseDate: row.purchaseDate,
          totalAmount: row.totalAmount,
          paidAmount: row.paidAmount,
          status: row.status,
          paymentStatus: row.paymentStatus,
          notes: row.notes,
          items: items,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
        ),
      );
    }

    return result;
  }

  @override
  Future<PurchaseEntity?> getPurchaseById(String id) async {
    final row = await (_db.select(
      _db.purchases,
    )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).getSingleOrNull();

    if (row == null) return null;

    final supplier = await getSupplierById(row.supplierId);
    final items = await _getItemsForPurchase(row.id);

    return PurchaseEntity(
      id: row.id,
      branchId: row.branchId,
      supplierId: row.supplierId,
      supplierName: supplier?.name,
      invoiceNumber: row.invoiceNumber,
      purchaseDate: row.purchaseDate,
      totalAmount: row.totalAmount,
      paidAmount: row.paidAmount,
      status: row.status,
      paymentStatus: row.paymentStatus,
      notes: row.notes,
      items: items,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  @override
  Future<PurchaseEntity> createPurchaseInvoice({
    required String supplierId,
    String? invoiceNumber,
    required DateTime purchaseDate,
    required int paidAmount,
    String? notes,
    required List<PurchaseItemDraft> items,
    required String userId,
    String? goodsReceiptId,
  }) async {
    if (items.isEmpty) {
      throw Exception('لا يمكن إنشاء فاتورة شراء بدون أصناف');
    }

    final branchId = await _branchId();
    final now = DateTime.now();
    final purchaseId = _uuid.v4();

    // 1. Calculate total
    int totalAmount = 0;
    for (final it in items) {
      totalAmount += (it.qty * it.costPrice);
    }

    if (paidAmount > totalAmount) {
      throw Exception(
        'المبلغ المدفوع ($paidAmount قرش) أكبر من إجمالي الفاتورة ($totalAmount قرش)',
      );
    }

    // 2. Determine payment status
    String paymentStatus;
    if (paidAmount >= totalAmount) {
      paymentStatus = 'paid';
    } else if (paidAmount > 0) {
      paymentStatus = 'partial';
    } else {
      paymentStatus = 'unpaid';
    }

    // 3. Execute atomic transaction
    await _db.transaction(() async {
      // A. Insert Purchase
      await _db
          .into(_db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              branchId: branchId,
              supplierId: supplierId,
              invoiceNumber: Value(invoiceNumber?.trim()),
              purchaseDate: purchaseDate,
              totalAmount: totalAmount,
              paidAmount: Value(paidAmount),
              status: const Value('received'),
              paymentStatus: Value(paymentStatus),
              notes: Value(notes?.trim()),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // B. Insert Items & update stock (only update stock if NOT linked to existing goods receipt)
      for (final it in items) {
        final itemId = _uuid.v4();
        final lineTotal = it.qty * it.costPrice;

        await _db
            .into(_db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                id: itemId,
                purchaseId: purchaseId,
                variantId: it.variantId,
                qty: it.qty,
                costPrice: it.costPrice,
                totalCost: lineTotal,
                createdAt: now,
              ),
            );

        // Always update variant costPrice in product_variants
        final variant = await (_db.select(
          _db.productVariants,
        )..where((v) => v.id.equals(it.variantId))).getSingleOrNull();

        if (variant != null) {
          final shouldIncreaseStock =
              (goodsReceiptId == null || goodsReceiptId.trim().isEmpty);

          // Check if this variant belongs to a product that is raw material with a conversionFactor (packSize)
          final product = await (_db.select(_db.products)
                ..where((p) => p.id.equals(variant.productId)))
              .getSingleOrNull();
          final cul = RestaurantCulinaryData.parse(product?.description);
          final int factor = (cul.isRawMaterial &&
                  cul.conversionFactor != null &&
                  cul.conversionFactor! > 1)
              ? cul.conversionFactor!.round()
              : 1;

          final int effectiveQtyToAdd = (it.qty * factor).round();
          final int newQty = shouldIncreaseStock
              ? (variant.quantity + effectiveQtyToAdd)
              : variant.quantity;

          final int effectiveUnitCost = factor > 1
              ? (it.costPrice / factor).round()
              : it.costPrice;

          await (_db.update(
            _db.productVariants,
          )..where((v) => v.id.equals(it.variantId))).write(
            ProductVariantsCompanion(
              quantity: Value(newQty),
              costPrice: Value(effectiveUnitCost),
              updatedAt: Value(now),
            ),
          );

          if (shouldIncreaseStock) {
            // Write inventory log only if we increased stock
            await _db
                .into(_db.inventoryLogs)
                .insert(
                  InventoryLogsCompanion.insert(
                    id: _uuid.v4(),
                    branchId: branchId,
                    variantId: it.variantId,
                    type: 'in',
                    qtyDelta: effectiveQtyToAdd,
                    refType: 'purchase',
                    refId: Value(purchaseId),
                    reason: Value('فاتورة مشتريات #${invoiceNumber ?? ''}'),
                    userId: userId,
                    createdAt: now,
                  ),
                );
          }
        }
      }

      // If linked to goodsReceiptId, mark GoodsReceipt status as 'invoiced'
      if (goodsReceiptId != null && goodsReceiptId.trim().isNotEmpty) {
        await (_db.update(
          _db.goodsReceipts,
        )..where((g) => g.id.equals(goodsReceiptId.trim()))).write(
          GoodsReceiptsCompanion(
            status: const Value('invoiced'),
            updatedAt: Value(now),
          ),
        );
      }

      // C. If advance payment was made, record it
      if (paidAmount > 0) {
        final paymentId = _uuid.v4();
        await _db
            .into(_db.supplierPayments)
            .insert(
              SupplierPaymentsCompanion.insert(
                id: paymentId,
                branchId: branchId,
                supplierId: supplierId,
                purchaseId: Value(purchaseId),
                amount: paidAmount,
                paymentDate: purchaseDate,
                paymentMethod: const Value('cash'),
                referenceNumber: Value(invoiceNumber),
                notes: const Value('مقدم فاتورة شراء'),
                createdBy: userId,
                createdAt: now,
              ),
            );

        // Phase 2: Record in cash_movements instead of expenses
        final nowSec = now.millisecondsSinceEpoch ~/ 1000;
        await _db
            .into(_db.cashMovements)
            .insert(
              CashMovementsCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                shiftId: const Value.absent(),
                type: 'purchase_payment',
                method: 'cash',
                direction: 'out',
                amountPiasters: paidAmount,
                referenceId: Value(purchaseId),
                notes: Value('دفعة فاتورة شراء #${invoiceNumber ?? ''}'),
                createdAt: nowSec,
                updatedAt: nowSec,
              ),
            );
      }

      // D. Recompute Supplier balance (source of truth: SUM(purchases) - SUM(payments))
      await _recomputeSupplierBalance(supplierId);

      // Queue sync
      await _queueSync('purchases', purchaseId, 'insert', branchId);
    });

    final created = await getPurchaseById(purchaseId);
    return created!;
  }

  Future<List<PurchaseItemEntity>> _getItemsForPurchase(
    String purchaseId,
  ) async {
    final query = _db.select(_db.purchaseItems).join([
      innerJoin(
        _db.productVariants,
        _db.productVariants.id.equalsExp(_db.purchaseItems.variantId),
      ),
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])..where(_db.purchaseItems.purchaseId.equals(purchaseId));

    final rows = await query.get();

    return rows.map((r) {
      final item = r.readTable(_db.purchaseItems);
      final variant = r.readTable(_db.productVariants);
      final product = r.readTable(_db.products);

      return PurchaseItemEntity(
        id: item.id,
        purchaseId: item.purchaseId,
        variantId: item.variantId,
        productName: product.name,
        sku: variant.sku,
        color: variant.color,
        size: variant.size,
        qty: item.qty,
        costPrice: item.costPrice,
        totalCost: item.totalCost,
        createdAt: item.createdAt,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUPPLIER PAYMENTS (سداد دفعات الموردين)
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<SupplierPaymentEntity> addSupplierPayment({
    required String supplierId,
    String? purchaseId,
    required int amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? referenceNumber,
    String? notes,
    required String userId,
  }) async {
    if (amount <= 0) {
      throw Exception('مبلغ الدفعة يجب أن يكون أكبر من الصفر');
    }

    final branchId = await _branchId();
    final now = DateTime.now();
    final paymentId = _uuid.v4();

    await _db.transaction(() async {
      // 1. Insert payment
      await _db
          .into(_db.supplierPayments)
          .insert(
            SupplierPaymentsCompanion.insert(
              id: paymentId,
              branchId: branchId,
              supplierId: supplierId,
              purchaseId: Value(purchaseId),
              amount: amount,
              paymentDate: paymentDate,
              paymentMethod: Value(paymentMethod),
              referenceNumber: Value(referenceNumber?.trim()),
              notes: Value(notes?.trim()),
              createdBy: userId,
              createdAt: now,
            ),
          );

      // 2. If purchaseId is null, FIFO-allocate across open invoices (oldest first)
      if (purchaseId == null) {
        int remaining = amount;

        final openInvoices =
            await (_db.select(_db.purchases)
                  ..where(
                    (p) =>
                        p.supplierId.equals(supplierId) &
                        p.deletedAt.isNull() &
                        p.paidAmount.isSmallerThan(p.totalAmount),
                  )
                  ..orderBy([
                    (p) => OrderingTerm.asc(p.purchaseDate),
                    (p) => OrderingTerm.asc(p.createdAt),
                  ]))
                .get();

        for (final invoice in openInvoices) {
          if (remaining <= 0) break;

          final invoiceRemaining = invoice.totalAmount - invoice.paidAmount;
          final allocate = remaining < invoiceRemaining
              ? remaining
              : invoiceRemaining;
          final newPaid = invoice.paidAmount + allocate;
          final newStatus = newPaid >= invoice.totalAmount ? 'paid' : 'partial';

          await (_db.update(
            _db.purchases,
          )..where((p) => p.id.equals(invoice.id))).write(
            PurchasesCompanion(
              paidAmount: Value(newPaid),
              paymentStatus: Value(newStatus),
              updatedAt: Value(now),
            ),
          );

          remaining -= allocate;
        }
      } else {
        // 3. If tied to a specific purchase, update that purchase paidAmount & status
        final purchase = await (_db.select(
          _db.purchases,
        )..where((p) => p.id.equals(purchaseId))).getSingleOrNull();

        if (purchase != null) {
          final invoiceRemaining = purchase.totalAmount - purchase.paidAmount;
          if (amount > invoiceRemaining) {
            throw Exception(
              'المبلغ المدفوع ($amount قرش) أكبر من المتبقي على الفاتورة ($invoiceRemaining قرش)',
            );
          }
          final newPaid = purchase.paidAmount + amount;
          final newStatus = newPaid >= purchase.totalAmount
              ? 'paid'
              : 'partial';

          await (_db.update(
            _db.purchases,
          )..where((p) => p.id.equals(purchaseId))).write(
            PurchasesCompanion(
              paidAmount: Value(newPaid),
              paymentStatus: Value(newStatus),
              updatedAt: Value(now),
            ),
          );
        }
      }

      // 4. Recompute supplier balance (single source of truth: SUM(purchases) - SUM(payments))
      await _recomputeSupplierBalance(supplierId);

      // 4. Phase 2: Log in cash_movements instead of expenses
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      final mMethod = paymentMethod.toLowerCase() == 'card'
          ? 'card'
          : (paymentMethod.toLowerCase() == 'transfer' ? 'transfer' : 'cash');
      await _db
          .into(_db.cashMovements)
          .insert(
            CashMovementsCompanion.insert(
              id: _uuid.v4(),
              branchId: branchId,
              shiftId: const Value.absent(),
              type: 'supplier_payment',
              method: mMethod,
              direction: 'out',
              amountPiasters: amount,
              referenceId: Value(paymentId),
              notes: Value(notes ?? 'سداد دفعة مورد'),
              createdAt: nowSec,
              updatedAt: nowSec,
            ),
          );

      // Queue sync
      await _queueSync('supplier_payments', paymentId, 'insert', branchId);
    });

    final supplier = await getSupplierById(supplierId);
    final purchase = purchaseId != null
        ? await getPurchaseById(purchaseId)
        : null;

    return SupplierPaymentEntity(
      id: paymentId,
      branchId: branchId,
      supplierId: supplierId,
      supplierName: supplier?.name,
      purchaseId: purchaseId,
      purchaseInvoiceNumber: purchase?.invoiceNumber,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      notes: notes,
      createdBy: userId,
      createdAt: now,
    );
  }

  @override
  Future<List<SupplierPaymentEntity>> getSupplierPayments({
    String? supplierId,
    String? purchaseId,
  }) async {
    var query = _db.select(_db.supplierPayments);

    if (supplierId != null) {
      query = query..where((p) => p.supplierId.equals(supplierId));
    }
    if (purchaseId != null) {
      query = query..where((p) => p.purchaseId.equals(purchaseId));
    }

    query = query..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]);
    final rows = await query.get();

    final result = <SupplierPaymentEntity>[];
    for (final r in rows) {
      final supplier = await getSupplierById(r.supplierId);
      final purchase = r.purchaseId != null
          ? await getPurchaseById(r.purchaseId!)
          : null;

      result.add(
        SupplierPaymentEntity(
          id: r.id,
          branchId: r.branchId,
          supplierId: r.supplierId,
          supplierName: supplier?.name,
          purchaseId: r.purchaseId,
          purchaseInvoiceNumber: purchase?.invoiceNumber,
          amount: r.amount,
          paymentDate: r.paymentDate,
          paymentMethod: r.paymentMethod,
          referenceNumber: r.referenceNumber,
          notes: r.notes,
          createdBy: r.createdBy,
          createdAt: r.createdAt,
        ),
      );
    }

    return result;
  }

  Future<void> _queueSync(
    String entity,
    String entityId,
    String operation,
    String branchId,
  ) async {
    final now = DateTime.now();
    await _db
        .into(_db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            id: _uuid.v4(),
            branchId: branchId,
            entity: entity,
            entityId: entityId,
            operation: operation,
            payload: '{}',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> _ensureReturnTables() async {
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS purchase_returns (
        id TEXT NOT NULL PRIMARY KEY,
        branch_id TEXT NOT NULL,
        purchase_id TEXT,
        supplier_id TEXT NOT NULL,
        total_amount INTEGER NOT NULL,
        refund_type TEXT NOT NULL,
        reason TEXT,
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS purchase_return_items (
        id TEXT NOT NULL PRIMARY KEY,
        return_id TEXT NOT NULL,
        variant_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        variant_info TEXT NOT NULL,
        sku TEXT NOT NULL,
        qty INTEGER NOT NULL,
        cost_price INTEGER NOT NULL,
        total_cost INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
  }

  Future<void> _recomputeSupplierBalance(String supplierId) async {
    final purchasesRows =
        await (_db.select(_db.purchases)..where(
              (p) => p.supplierId.equals(supplierId) & p.deletedAt.isNull(),
            ))
            .get();
    final purchasesTotal = purchasesRows.fold<int>(
      0,
      (sum, p) => sum + p.totalAmount,
    );

    final paymentsRows = await (_db.select(
      _db.supplierPayments,
    )..where((p) => p.supplierId.equals(supplierId))).get();
    final paymentsTotal = paymentsRows.fold<int>(0, (sum, p) => sum + p.amount);

    await _ensureReturnTables();
    final creditReturnsResult = await _db
        .customSelect(
          "SELECT COALESCE(SUM(total_amount), 0) AS total FROM purchase_returns WHERE supplier_id = ? AND refund_type = 'credit'",
          variables: [Variable.withString(supplierId)],
        )
        .getSingle();
    final creditReturnsTotal = creditReturnsResult.read<int>('total');

    final newBalance = purchasesTotal - paymentsTotal - creditReturnsTotal;

    await (_db.update(
      _db.suppliers,
    )..where((s) => s.id.equals(supplierId))).write(
      SuppliersCompanion(
        balance: Value(newBalance),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PURCHASE RETURNS (مرتجعات المشتريات للموردين)
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Future<PurchaseReturnEntity> createPurchaseReturn({
    required String supplierId,
    String? purchaseId,
    required List<PurchaseReturnItemDraft> items,
    required String refundType,
    String? reason,
    required String userId,
  }) async {
    if (items.isEmpty) {
      throw Exception('لا يمكن إنشاء مرتجع مشتريات بدون أصناف');
    }
    if (refundType != 'credit' && refundType != 'cash') {
      throw Exception(
        'نوع تسوية المرتجع غير صالح (يجب أن يكون رصيد credit أو نقدي cash)',
      );
    }

    await _ensureReturnTables();
    final branchId = await _branchId();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final nowSec = nowMs ~/ 1000;
    final returnId = _uuid.v4();

    // 1. Verify stock availability for all items before executing transaction
    for (final it in items) {
      if (it.qty <= 0) {
        throw Exception('الكمية المرتجعة يجب أن تكون أكبر من الصفر');
      }
      final variant = await (_db.select(
        _db.productVariants,
      )..where((v) => v.id.equals(it.variantId))).getSingleOrNull();

      if (variant == null) {
        throw Exception('الصنف غير موجود بالمخزن: ${it.productName}');
      }
      if (variant.quantity < it.qty) {
        throw Exception(
          'الكمية المتوفرة في المخزن من (${it.productName} - ${it.variantInfo}) هي ${variant.quantity} فقط، لا يمكن إرجاع ${it.qty} قطعة للمورد',
        );
      }
    }

    // 2. Calculate total
    int totalAmount = 0;
    for (final it in items) {
      totalAmount += (it.qty * it.costPrice);
    }

    // 3. Atomic Transaction
    await _db.transaction(() async {
      // A. Insert into purchase_returns
      await _db.customStatement(
        '''
        INSERT INTO purchase_returns
          (id, branch_id, purchase_id, supplier_id, total_amount, refund_type, reason, created_by, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          returnId,
          branchId,
          purchaseId,
          supplierId,
          totalAmount,
          refundType,
          reason,
          userId,
          nowMs,
        ],
      );

      // B. Insert items, deduct variant quantities & record inventory logs
      for (final it in items) {
        final itemId = _uuid.v4();
        final lineTotal = it.qty * it.costPrice;

        await _db.customStatement(
          '''
          INSERT INTO purchase_return_items
            (id, return_id, variant_id, product_name, variant_info, sku, qty, cost_price, total_cost, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            itemId,
            returnId,
            it.variantId,
            it.productName,
            it.variantInfo,
            it.sku,
            it.qty,
            it.costPrice,
            lineTotal,
            nowMs,
          ],
        );

        // Deduct from stock
        final variant = await (_db.select(
          _db.productVariants,
        )..where((v) => v.id.equals(it.variantId))).getSingle();

        final newQty = variant.quantity - it.qty;
        await (_db.update(
          _db.productVariants,
        )..where((v) => v.id.equals(it.variantId))).write(
          ProductVariantsCompanion(
            quantity: Value(newQty),
            updatedAt: Value(now),
          ),
        );

        // Record Inventory Log
        await _db
            .into(_db.inventoryLogs)
            .insert(
              InventoryLogsCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                variantId: it.variantId,
                type: 'out',
                qtyDelta: -it.qty,
                refType: 'purchase_return',
                refId: Value(returnId),
                reason: Value(
                  reason?.trim().isNotEmpty == true
                      ? 'مرتجع مشتريات للمورد: ${reason!.trim()}'
                      : 'مرتجع مشتريات للمورد',
                ),
                userId: userId,
                createdAt: now,
              ),
            );
      }

      // C. If cash refund, record cash movement into cash drawer
      if (refundType == 'cash') {
        final activeShift = await (_db.select(
          _db.shifts,
        )..where((s) => s.closedAt.isNull())).getSingleOrNull();

        await _db
            .into(_db.cashMovements)
            .insert(
              CashMovementsCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                shiftId: Value(activeShift?.id),
                type: 'purchase_reversal',
                method: 'cash',
                direction: 'in',
                amountPiasters: totalAmount,
                referenceId: Value(returnId),
                notes: Value(
                  reason?.trim().isNotEmpty == true
                      ? 'استرداد نقدي لمرتجع مشتريات: ${reason!.trim()}'
                      : 'استرداد نقدي لمرتجع مشتريات للمورد',
                ),
                createdAt: nowSec,
                updatedAt: nowSec,
              ),
            );
      }

      // D. Recompute Supplier Balance
      await _recomputeSupplierBalance(supplierId);

      // E. Queue sync
      await _queueSync('purchase_returns', returnId, 'insert', branchId);
    });

    final createdList = await getPurchaseReturns(supplierId: supplierId);
    return createdList.firstWhere((r) => r.id == returnId);
  }

  @override
  Future<List<PurchaseReturnEntity>> getPurchaseReturns({
    String? supplierId,
    String? purchaseId,
  }) async {
    await _ensureReturnTables();

    var sql = 'SELECT * FROM purchase_returns WHERE 1=1';
    final vars = <Variable>[];

    if (supplierId != null && supplierId.isNotEmpty) {
      sql += ' AND supplier_id = ?';
      vars.add(Variable.withString(supplierId));
    }
    if (purchaseId != null && purchaseId.isNotEmpty) {
      sql += ' AND purchase_id = ?';
      vars.add(Variable.withString(purchaseId));
    }

    sql += ' ORDER BY created_at DESC';

    final rows = await _db.customSelect(sql, variables: vars).get();

    final result = <PurchaseReturnEntity>[];
    for (final r in rows) {
      final sId = r.read<String>('supplier_id');
      final pId = r.readNullable<String>('purchase_id');
      final supplier = await getSupplierById(sId);
      final purchase = pId != null ? await getPurchaseById(pId) : null;
      final retId = r.read<String>('id');

      final itemRows = await _db
          .customSelect(
            'SELECT * FROM purchase_return_items WHERE return_id = ? ORDER BY created_at ASC',
            variables: [Variable.withString(retId)],
          )
          .get();

      final items = itemRows
          .map(
            (ir) => PurchaseReturnItemEntity(
              id: ir.read<String>('id'),
              returnId: ir.read<String>('return_id'),
              variantId: ir.read<String>('variant_id'),
              productName: ir.read<String>('product_name'),
              variantInfo: ir.read<String>('variant_info'),
              sku: ir.read<String>('sku'),
              qty: ir.read<int>('qty'),
              costPrice: ir.read<int>('cost_price'),
              totalCost: ir.read<int>('total_cost'),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                ir.read<int>('created_at'),
              ),
            ),
          )
          .toList();

      result.add(
        PurchaseReturnEntity(
          id: retId,
          branchId: r.read<String>('branch_id'),
          purchaseId: pId,
          purchaseInvoiceNumber: purchase?.invoiceNumber,
          supplierId: sId,
          supplierName: supplier?.name,
          totalAmount: r.read<int>('total_amount'),
          refundType: r.read<String>('refund_type'),
          reason: r.readNullable<String>('reason'),
          createdBy: r.read<String>('created_by'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('created_at'),
          ),
          items: items,
        ),
      );
    }

    return result;
  }
}
