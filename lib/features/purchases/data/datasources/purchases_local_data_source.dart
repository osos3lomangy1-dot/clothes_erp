import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/purchase_item_entity.dart';
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
  Future<List<PurchaseEntity>> getPurchases({String? supplierId, String? paymentStatus});
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
  Future<List<SupplierPaymentEntity>> getSupplierPayments({String? supplierId, String? purchaseId});
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
    final rows = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .get();

    return rows.map(_mapSupplier).toList();
  }

  @override
  Future<SupplierEntity?> getSupplierById(String id) async {
    final row = await (_db.select(_db.suppliers)
          ..where((s) => s.id.equals(id) & s.deletedAt.isNull()))
        .getSingleOrNull();

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

    await _db.into(_db.suppliers).insert(
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
      SuppliersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
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

      result.add(PurchaseEntity(
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
      ));
    }

    return result;
  }

  @override
  Future<PurchaseEntity?> getPurchaseById(String id) async {
    final row = await (_db.select(_db.purchases)
          ..where((p) => p.id.equals(id) & p.deletedAt.isNull()))
        .getSingleOrNull();

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
      throw Exception('المبلغ المدفوع ($paidAmount قرش) أكبر من إجمالي الفاتورة ($totalAmount قرش)');
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
      await _db.into(_db.purchases).insert(
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

        await _db.into(_db.purchaseItems).insert(
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
        final variant = await (_db.select(_db.productVariants)
              ..where((v) => v.id.equals(it.variantId)))
            .getSingleOrNull();

        if (variant != null) {
          final shouldIncreaseStock = (goodsReceiptId == null || goodsReceiptId.trim().isEmpty);
          final newQty = shouldIncreaseStock ? (variant.quantity + it.qty) : variant.quantity;

          await (_db.update(_db.productVariants)
                ..where((v) => v.id.equals(it.variantId)))
              .write(
            ProductVariantsCompanion(
              quantity: Value(newQty),
              costPrice: Value(it.costPrice),
              updatedAt: Value(now),
            ),
          );

          if (shouldIncreaseStock) {
            // Write inventory log only if we increased stock
            await _db.into(_db.inventoryLogs).insert(
                  InventoryLogsCompanion.insert(
                    id: _uuid.v4(),
                    branchId: branchId,
                    variantId: it.variantId,
                    type: 'in',
                    qtyDelta: it.qty,
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
        await (_db.update(_db.goodsReceipts)
              ..where((g) => g.id.equals(goodsReceiptId.trim())))
            .write(
          GoodsReceiptsCompanion(
            status: const Value('invoiced'),
            updatedAt: Value(now),
          ),
        );
      }

      // C. If advance payment was made, record it
      if (paidAmount > 0) {
        final paymentId = _uuid.v4();
        await _db.into(_db.supplierPayments).insert(
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
        await _db.into(_db.cashMovements).insert(
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

  Future<List<PurchaseItemEntity>> _getItemsForPurchase(String purchaseId) async {
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
      await _db.into(_db.supplierPayments).insert(
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

        final openInvoices = await (_db.select(_db.purchases)
              ..where((p) =>
                  p.supplierId.equals(supplierId) &
                  p.deletedAt.isNull() &
                  p.paidAmount.isSmallerThan(p.totalAmount))
              ..orderBy([
                (p) => OrderingTerm.asc(p.purchaseDate),
                (p) => OrderingTerm.asc(p.createdAt),
              ]))
            .get();

        for (final invoice in openInvoices) {
          if (remaining <= 0) break;

          final invoiceRemaining = invoice.totalAmount - invoice.paidAmount;
          final allocate = remaining < invoiceRemaining ? remaining : invoiceRemaining;
          final newPaid = invoice.paidAmount + allocate;
          final newStatus = newPaid >= invoice.totalAmount ? 'paid' : 'partial';

          await (_db.update(_db.purchases)..where((p) => p.id.equals(invoice.id)))
              .write(PurchasesCompanion(
            paidAmount: Value(newPaid),
            paymentStatus: Value(newStatus),
            updatedAt: Value(now),
          ));

          remaining -= allocate;
        }
      } else {
        // 3. If tied to a specific purchase, update that purchase paidAmount & status
        final purchase = await (_db.select(_db.purchases)
              ..where((p) => p.id.equals(purchaseId)))
            .getSingleOrNull();

        if (purchase != null) {
          final invoiceRemaining = purchase.totalAmount - purchase.paidAmount;
          if (amount > invoiceRemaining) {
            throw Exception('المبلغ المدفوع ($amount قرش) أكبر من المتبقي على الفاتورة ($invoiceRemaining قرش)');
          }
          final newPaid = purchase.paidAmount + amount;
          final newStatus = newPaid >= purchase.totalAmount ? 'paid' : 'partial';

          await (_db.update(_db.purchases)..where((p) => p.id.equals(purchaseId)))
              .write(
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
      await _db.into(_db.cashMovements).insert(
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
    final purchase = purchaseId != null ? await getPurchaseById(purchaseId) : null;

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
      final purchase = r.purchaseId != null ? await getPurchaseById(r.purchaseId!) : null;

      result.add(SupplierPaymentEntity(
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
      ));
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
    await _db.into(_db.syncQueue).insert(
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

  Future<void> _recomputeSupplierBalance(String supplierId) async {
    final purchasesRows = await (_db.select(_db.purchases)
          ..where((p) => p.supplierId.equals(supplierId) & p.deletedAt.isNull()))
        .get();
    final purchasesTotal = purchasesRows.fold<int>(0, (sum, p) => sum + p.totalAmount);

    final paymentsRows = await (_db.select(_db.supplierPayments)
          ..where((p) => p.supplierId.equals(supplierId)))
        .get();
    final paymentsTotal = paymentsRows.fold<int>(0, (sum, p) => sum + p.amount);

    final newBalance = purchasesTotal - paymentsTotal;

    await (_db.update(_db.suppliers)..where((s) => s.id.equals(supplierId)))
        .write(SuppliersCompanion(
      balance: Value(newBalance),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

