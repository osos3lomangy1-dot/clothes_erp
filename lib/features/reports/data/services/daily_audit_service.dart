import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';

class DailyAuditSaleEntry {
  final Sale sale;
  final String cashierName;
  final String? customerName;
  final List<SaleItem> items;

  const DailyAuditSaleEntry({
    required this.sale,
    required this.cashierName,
    this.customerName,
    required this.items,
  });
}

class DailyAuditReturnEntry {
  final Return ret;
  final String cashierName;

  const DailyAuditReturnEntry({
    required this.ret,
    required this.cashierName,
  });
}

class DailyAuditExpenseEntry {
  final Expense expense;
  final String userName;

  const DailyAuditExpenseEntry({
    required this.expense,
    required this.userName,
  });
}

class DailyAuditInstallmentEntry {
  final InstallmentPayment payment;
  final String recordedByName;

  const DailyAuditInstallmentEntry({
    required this.payment,
    required this.recordedByName,
  });
}

class DailyAuditPurchaseEntry {
  final Purchase purchase;
  final String supplierName;

  const DailyAuditPurchaseEntry({
    required this.purchase,
    required this.supplierName,
  });
}

class DailyAuditSupplierPaymentEntry {
  final SupplierPayment payment;
  final String supplierName;
  final String createdByName;

  const DailyAuditSupplierPaymentEntry({
    required this.payment,
    required this.supplierName,
    required this.createdByName,
  });
}

class DailyAuditShiftEntry {
  final Shift shift;
  final String cashierName;

  const DailyAuditShiftEntry({
    required this.shift,
    required this.cashierName,
  });
}

class DailyAuditSnapshot {
  final DateTime startDate;
  final DateTime endDate;
  final List<DailyAuditSaleEntry> sales;
  final List<DailyAuditReturnEntry> returns;
  final List<DailyAuditExpenseEntry> expenses;
  final List<DailyAuditInstallmentEntry> installmentPayments;
  final List<DailyAuditPurchaseEntry> purchases;
  final List<DailyAuditSupplierPaymentEntry> supplierPayments;
  final List<DailyAuditShiftEntry> shifts;

  const DailyAuditSnapshot({
    required this.startDate,
    required this.endDate,
    required this.sales,
    required this.returns,
    required this.expenses,
    required this.installmentPayments,
    required this.purchases,
    required this.supplierPayments,
    required this.shifts,
  });

  int get totalSalesAmount => sales.fold(0, (s, e) => s + e.sale.total);
  int get totalReturnsAmount => returns.fold(0, (s, e) => s + e.ret.refundAmount);
  int get totalExpensesAmount => expenses.fold(0, (s, e) => s + e.expense.amount);
  int get totalInstallmentsAmount =>
      installmentPayments.fold(0, (s, e) => s + e.payment.amountPiasters);
  int get totalPurchasesAmount =>
      purchases.fold(0, (s, e) => s + e.purchase.totalAmount);
  int get totalSupplierPaymentsAmount =>
      supplierPayments.fold(0, (s, e) => s + e.payment.amount);
}

/// Loads all daily/period operational details from local Drift DB for audit drill-down.
class DailyAuditService {
  final AppDatabase _db;

  DailyAuditService(this._db);

  Future<DailyAuditSnapshot> loadRange(DateTime startDate, DateTime endDate) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

    final results = await Future.wait<dynamic>([
      (_db.select(_db.users)).get(),
      (_db.select(_db.customers)).get(),
      (_db.select(_db.suppliers)).get(),
      (_db.select(_db.sales)
            ..where((s) =>
                s.date.isBiggerOrEqualValue(start) &
                s.date.isSmallerOrEqualValue(end) &
                s.deletedAt.isNull() &
                s.status.isNotValue('cancelled'))
            ..orderBy([(s) => OrderingTerm.desc(s.date)]))
          .get(),
      (_db.select(_db.returns)
            ..where((r) =>
                r.date.isBiggerOrEqualValue(start) &
                r.date.isSmallerOrEqualValue(end) &
                r.deletedAt.isNull())
            ..orderBy([(r) => OrderingTerm.desc(r.date)]))
          .get(),
      (_db.select(_db.expenses)
            ..where((e) =>
                e.expenseDate.isBiggerOrEqualValue(start) &
                e.expenseDate.isSmallerOrEqualValue(end) &
                e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]))
          .get(),
      (_db.select(_db.installmentPayments)
            ..where((p) =>
                p.paidAt.isBiggerOrEqualValue(start) &
                p.paidAt.isSmallerOrEqualValue(end) &
                p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.desc(p.paidAt)]))
          .get(),
      (_db.select(_db.purchases)
            ..where((p) =>
                p.purchaseDate.isBiggerOrEqualValue(start) &
                p.purchaseDate.isSmallerOrEqualValue(end) &
                p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
          .get(),
      (_db.select(_db.supplierPayments)
            ..where((p) =>
                p.paymentDate.isBiggerOrEqualValue(start) &
                p.paymentDate.isSmallerOrEqualValue(end))
            ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
          .get(),
      (_db.select(_db.shifts)
            ..where((s) =>
                s.openedAt.isBiggerOrEqualValue(start) &
                s.openedAt.isSmallerOrEqualValue(end) &
                s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)]))
          .get(),
    ]);

    final users = {for (final u in results[0] as List<User>) u.id: u.displayName};
    final customers = {
      for (final c in results[1] as List<Customer>) c.id: c.name,
    };
    final suppliers = {
      for (final s in results[2] as List<Supplier>) s.id: s.name,
    };

    final salesRows = results[3] as List<Sale>;
    final saleIds = salesRows.map((s) => s.id).toList();
    final Map<String, List<SaleItem>> itemsBySale = {};
    if (saleIds.isNotEmpty) {
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleId.isIn(saleIds)))
          .get();
      for (final item in items) {
        itemsBySale.putIfAbsent(item.saleId, () => []).add(item);
      }
    }

    return DailyAuditSnapshot(
      startDate: start,
      endDate: end,
      sales: salesRows
          .map(
            (s) => DailyAuditSaleEntry(
              sale: s,
              cashierName: users[s.cashierId] ?? s.cashierId,
              customerName:
                  s.customerId != null ? customers[s.customerId!] : null,
              items: itemsBySale[s.id] ?? const [],
            ),
          )
          .toList(),
      returns: (results[4] as List<Return>)
          .map(
            (r) => DailyAuditReturnEntry(
              ret: r,
              cashierName: users[r.cashierId] ?? r.cashierId,
            ),
          )
          .toList(),
      expenses: (results[5] as List<Expense>)
          .map(
            (e) => DailyAuditExpenseEntry(
              expense: e,
              userName: users[e.userId] ?? e.userId,
            ),
          )
          .toList(),
      installmentPayments: (results[6] as List<InstallmentPayment>)
          .map(
            (p) => DailyAuditInstallmentEntry(
              payment: p,
              recordedByName: users[p.recordedBy] ?? p.recordedBy,
            ),
          )
          .toList(),
      purchases: (results[7] as List<Purchase>)
          .map(
            (p) => DailyAuditPurchaseEntry(
              purchase: p,
              supplierName: suppliers[p.supplierId] ?? p.supplierId,
            ),
          )
          .toList(),
      supplierPayments: (results[8] as List<SupplierPayment>)
          .map(
            (p) => DailyAuditSupplierPaymentEntry(
              payment: p,
              supplierName: suppliers[p.supplierId] ?? p.supplierId,
              createdByName: users[p.createdBy] ?? p.createdBy,
            ),
          )
          .toList(),
      shifts: (results[9] as List<Shift>)
          .map(
            (s) => DailyAuditShiftEntry(
              shift: s,
              cashierName: users[s.cashierId] ?? s.cashierId,
            ),
          )
          .toList(),
    );
  }
}
