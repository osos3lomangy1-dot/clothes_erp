import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../features/inventory/data/datasources/inventory_local_data_source.dart';
import '../../../../features/promotions/domain/entities/promotion.dart';
import '../../domain/entities/payment_split.dart';

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

  Future<String> checkout({
    required List<Map<String, dynamic>> items,
    required int total,
    required String cashierId,
    String? customerId,
    String? shiftId,
    String? paymentMethod,
    List<PaymentSplit>? splits,
    String? saleId,
    PromotionEvaluationResult? promotionResult,
  }) async {
    final now = DateTime.now();
    final branchId = await _branchId();
    final effectiveSaleId = saleId ?? _uuid.v4();

    String? effectiveShiftId = shiftId;
    if (effectiveShiftId == null) {
      final activeShift = await (_db.select(_db.shifts)
            ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(1))
          .getSingleOrNull();
      if (activeShift != null) {
        effectiveShiftId = activeShift.id;
      }
    }

    final isInstallment = paymentMethod == 'installment';
    final isCredit = paymentMethod == 'credit';
    final effectiveSplits = (splits != null && splits.isNotEmpty)
        ? splits
        : [
            PaymentSplit(
              method: isCredit
                  ? 'credit'
                  : ((paymentMethod != null && paymentMethod.toLowerCase() == 'card')
                      ? 'card'
                      : 'cash'),
              amountPiasters: total,
            ),
          ];

    final effectivePaymentMethod = isInstallment
        ? 'installment'
        : (isCredit
            ? 'credit'
            : (effectiveSplits.length > 1 ? 'split' : effectiveSplits.first.method));

    final nowSec = now.millisecondsSinceEpoch ~/ 1000;

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.sales).insert(SalesCompanion.insert(
          id: effectiveSaleId,
          branchId: branchId,
          shortRef: 'S${now.millisecondsSinceEpoch}',
          cashierId: cashierId,
          shiftId: Value(effectiveShiftId),
          customerId: Value(customerId),
          subtotal: total,
          discountType: 'none',
          total: total,
          paymentMethod: effectivePaymentMethod,
          date: now,
          createdAt: now,
          updatedAt: now,
        ));
        final saleItemIds = <String>[];
        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          final sItemId = _uuid.v4();
          saleItemIds.add(sItemId);

          final promoDiscount = (item['promotionDiscount'] as num?)?.toInt() ?? 0;
          final lineDiscount = (item['discount'] as num?)?.toInt() ?? 0;
          final price = item['price'] as int;
          final qty = item['qty'] as int;
          final decimalQty = (item['decimalQty'] as num?)?.toDouble();
          final effectiveQty = (item['effectiveQty'] as num?)?.toDouble() ??
              ((decimalQty != null && decimalQty > 0) ? decimalQty : qty.toDouble());
          final calculatedLineTotal = (price * effectiveQty).round() - lineDiscount - promoDiscount;
          final lineTotal = calculatedLineTotal < 0 ? 0 : calculatedLineTotal;

          final effectiveSize = (decimalQty != null && decimalQty > 0)
              ? '${item['size'] ?? ""} • $decimalQty ${item['unit'] ?? "م"}'.trim()
              : (item['size'] as String? ?? '-');

          await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
            id: sItemId,
            branchId: branchId,
            saleId: effectiveSaleId,
            variantId: item['variantId'] as String,
            productName: item['name'] as String,
            color: item['color'] as String,
            size: effectiveSize,
            qty: qty,
            priceSnapshot: price,
            costSnapshot: item['cost'] as int,
            lineDiscount: Value(lineDiscount),
            promotionDiscountPiasters: Value(promoDiscount),
            lineTotal: lineTotal,
            createdAt: now,
          ));
          if (decimalQty != null && decimalQty > 0) {
            final decimalStockKey = 'stock_decimal_${item['variantId']}';
            final metaRow = await (_db.select(_db.appMeta)
                  ..where((m) => m.key.equals(decimalStockKey)))
                .getSingleOrNull();
            double currentStock;
            if (metaRow != null) {
              currentStock = double.tryParse(metaRow.value) ?? 0.0;
            } else {
              final v = await (_db.select(_db.productVariants)
                    ..where((pv) => pv.id.equals(item['variantId'] as String)))
                  .getSingleOrNull();
              currentStock = (v?.quantity ?? 0).toDouble();
            }
            final newStock = currentStock - decimalQty;
            await _db.into(_db.appMeta).insertOnConflictUpdate(
              AppMetaCompanion.insert(
                key: decimalStockKey,
                value: newStock.toString(),
                updatedAt: now,
              ),
            );
          }

          await _inventory.applyStockMovement(
            variantId: item['variantId'] as String,
            qtyDelta: -qty,
            type: StockMovementType.sale,
            reason: 'sale',
            userId: cashierId,
            refType: 'sale',
            refId: effectiveSaleId,
          );
        }

        // Record promotion applications if applicable
        if (promotionResult != null) {
          for (int i = 0; i < saleItemIds.length && i < promotionResult.lineResults.length; i++) {
            final lineRes = promotionResult.lineResults[i];
            final applied = lineRes.appliedPromotion;
            final promoDisc = lineRes.promotionDiscountPiasters;
            if (applied != null && promoDisc > 0) {
              await _db.into(_db.promotionApplications).insert(
                PromotionApplicationsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  promotionId: applied.id,
                  saleId: effectiveSaleId,
                  saleItemId: saleItemIds[i],
                  discountPiasters: promoDisc,
                  createdAt: now,
                ),
              );
            }
          }
        }

        // For non-installment sales, write sale_payments and cash_movements (sale)
        if (!isInstallment && !isCredit) {
          for (final split in effectiveSplits) {
            final spId = _uuid.v4();
            await _db.into(_db.salePayments).insert(
              SalePaymentsCompanion.insert(
                id: spId,
                branchId: branchId,
                saleId: effectiveSaleId,
                method: split.method,
                amountPiasters: split.amountPiasters,
                shiftId: Value(effectiveShiftId),
                createdAt: nowSec,
                updatedAt: nowSec,
              ),
            );

            await _db.into(_db.cashMovements).insert(
              CashMovementsCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                shiftId: Value(effectiveShiftId),
                type: 'sale',
                method: split.method,
                direction: 'in',
                amountPiasters: split.amountPiasters,
                referenceId: Value(effectiveSaleId),
                notes: Value('مبيعات نقطة بيع (${split.method})'),
                createdAt: nowSec,
                updatedAt: nowSec,
              ),
            );
          }
        } else if (isCredit) {
          // In credit sales, record down payments (cash/card) in sale_payments & cash_movements
          for (final split in effectiveSplits) {
            if (split.method != 'credit' && split.amountPiasters > 0) {
              final spId = _uuid.v4();
              await _db.into(_db.salePayments).insert(
                SalePaymentsCompanion.insert(
                  id: spId,
                  branchId: branchId,
                  saleId: effectiveSaleId,
                  method: split.method,
                  amountPiasters: split.amountPiasters,
                  shiftId: Value(effectiveShiftId),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );

              await _db.into(_db.cashMovements).insert(
                CashMovementsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  shiftId: Value(effectiveShiftId),
                  type: 'sale',
                  method: split.method,
                  direction: 'in',
                  amountPiasters: split.amountPiasters,
                  referenceId: Value(effectiveSaleId),
                  notes: Value('دفعة مقدمة لمبيعات آجل (${split.method})'),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );
            }
          }
        }
      },
      branchId: branchId,
      entity: 'sale',
      entityId: effectiveSaleId,
      operation: 'insert',
      userId: cashierId,
    );
    // Flush committed WAL pages to disk to guarantee printed receipt durability on power-cut
    await _db.flushWal();
    return effectiveSaleId;
  }
}


