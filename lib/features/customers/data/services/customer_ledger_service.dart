import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/excel_style_helper.dart';
import '../../domain/entities/customer_entity.dart';

class CustomerFinancialSummary {
  final int invoiceCount;
  final int totalSpentPiasters;
  final int activeInstallmentsCount;
  final int installmentsRemainingPiasters;
  final int creditDebtPiasters;
  final DateTime? lastPurchaseDate;

  const CustomerFinancialSummary({
    this.invoiceCount = 0,
    this.totalSpentPiasters = 0,
    this.activeInstallmentsCount = 0,
    this.installmentsRemainingPiasters = 0,
    this.creditDebtPiasters = 0,
    this.lastPurchaseDate,
  });

  static const empty = CustomerFinancialSummary();
}

class CustomerStatement {
  final CustomerFinancialSummary summary;
  final List<Sale> sales;
  final List<CustomerInstallment> installments;
  final List<LoyaltyTransaction> loyaltyLogs;
  final List<CustomerPayment> payments;

  const CustomerStatement({
    required this.summary,
    required this.sales,
    required this.installments,
    required this.loyaltyLogs,
    this.payments = const [],
  });
}

/// Provides CRM financial summaries, full customer statements (invoices,
/// installments, loyalty ledger), WhatsApp deep-links, and Excel export.
class CustomerLedgerService {
  final AppDatabase _db;

  CustomerLedgerService(this._db);

  /// Loads aggregated sales + active installment summaries for all customers
  /// in two lightweight queries (no N+1 queries).
  Future<Map<String, CustomerFinancialSummary>> getAllCustomerSummaries() async {
    final sales = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.deletedAt.isNull() &
                s.customerId.isNotNull() &
                s.status.isNotValue('cancelled'),
          ))
        .get();

    final installments = await (_db.select(_db.customerInstallments)
          ..where((c) => c.deletedAt.isNull()))
        .get();

    final payments = await (_db.select(_db.customerPayments)
          ..where((p) => p.deletedAt.isNull()))
        .get();

    final returnsJoin = await (_db.select(_db.returns).join([
      drift.innerJoin(_db.sales, _db.sales.id.equalsExp(_db.returns.saleId)),
    ])..where(
      _db.sales.customerId.isNotNull() &
      _db.returns.paymentMethod.equals('credit') &
      _db.returns.deletedAt.isNull(),
    )).get();

    final downPayments = await (_db.select(_db.salePayments)
          ..where((sp) => sp.deletedAt.isNull()))
        .get();
    final Map<String, int> saleToDownPayment = {};
    for (final sp in downPayments) {
      saleToDownPayment[sp.saleId] = (saleToDownPayment[sp.saleId] ?? 0) + sp.amountPiasters;
    }

    final invoiceCount = <String, int>{};
    final totalSpent = <String, int>{};
    final creditSalesTotal = <String, int>{};
    final lastDate = <String, DateTime>{};
    final activeInstCount = <String, int>{};
    final instRemaining = <String, int>{};
    final paymentsTotal = <String, int>{};
    final returnsCreditTotal = <String, int>{};

    for (final s in sales) {
      final cid = s.customerId;
      if (cid == null || cid.isEmpty) continue;
      invoiceCount[cid] = (invoiceCount[cid] ?? 0) + 1;
      totalSpent[cid] = (totalSpent[cid] ?? 0) + s.total;
      if (s.paymentMethod == 'credit') {
        final paidDown = saleToDownPayment[s.id] ?? 0;
        final creditPortion = s.total - paidDown;
        creditSalesTotal[cid] = (creditSalesTotal[cid] ?? 0) + (creditPortion < 0 ? 0 : creditPortion);
      }
      final prev = lastDate[cid];
      if (prev == null || s.date.isAfter(prev)) {
        lastDate[cid] = s.date;
      }
    }

    for (final p in payments) {
      final cid = p.customerId;
      if (cid.isEmpty) continue;
      paymentsTotal[cid] = (paymentsTotal[cid] ?? 0) + p.amount;
    }

    for (final row in returnsJoin) {
      final s = row.readTable(_db.sales);
      final r = row.readTable(_db.returns);
      final cid = s.customerId;
      if (cid == null || cid.isEmpty) continue;
      returnsCreditTotal[cid] = (returnsCreditTotal[cid] ?? 0) + r.refundAmount;
    }

    for (final c in installments) {
      if (c.status == 'active' || c.status == 'overdue') {
        activeInstCount[c.customerId] =
            (activeInstCount[c.customerId] ?? 0) + 1;
        instRemaining[c.customerId] =
            (instRemaining[c.customerId] ?? 0) + c.remainingPiasters;
      }
    }

    final allIds = <String>{
      ...invoiceCount.keys,
      ...activeInstCount.keys,
      ...creditSalesTotal.keys,
      ...paymentsTotal.keys,
    };
    return {
      for (final id in allIds)
        id: CustomerFinancialSummary(
          invoiceCount: invoiceCount[id] ?? 0,
          totalSpentPiasters: totalSpent[id] ?? 0,
          activeInstallmentsCount: activeInstCount[id] ?? 0,
          installmentsRemainingPiasters: instRemaining[id] ?? 0,
          creditDebtPiasters: () {
            final net = (creditSalesTotal[id] ?? 0) -
                (paymentsTotal[id] ?? 0) -
                (returnsCreditTotal[id] ?? 0);
            return net < 0 ? 0 : net;
          }(),
          lastPurchaseDate: lastDate[id],
        ),
    };
  }

  /// Loads a customer's complete financial & loyalty statement.
  Future<CustomerStatement> getCustomerStatement(String customerId) async {
    final sales = await (_db.select(_db.sales)
          ..where(
            (s) => s.customerId.equals(customerId) & s.deletedAt.isNull(),
          )
          ..orderBy([(s) => drift.OrderingTerm.desc(s.date)]))
        .get();

    final installments = await (_db.select(_db.customerInstallments)
          ..where(
            (c) => c.customerId.equals(customerId) & c.deletedAt.isNull(),
          )
          ..orderBy([(c) => drift.OrderingTerm.desc(c.startDate)]))
        .get();

    final payments = await (_db.select(_db.customerPayments)
          ..where(
            (p) => p.customerId.equals(customerId) & p.deletedAt.isNull(),
          )
          ..orderBy([(p) => drift.OrderingTerm.desc(p.paymentDate)]))
        .get();

    final returnsRows = await (_db.select(_db.returns).join([
      drift.innerJoin(_db.sales, _db.sales.id.equalsExp(_db.returns.saleId)),
    ])..where(
      _db.sales.customerId.equals(customerId) &
      _db.returns.paymentMethod.equals('credit') &
      _db.returns.deletedAt.isNull(),
    )).get();
    final returnsCreditTotal = returnsRows.fold<int>(0, (sum, r) => sum + r.readTable(_db.returns).refundAmount);

    final loyaltyLogs = await (_db.select(_db.loyaltyTransactions)
          ..where((l) => l.customerId.equals(customerId))
          ..orderBy([(l) => drift.OrderingTerm.desc(l.createdAt)]))
        .get();

    final completedSales =
        sales.where((s) => s.status != 'cancelled').toList();
    final totalSpent = completedSales.fold<int>(0, (sum, s) => sum + s.total);
    final activeInst = installments
        .where((c) => c.status == 'active' || c.status == 'overdue')
        .toList();
    final remaining = activeInst.fold<int>(
      0,
      (sum, c) => sum + c.remainingPiasters,
    );

    final downPayments = await (_db.select(_db.salePayments)
          ..where((sp) => sp.deletedAt.isNull()))
        .get();
    final Map<String, int> saleToDownPayment = {};
    for (final sp in downPayments) {
      saleToDownPayment[sp.saleId] = (saleToDownPayment[sp.saleId] ?? 0) + sp.amountPiasters;
    }

    final creditSalesTotal = completedSales
        .where((s) => s.paymentMethod == 'credit')
        .fold<int>(0, (sum, s) {
          final paidDown = saleToDownPayment[s.id] ?? 0;
          final creditPortion = s.total - paidDown;
          return sum + (creditPortion < 0 ? 0 : creditPortion);
        });
    final paymentsTotal = payments.fold<int>(0, (sum, p) => sum + p.amount);
    final netDebt = creditSalesTotal - paymentsTotal - returnsCreditTotal;
    final creditDebt = netDebt < 0 ? 0 : netDebt;

    return CustomerStatement(
      summary: CustomerFinancialSummary(
        invoiceCount: completedSales.length,
        totalSpentPiasters: totalSpent,
        activeInstallmentsCount: activeInst.length,
        installmentsRemainingPiasters: remaining,
        creditDebtPiasters: creditDebt,
        lastPurchaseDate:
            completedSales.isNotEmpty ? completedSales.first.date : null,
      ),
      sales: sales,
      installments: installments,
      loyaltyLogs: loyaltyLogs,
      payments: payments,
    );
  }

  /// Builds a WhatsApp chat URI, normalizing Egyptian mobile numbers (`01...` -> `201...`).
  static Uri? buildWhatsAppUri(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return null;
    String intl = digits;
    if (intl.startsWith('+')) {
      intl = intl.substring(1);
    } else if (intl.startsWith('00')) {
      intl = intl.substring(2);
    } else if (intl.startsWith('01') && intl.length == 11) {
      intl = '2$intl';
    }
    if (intl.length < 8) return null;
    return Uri.parse('https://wa.me/$intl');
  }

  /// Builds styled Excel bytes for the given customer list & financial summaries.
  Uint8List buildCustomersExcelBytes(
    List<CustomerEntity> customers,
    Map<String, CustomerFinancialSummary> summaries,
  ) {
    final excel = Excel.createExcel();
    const sheetName = 'سجل_العملاء';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = const [
      'اسم العميل',
      'رقم الهاتف',
      'التصنيف',
      'نسبة الخصم (%)',
      'نقاط الولاء',
      'الحد الائتماني (ج.م)',
      'المديونية الآجلة (ج.م)',
      'عدد الفواتير',
      'إجمالي المشتريات (ج.م)',
      'عقود تقسيط نشطة',
      'متبقي التقسيط (ج.م)',
    ];
    ExcelStyleHelper.appendStyledHeader(sheet, headers);

    for (final c in customers) {
      final sum = summaries[c.id] ?? CustomerFinancialSummary.empty;
      final typeLabel = switch (c.customerType) {
        'wholesale' => 'جملة',
        'vip' => 'VIP',
        _ => 'قطاعي',
      };
      sheet.appendRow([
        TextCellValue(c.name),
        TextCellValue(c.phone),
        TextCellValue(typeLabel),
        IntCellValue(c.discountPercent),
        IntCellValue(c.loyaltyPoints),
        DoubleCellValue(c.creditLimit / 100.0),
        DoubleCellValue(sum.creditDebtPiasters / 100.0),
        IntCellValue(sum.invoiceCount),
        DoubleCellValue(sum.totalSpentPiasters / 100.0),
        IntCellValue(sum.activeInstallmentsCount),
        DoubleCellValue(sum.installmentsRemainingPiasters / 100.0),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      sheet,
      startRow: 1,
      rowCount: customers.length,
      colCount: headers.length,
      currencyCols: {5, 6, 8, 10},
      centerCols: {1, 2, 3, 4, 7, 9},
    );
    if (customers.isNotEmpty) {
      final cEnd = customers.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        sheet,
        rowIndex: customers.length + 1,
        cells: [
          TextCellValue('الإجمالي (${customers.length} عميل)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$cEnd)'),
          TextCellValue(''),
          FormulaCellValue('SUM(G2:G$cEnd)'),
          FormulaCellValue('SUM(H2:H$cEnd)'),
          FormulaCellValue('SUM(I2:I$cEnd)'),
          FormulaCellValue('SUM(J2:J$cEnd)'),
          FormulaCellValue('SUM(K2:K$cEnd)'),
        ],
        currencyCols: {6, 8, 10},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      sheet,
      const [24, 16, 12, 15, 13, 18, 18, 13, 20, 16, 18],
    );

    final encoded = excel.encode();
    if (encoded == null) throw Exception('فشل إنشاء ملف إكسيل العملاء');
    return Uint8List.fromList(encoded);
  }

  Future<String?> exportCustomersExcel(
    List<CustomerEntity> customers,
    Map<String, CustomerFinancialSummary> summaries,
  ) async {
    final bytes = buildCustomersExcelBytes(customers, summaries);
    final nowStr = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final defaultName = 'سجل_العملاء_$nowStr.xlsx';

    String? outputPath;
    bool pickerErrored = false;
    try {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ سجل العملاء (Excel)',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
    } catch (_) {
      pickerErrored = true;
    }

    if (outputPath == null && !pickerErrored) return null;
    if (outputPath == null) {
      final dir = await getApplicationDocumentsDirectory();
      outputPath = '${dir.path}/$defaultName';
    }
    if (!outputPath.toLowerCase().endsWith('.xlsx')) {
      outputPath = '$outputPath.xlsx';
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
    return outputPath;
  }
}

