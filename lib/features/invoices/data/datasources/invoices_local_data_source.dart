import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../../domain/entities/invoice_item_details_entity.dart';

abstract class InvoicesLocalDataSource {
  Future<List<InvoiceDetailsEntity>> getInvoices({
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? cashierId,
    String? paymentMethod,
    int limit = 100,
  });

  Future<InvoiceDetailsEntity?> getInvoiceById(String id);
  Future<InvoiceDetailsEntity?> getInvoiceByShortRef(String shortRef);
}

@LazySingleton(as: InvoicesLocalDataSource)
class InvoicesLocalDataSourceImpl implements InvoicesLocalDataSource {
  final AppDatabase _db;

  InvoicesLocalDataSourceImpl(this._db);

  @override
  Future<List<InvoiceDetailsEntity>> getInvoices({
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
    String? cashierId,
    String? paymentMethod,
    int limit = 100,
  }) async {
    final query = _db.select(_db.sales).join([
      leftOuterJoin(_db.customers, _db.customers.id.equalsExp(_db.sales.customerId)),
      leftOuterJoin(_db.users, _db.users.id.equalsExp(_db.sales.cashierId)),
    ])..where(_db.sales.deletedAt.isNull());

    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
      query.where(_db.sales.date.isBiggerOrEqualValue(start));
    }
    if (toDate != null) {
      final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      query.where(_db.sales.date.isSmallerOrEqualValue(end));
    }
    if (cashierId != null && cashierId.isNotEmpty) {
      query.where(_db.sales.cashierId.equals(cashierId));
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      query.where(_db.sales.paymentMethod.equals(paymentMethod));
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim();
      query.where(
        _db.sales.shortRef.contains(q) |
            _db.customers.name.contains(q) |
            _db.customers.phone.contains(q),
      );
    }

    query.orderBy([OrderingTerm.desc(_db.sales.date)]);
    query.limit(limit);

    final rows = await query.get();
    if (rows.isEmpty) return [];

    final saleIds = rows.map((r) => r.readTable(_db.sales).id).toList();

    final itemsRows = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.isIn(saleIds))
          ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
        .get();

    final Map<String, List<InvoiceItemDetailsEntity>> itemsMap = {};
    for (final it in itemsRows) {
      final list = itemsMap.putIfAbsent(it.saleId, () => []);
      list.add(InvoiceItemDetailsEntity(
        id: it.id,
        variantId: it.variantId,
        productName: it.productName,
        color: it.color,
        size: it.size,
        qty: it.qty,
        price: it.priceSnapshot,
        lineDiscount: it.lineDiscount,
        lineTotal: it.lineTotal,
      ));
    }

    return rows.map((r) {
      final s = r.readTable(_db.sales);
      final c = r.readTableOrNull(_db.customers);
      final u = r.readTableOrNull(_db.users);

      return InvoiceDetailsEntity(
        id: s.id,
        shortRef: s.shortRef,
        date: s.date,
        cashierId: s.cashierId,
        cashierName: u?.displayName ?? s.cashierId,
        customerId: s.customerId,
        customerName: c?.name,
        customerPhone: c?.phone,
        subtotal: s.subtotal,
        discountAmount: s.discountAmount,
        total: s.total,
        paymentMethod: s.paymentMethod,
        shiftId: s.shiftId,
        status: s.status,
        items: itemsMap[s.id] ?? [],
      );
    }).toList();
  }

  @override
  Future<InvoiceDetailsEntity?> getInvoiceById(String id) async {
    // Find directly
    final row = await (_db.select(_db.sales).join([
      leftOuterJoin(_db.customers, _db.customers.id.equalsExp(_db.sales.customerId)),
      leftOuterJoin(_db.users, _db.users.id.equalsExp(_db.sales.cashierId)),
    ])..where(_db.sales.id.equals(id) & _db.sales.deletedAt.isNull()))
        .getSingleOrNull();

    if (row == null) return null;

    final s = row.readTable(_db.sales);
    final c = row.readTableOrNull(_db.customers);
    final u = row.readTableOrNull(_db.users);

    final itemsRows = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(s.id))
          ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
        .get();

    final items = itemsRows
        .map((it) => InvoiceItemDetailsEntity(
              id: it.id,
              variantId: it.variantId,
              productName: it.productName,
              color: it.color,
              size: it.size,
              qty: it.qty,
              price: it.priceSnapshot,
              lineDiscount: it.lineDiscount,
              lineTotal: it.lineTotal,
            ))
        .toList();

    return InvoiceDetailsEntity(
      id: s.id,
      shortRef: s.shortRef,
      date: s.date,
      cashierId: s.cashierId,
      cashierName: u?.displayName ?? s.cashierId,
      customerId: s.customerId,
      customerName: c?.name,
      customerPhone: c?.phone,
      subtotal: s.subtotal,
      discountAmount: s.discountAmount,
      total: s.total,
      paymentMethod: s.paymentMethod,
      shiftId: s.shiftId,
      status: s.status,
      items: items,
    );
  }

  @override
  Future<InvoiceDetailsEntity?> getInvoiceByShortRef(String shortRef) async {
    final row = await (_db.select(_db.sales).join([
      leftOuterJoin(_db.customers, _db.customers.id.equalsExp(_db.sales.customerId)),
      leftOuterJoin(_db.users, _db.users.id.equalsExp(_db.sales.cashierId)),
    ])..where(_db.sales.shortRef.equals(shortRef) & _db.sales.deletedAt.isNull()))
        .getSingleOrNull();

    if (row == null) return null;

    final s = row.readTable(_db.sales);
    final c = row.readTableOrNull(_db.customers);
    final u = row.readTableOrNull(_db.users);

    final itemsRows = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(s.id))
          ..orderBy([(i) => OrderingTerm.asc(i.createdAt)]))
        .get();

    final items = itemsRows
        .map((it) => InvoiceItemDetailsEntity(
              id: it.id,
              variantId: it.variantId,
              productName: it.productName,
              color: it.color,
              size: it.size,
              qty: it.qty,
              price: it.priceSnapshot,
              lineDiscount: it.lineDiscount,
              lineTotal: it.lineTotal,
            ))
        .toList();

    return InvoiceDetailsEntity(
      id: s.id,
      shortRef: s.shortRef,
      date: s.date,
      cashierId: s.cashierId,
      cashierName: u?.displayName ?? s.cashierId,
      customerId: s.customerId,
      customerName: c?.name,
      customerPhone: c?.phone,
      subtotal: s.subtotal,
      discountAmount: s.discountAmount,
      total: s.total,
      paymentMethod: s.paymentMethod,
      shiftId: s.shiftId,
      status: s.status,
      items: items,
    );
  }
}

