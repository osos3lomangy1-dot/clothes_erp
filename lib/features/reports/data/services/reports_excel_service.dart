import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/excel_style_helper.dart';

/// Exports a unified, date-range-filtered Excel workbook containing all
/// Reports hub sections:
/// 1. الملخص المالي (Financial Summary)
/// 2. كشف اليوم - الفواتير (Sales in period)
/// 3. كشف اليوم - المرتجعات (Returns in period)
/// 4. كشف اليوم - المصروفات (Expenses in period)
/// 5. كشف اليوم - المشتريات والموردين (Purchases & Supplier Payments in period)
/// 6. كشف اليوم - الورديات (Shifts in period)
/// 7. المخزون والأصناف (Inventory + Sold Qty in period + Low-Stock Highlights)
/// 8. الأقساط والتحصيل (Installments & Payments in period)
/// 9. العروض والخصومات (Promotions & Discounts in period)
class ReportsExcelService {
  final AppDatabase _db;

  ReportsExcelService(this._db);

  Future<String?> exportComprehensiveReports({
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);

    // ─── Load Period-Filtered Data ──────────────────────────────────────────
    final sales = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(start) &
              s.date.isSmallerOrEqualValue(end) &
              s.deletedAt.isNull())
          ..orderBy([(s) => drift.OrderingTerm.desc(s.date)]))
        .get();

    final validSales =
        sales.where((s) => s.status != 'cancelled').toList();
    final validSaleIds = validSales.map((s) => s.id).toList();

    final saleItems = validSaleIds.isEmpty
        ? <SaleItem>[]
        : await (_db.select(_db.saleItems)
              ..where((si) => si.saleId.isIn(validSaleIds)))
            .get();

    final returns = await (_db.select(_db.returns)
          ..where((r) =>
              r.date.isBiggerOrEqualValue(start) &
              r.date.isSmallerOrEqualValue(end) &
              r.deletedAt.isNull())
          ..orderBy([(r) => drift.OrderingTerm.desc(r.date)]))
        .get();

    final allExpenses = await (_db.select(_db.expenses)
          ..where((e) =>
              e.expenseDate.isBiggerOrEqualValue(start) &
              e.expenseDate.isSmallerOrEqualValue(end) &
              e.deletedAt.isNull())
          ..orderBy([(e) => drift.OrderingTerm.desc(e.expenseDate)]))
        .get();
    final operatingExpenses =
        allExpenses.where((e) => e.kind != 'supplier_payment').toList();

    final purchases = await (_db.select(_db.purchases)
          ..where((p) =>
              p.purchaseDate.isBiggerOrEqualValue(start) &
              p.purchaseDate.isSmallerOrEqualValue(end) &
              p.deletedAt.isNull())
          ..orderBy([(p) => drift.OrderingTerm.desc(p.purchaseDate)]))
        .get();

    final supplierPayments = await (_db.select(_db.supplierPayments)
          ..where((sp) =>
              sp.paymentDate.isBiggerOrEqualValue(start) &
              sp.paymentDate.isSmallerOrEqualValue(end))
          ..orderBy([(sp) => drift.OrderingTerm.desc(sp.paymentDate)]))
        .get();

    final shifts = await (_db.select(_db.shifts)
          ..where((sh) =>
              sh.openedAt.isBiggerOrEqualValue(start) &
              sh.openedAt.isSmallerOrEqualValue(end) &
              sh.deletedAt.isNull())
          ..orderBy([(sh) => drift.OrderingTerm.desc(sh.openedAt)]))
        .get();

    final instPayments = await (_db.select(_db.installmentPayments)
          ..where((p) =>
              p.paidAt.isBiggerOrEqualValue(start) &
              p.paidAt.isSmallerOrEqualValue(end) &
              p.deletedAt.isNull())
          ..orderBy([(p) => drift.OrderingTerm.desc(p.paidAt)]))
        .get();

    final promoApps = await (_db.select(_db.promotionApplications)
          ..where((pa) =>
              pa.createdAt.isBiggerOrEqualValue(start) &
              pa.createdAt.isSmallerOrEqualValue(end) &
              pa.deletedAt.isNull()))
        .get();

    // ─── Load Master / Reference Tables ─────────────────────────────────────
    final products = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull()))
        .get();
    final categories = await (_db.select(_db.categories)
          ..where((c) => c.deletedAt.isNull()))
        .get();
    final customers = await (_db.select(_db.customers)
          ..where((c) => c.deletedAt.isNull()))
        .get();
    final suppliers = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull()))
        .get();
    final users = await (_db.select(_db.users)
          ..where((u) => u.deletedAt.isNull()))
        .get();
    final installments = await (_db.select(_db.customerInstallments)
          ..where((i) => i.deletedAt.isNull())
          ..orderBy([(i) => drift.OrderingTerm.desc(i.startDate)]))
        .get();
    final promotions = await (_db.select(_db.promotions)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => drift.OrderingTerm.desc(p.priority)]))
        .get();

    final catMap = {for (final c in categories) c.id: c.name};
    final prodMap = {for (final p in products) p.id: p};
    final custMap = {for (final c in customers) c.id: c};
    final supMap = {for (final s in suppliers) s.id: s};
    final userMap = {for (final u in users) u.id: u.displayName};
    final saleMap = {for (final s in sales) s.id: s};

    // ─── Build Excel Workbook ───────────────────────────────────────────────
    final excel = Excel.createExcel();
    const sSummary = 'الملخص_المالي';
    const sSales = 'كشف_الفواتير';
    const sReturns = 'كشف_المرتجعات';
    const sExpenses = 'كشف_المصروفات';
    const sPurchases = 'كشف_المشتريات_والموردين';
    const sShifts = 'كشف_الورديات';
    const sInventory = 'المخزون_والأصناف';
    const sInstallments = 'الأقساط_والتحصيل';
    const sPromotions = 'العروض_والخصومات';

    final summarySheet = excel[sSummary];
    final salesSheet = excel[sSales];
    final returnsSheet = excel[sReturns];
    final expensesSheet = excel[sExpenses];
    final purchasesSheet = excel[sPurchases];
    final shiftsSheet = excel[sShifts];
    final inventorySheet = excel[sInventory];
    final installmentsSheet = excel[sInstallments];
    final promotionsSheet = excel[sPromotions];

    excel.setDefaultSheet(sSummary);
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // ─── 1. الملخص المالي ───────────────────────────────────────────────────
    final totalSalesPiasters =
        validSales.fold<int>(0, (sum, s) => sum + s.total);
    final totalDiscountPiasters =
        validSales.fold<int>(0, (sum, s) => sum + s.discountAmount);
    final totalCogsPiasters = saleItems.fold<int>(
      0,
      (sum, si) => sum + (si.costSnapshot * si.qty),
    );
    final totalReturnsPiasters =
        returns.fold<int>(0, (sum, r) => sum + r.refundAmount);
    final totalOpExpensesPiasters =
        operatingExpenses.fold<int>(0, (sum, e) => sum + e.amount);
    final grossProfitPiasters =
        totalSalesPiasters - totalReturnsPiasters - totalCogsPiasters;
    final netProfitPiasters = grossProfitPiasters - totalOpExpensesPiasters;
    final totalPurchasesPiasters =
        purchases.fold<int>(0, (sum, p) => sum + p.totalAmount);
    final totalSupPayPiasters =
        supplierPayments.fold<int>(0, (sum, sp) => sum + sp.amount);
    final totalInstCollectedPiasters =
        instPayments.fold<int>(0, (sum, p) => sum + p.amountPiasters);

    ExcelStyleHelper.appendStyledHeader(summarySheet, const [
      'البيان المالي',
      'القيمة (ج.م)',
      'التفاصيل / الملاحظات',
    ]);

    final summaryRows = <(String, CellValue, String)>[
      (
        'فترة التقرير',
        TextCellValue('${_fmtDate(start)}  ←  ${_fmtDate(end)}'),
        'التاريخ المحدد من شاشة التقارير',
      ),
      (
        'إجمالي المبيعات (بدون الملغاة)',
        DoubleCellValue(totalSalesPiasters / 100.0),
        '${validSales.length} فاتورة مكتملة',
      ),
      (
        'إجمالي الخصومات الممنوحة',
        DoubleCellValue(totalDiscountPiasters / 100.0),
        'خصومات الفواتير والعروض',
      ),
      (
        'إجمالي المرتجعات المستردة',
        DoubleCellValue(totalReturnsPiasters / 100.0),
        '${returns.length} عملية مرتجع',
      ),
      (
        'تكلفة البضاعة المباعة (COGS)',
        DoubleCellValue(totalCogsPiasters / 100.0),
        '${saleItems.fold<int>(0, (s, i) => s + i.qty)} قطعة مباعة',
      ),
      (
        'مجمل الربح (Gross Profit)',
        DoubleCellValue(grossProfitPiasters / 100.0),
        'المبيعات - المرتجعات - التكلفة',
      ),
      (
        'المصروفات التشغيلية',
        DoubleCellValue(totalOpExpensesPiasters / 100.0),
        '${operatingExpenses.length} بند مصروف',
      ),
      (
        'صافي الربح التشغيلي (Net Profit)',
        DoubleCellValue(netProfitPiasters / 100.0),
        netProfitPiasters >= 0 ? 'فائض أرباح' : 'عجز / خسارة',
      ),
      (
        'إجمالي فواتير المشتريات',
        DoubleCellValue(totalPurchasesPiasters / 100.0),
        '${purchases.length} فاتورة توريد',
      ),
      (
        'دفعات سداد الموردين',
        DoubleCellValue(totalSupPayPiasters / 100.0),
        '${supplierPayments.length} سند سداد',
      ),
      (
        'تحصيلات الأقساط في الفترة',
        DoubleCellValue(totalInstCollectedPiasters / 100.0),
        '${instPayments.length} دفعة قسط',
      ),
    ];

    for (final row in summaryRows) {
      summarySheet.appendRow([
        TextCellValue(row.$1),
        row.$2,
        TextCellValue(row.$3),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      summarySheet,
      startRow: 1,
      rowCount: summaryRows.length,
      colCount: 3,
      currencyCols: {1},
    );
    // Highlight period row (1), Gross Profit (6), Net Profit (8)
    ExcelStyleHelper.styleRow(
      summarySheet,
      1,
      3,
      ExcelStyleHelper.highlightRowStyle(isCurrency: false),
    );
    ExcelStyleHelper.styleRow(
      summarySheet,
      6,
      3,
      ExcelStyleHelper.highlightRowStyle(isCurrency: true),
    );
    ExcelStyleHelper.styleRow(
      summarySheet,
      8,
      3,
      netProfitPiasters >= 0
          ? ExcelStyleHelper.highlightRowStyle(isCurrency: true)
          : ExcelStyleHelper.dangerRowStyle(isCurrency: true),
    );
    ExcelStyleHelper.setColumnWidths(summarySheet, const [36, 26, 36]);

    // ─── 2. كشف الفواتير ────────────────────────────────────────────────────
    ExcelStyleHelper.appendStyledHeader(salesSheet, const [
      'رقم الفاتورة',
      'التاريخ والوقت',
      'العميل',
      'الكاشير',
      'قبل الخصم (ج.م)',
      'الخصم (ج.م)',
      'الصافي (ج.م)',
      'طريقة الدفع',
      'الحالة',
    ]);
    for (final s in sales) {
      final cust = s.customerId != null ? custMap[s.customerId] : null;
      salesSheet.appendRow([
        TextCellValue(s.shortRef),
        TextCellValue(_fmtDateTime(s.date)),
        TextCellValue(cust?.name ?? 'عميل نقدي'),
        TextCellValue(userMap[s.cashierId] ?? s.cashierId),
        DoubleCellValue(s.subtotal / 100.0),
        DoubleCellValue(s.discountAmount / 100.0),
        DoubleCellValue(s.total / 100.0),
        TextCellValue(_fmtPayment(s.paymentMethod)),
        TextCellValue(s.status == 'cancelled' ? 'ملغاة' : 'مكتملة'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      salesSheet,
      startRow: 1,
      rowCount: sales.length,
      colCount: 9,
      currencyCols: {4, 5, 6},
      centerCols: {0, 1, 7, 8},
    );
    for (var i = 0; i < sales.length; i++) {
      if (sales[i].status == 'cancelled') {
        ExcelStyleHelper.styleRow(
          salesSheet,
          i + 1,
          9,
          ExcelStyleHelper.dangerRowStyle(),
        );
      }
    }
    if (sales.isNotEmpty) {
      final sEnd = sales.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        salesSheet,
        rowIndex: sEnd,
        cells: [
          TextCellValue('الإجمالي (${sales.length} فاتورة)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$sEnd)'),
          FormulaCellValue('SUM(F2:F$sEnd)'),
          FormulaCellValue('SUM(G2:G$sEnd)'),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {4, 5, 6},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      salesSheet,
      const [18, 20, 22, 18, 18, 14, 18, 16, 12],
    );

    // ─── 3. كشف المرتجعات ───────────────────────────────────────────────────
    ExcelStyleHelper.appendStyledHeader(returnsSheet, const [
      'رقم المرتجع',
      'رقم الفاتورة الأصلية',
      'التاريخ والوقت',
      'السبب',
      'المبلغ المسترد (ج.م)',
      'طريقة الاسترداد',
      'الكاشير',
    ]);
    for (final r in returns) {
      final sale = r.saleId != null ? saleMap[r.saleId] : null;
      returnsSheet.appendRow([
        TextCellValue(r.id.length >= 8 ? r.id.substring(0, 8) : r.id),
        TextCellValue(sale?.shortRef ?? r.saleId ?? '-'),
        TextCellValue(_fmtDateTime(r.date)),
        TextCellValue(r.reason),
        DoubleCellValue(r.refundAmount / 100.0),
        TextCellValue(_fmtPayment(r.paymentMethod)),
        TextCellValue(userMap[r.cashierId] ?? r.cashierId),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      returnsSheet,
      startRow: 1,
      rowCount: returns.length,
      colCount: 7,
      currencyCols: {4},
      centerCols: {0, 1, 2, 5},
    );
    if (returns.isNotEmpty) {
      final rEnd = returns.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        returnsSheet,
        rowIndex: rEnd,
        cells: [
          TextCellValue('الإجمالي (${returns.length} مرتجع)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$rEnd)'),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {4},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      returnsSheet,
      const [16, 18, 20, 26, 18, 16, 18],
    );

    // ─── 4. كشف المصروفات ───────────────────────────────────────────────────
    ExcelStyleHelper.appendStyledHeader(expensesSheet, const [
      'التاريخ',
      'البند',
      'المبلغ (ج.م)',
      'الملاحظات',
      'المسجل',
    ]);
    for (final e in operatingExpenses) {
      expensesSheet.appendRow([
        TextCellValue(_fmtDate(e.expenseDate)),
        TextCellValue(e.category),
        DoubleCellValue(e.amount / 100.0),
        TextCellValue(e.note ?? ''),
        TextCellValue(userMap[e.userId] ?? e.userId),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      expensesSheet,
      startRow: 1,
      rowCount: operatingExpenses.length,
      colCount: 5,
      currencyCols: {2},
      centerCols: {0},
    );
    if (operatingExpenses.isNotEmpty) {
      final eEnd = operatingExpenses.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        expensesSheet,
        rowIndex: eEnd,
        cells: [
          TextCellValue('الإجمالي (${operatingExpenses.length} بند)'),
          TextCellValue(''),
          FormulaCellValue('SUM(C2:C$eEnd)'),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {2},
      );
    }
    ExcelStyleHelper.setColumnWidths(expensesSheet, const [16, 24, 18, 30, 18]);

    // ─── 5. كشف المشتريات والموردين ─────────────────────────────────────────
    ExcelStyleHelper.appendStyledHeader(purchasesSheet, const [
      'النوع',
      'المرجع / الفاتورة',
      'التاريخ',
      'المورد',
      'الإجمالي (ج.م)',
      'المدفوع (ج.م)',
      'المتبقي (ج.م)',
      'ملاحظات',
    ]);
    int purRowCount = 0;
    for (final p in purchases) {
      final rem = p.totalAmount - p.paidAmount;
      purchasesSheet.appendRow([
        TextCellValue('فاتورة شراء'),
        TextCellValue(p.invoiceNumber ?? p.id),
        TextCellValue(_fmtDate(p.purchaseDate)),
        TextCellValue(supMap[p.supplierId]?.name ?? p.supplierId),
        DoubleCellValue(p.totalAmount / 100.0),
        DoubleCellValue(p.paidAmount / 100.0),
        DoubleCellValue((rem > 0 ? rem : 0) / 100.0),
        TextCellValue(p.notes ?? ''),
      ]);
      purRowCount++;
    }
    for (final sp in supplierPayments) {
      purchasesSheet.appendRow([
        TextCellValue('سداد مورد'),
        TextCellValue(sp.referenceNumber ?? sp.id),
        TextCellValue(_fmtDateTime(sp.paymentDate)),
        TextCellValue(supMap[sp.supplierId]?.name ?? sp.supplierId),
        DoubleCellValue(0.0),
        DoubleCellValue(sp.amount / 100.0),
        DoubleCellValue(0.0),
        TextCellValue(sp.notes ?? ''),
      ]);
      purRowCount++;
    }
    ExcelStyleHelper.styleDataRows(
      purchasesSheet,
      startRow: 1,
      rowCount: purRowCount,
      colCount: 8,
      currencyCols: {4, 5, 6},
      centerCols: {0, 1, 2},
    );
    if (purRowCount > 0) {
      final purEnd = purRowCount + 1;
      ExcelStyleHelper.appendTotalsRow(
        purchasesSheet,
        rowIndex: purEnd,
        cells: [
          TextCellValue('الإجمالي ($purRowCount حركة)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$purEnd)'),
          FormulaCellValue('SUM(F2:F$purEnd)'),
          FormulaCellValue('SUM(G2:G$purEnd)'),
          TextCellValue(''),
        ],
        currencyCols: {4, 5, 6},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      purchasesSheet,
      const [16, 18, 20, 22, 16, 16, 16, 26],
    );

    // ─── 6. كشف الورديات ────────────────────────────────────────────────────
    ExcelStyleHelper.appendStyledHeader(shiftsSheet, const [
      'رقم الوردية',
      'الكاشير',
      'وقت الفتح',
      'وقت الإغلاق',
      'الافتتاحي (ج.م)',
      'المتوقع (ج.م)',
      'الفعلي (ج.م)',
      'الفرق (ج.م)',
      'الحالة',
    ]);
    for (final sh in shifts) {
      shiftsSheet.appendRow([
        TextCellValue(sh.id.length >= 8 ? sh.id.substring(0, 8) : sh.id),
        TextCellValue(userMap[sh.cashierId] ?? sh.cashierId),
        TextCellValue(_fmtDateTime(sh.openedAt)),
        TextCellValue(sh.closedAt != null ? _fmtDateTime(sh.closedAt!) : '-'),
        DoubleCellValue(sh.openingBalance / 100.0),
        DoubleCellValue((sh.expectedBalance ?? 0) / 100.0),
        DoubleCellValue((sh.countedBalance ?? 0) / 100.0),
        DoubleCellValue((sh.difference ?? 0) / 100.0),
        TextCellValue(sh.closedAt == null ? 'مفتوحة' : 'مغلقة'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      shiftsSheet,
      startRow: 1,
      rowCount: shifts.length,
      colCount: 9,
      currencyCols: {4, 5, 6, 7},
      centerCols: {0, 2, 3, 8},
    );
    if (shifts.isNotEmpty) {
      final shEnd = shifts.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        shiftsSheet,
        rowIndex: shEnd,
        cells: [
          TextCellValue('الإجمالي (${shifts.length} وردية)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$shEnd)'),
          FormulaCellValue('SUM(F2:F$shEnd)'),
          FormulaCellValue('SUM(G2:G$shEnd)'),
          FormulaCellValue('SUM(H2:H$shEnd)'),
          TextCellValue(''),
        ],
        currencyCols: {4, 5, 6, 7},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      shiftsSheet,
      const [14, 20, 20, 20, 16, 16, 16, 16, 12],
    );

    // ─── 7. المخزون والأصناف ────────────────────────────────────────────────
    final soldQtyByVariant = <String, int>{};
    for (final si in saleItems) {
      soldQtyByVariant[si.variantId] =
          (soldQtyByVariant[si.variantId] ?? 0) + si.qty;
    }
    ExcelStyleHelper.appendStyledHeader(inventorySheet, const [
      'اسم المنتج',
      'التصنيف',
      'SKU',
      'المقاس',
      'اللون',
      'المباع في الفترة',
      'الرصيد الحالي',
      'حد الطلب',
      'التكلفة (ج.م)',
      'البيع (ج.م)',
      'قيمة المخزون بالتكلفة (ج.م)',
      'قيمة المخزون بالبيع (ج.م)',
    ]);
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final prod = prodMap[v.productId];
      final rowNum = i + 2;
      inventorySheet.appendRow([
        TextCellValue(prod?.name ?? v.productId),
        TextCellValue(
          prod != null ? (catMap[prod.categoryId] ?? 'عام') : 'عام',
        ),
        TextCellValue(v.sku),
        TextCellValue(v.size),
        TextCellValue(v.color),
        IntCellValue(soldQtyByVariant[v.id] ?? 0),
        IntCellValue(v.quantity),
        IntCellValue(prod?.minStock ?? 5),
        DoubleCellValue(v.costPrice / 100.0),
        DoubleCellValue(v.sellPrice / 100.0),
        FormulaCellValue('G$rowNum*I$rowNum'),
        FormulaCellValue('G$rowNum*J$rowNum'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      inventorySheet,
      startRow: 1,
      rowCount: variants.length,
      colCount: 12,
      currencyCols: {8, 9, 10, 11},
      centerCols: {2, 3, 4, 5, 6, 7},
    );
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final minS = prodMap[v.productId]?.minStock ?? 5;
      if (v.quantity <= 0) {
        ExcelStyleHelper.styleRow(
          inventorySheet,
          i + 1,
          12,
          ExcelStyleHelper.dangerRowStyle(),
        );
      } else if (v.quantity <= minS) {
        ExcelStyleHelper.styleRow(
          inventorySheet,
          i + 1,
          12,
          ExcelStyleHelper.warningRowStyle(),
        );
      }
    }
    if (variants.isNotEmpty) {
      final invEnd = variants.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        inventorySheet,
        rowIndex: invEnd,
        cells: [
          TextCellValue('الإجمالي (${variants.length} صنف)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(F2:F$invEnd)'),
          FormulaCellValue('SUM(G2:G$invEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(K2:K$invEnd)'),
          FormulaCellValue('SUM(L2:L$invEnd)'),
        ],
        currencyCols: {10, 11},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      inventorySheet,
      const [26, 18, 18, 12, 14, 16, 14, 12, 14, 14, 22, 22],
    );

    // ─── 8. الأقساط والتحصيل ────────────────────────────────────────────────
    final paidInPeriodByInst = <String, int>{};
    for (final p in instPayments) {
      paidInPeriodByInst[p.customerInstallmentId] =
          (paidInPeriodByInst[p.customerInstallmentId] ?? 0) +
              p.amountPiasters;
    }
    ExcelStyleHelper.appendStyledHeader(installmentsSheet, const [
      'رقم العقد',
      'العميل',
      'الهاتف',
      'إجمالي العقد (ج.م)',
      'المقدم (ج.م)',
      'المحصل في الفترة (ج.م)',
      'المتبقي الحالي (ج.م)',
      'تاريخ البداية',
      'تاريخ النهاية',
      'الحالة',
    ]);
    for (final inst in installments) {
      final cust = custMap[inst.customerId];
      installmentsSheet.appendRow([
        TextCellValue(inst.id.length >= 8 ? inst.id.substring(0, 8) : inst.id),
        TextCellValue(cust?.name ?? inst.customerId),
        TextCellValue(cust?.phone ?? ''),
        DoubleCellValue(inst.totalPiasters / 100.0),
        DoubleCellValue(inst.downPaymentPiasters / 100.0),
        DoubleCellValue((paidInPeriodByInst[inst.id] ?? 0) / 100.0),
        DoubleCellValue(inst.remainingPiasters / 100.0),
        TextCellValue(_fmtDate(inst.startDate)),
        TextCellValue(_fmtDate(inst.endDate)),
        TextCellValue(_fmtInstStatus(inst.status)),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      installmentsSheet,
      startRow: 1,
      rowCount: installments.length,
      colCount: 10,
      currencyCols: {3, 4, 5, 6},
      centerCols: {0, 2, 7, 8, 9},
    );
    for (var i = 0; i < installments.length; i++) {
      if (installments[i].status == 'overdue') {
        ExcelStyleHelper.styleRow(
          installmentsSheet,
          i + 1,
          10,
          ExcelStyleHelper.dangerRowStyle(),
        );
      }
    }
    if (installments.isNotEmpty) {
      final insEnd = installments.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        installmentsSheet,
        rowIndex: insEnd,
        cells: [
          TextCellValue('الإجمالي (${installments.length} عقد)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(D2:D$insEnd)'),
          FormulaCellValue('SUM(E2:E$insEnd)'),
          FormulaCellValue('SUM(F2:F$insEnd)'),
          FormulaCellValue('SUM(G2:G$insEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {3, 4, 5, 6},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      installmentsSheet,
      const [16, 22, 16, 18, 16, 20, 18, 14, 14, 14],
    );

    // ─── 9. العروض والخصومات ────────────────────────────────────────────────
    final promoCount = <String, int>{};
    final promoDiscount = <String, int>{};
    for (final pa in promoApps) {
      promoCount[pa.promotionId] = (promoCount[pa.promotionId] ?? 0) + 1;
      promoDiscount[pa.promotionId] =
          (promoDiscount[pa.promotionId] ?? 0) + pa.discountPiasters;
    }
    ExcelStyleHelper.appendStyledHeader(promotionsSheet, const [
      'اسم العرض',
      'النوع',
      'قيمة الخصم',
      'تاريخ البداية',
      'تاريخ النهاية',
      'مرات التطبيق في الفترة',
      'إجمالي الخصم الممنوح (ج.م)',
      'الحالة',
    ]);
    for (final pr in promotions) {
      final bp = pr.valueBp ?? 0;
      final piasters = pr.valuePiasters ?? 0;
      final valLabel = bp > 0
          ? '${(bp / 100).toStringAsFixed(0)}%'
          : '${(piasters / 100).toStringAsFixed(2)} ج.م';
      promotionsSheet.appendRow([
        TextCellValue(pr.name),
        TextCellValue(pr.type),
        TextCellValue(valLabel),
        TextCellValue(_fmtDate(pr.startsAt)),
        TextCellValue(_fmtDate(pr.endsAt)),
        IntCellValue(promoCount[pr.id] ?? 0),
        DoubleCellValue((promoDiscount[pr.id] ?? 0) / 100.0),
        TextCellValue(pr.isActive ? 'نشط' : 'متوقف'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      promotionsSheet,
      startRow: 1,
      rowCount: promotions.length,
      colCount: 8,
      currencyCols: {6},
      centerCols: {1, 2, 3, 4, 5, 7},
    );
    if (promotions.isNotEmpty) {
      final prEnd = promotions.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        promotionsSheet,
        rowIndex: prEnd,
        cells: [
          TextCellValue('الإجمالي (${promotions.length} عرض)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(F2:F$prEnd)'),
          FormulaCellValue('SUM(G2:G$prEnd)'),
          TextCellValue(''),
        ],
        currencyCols: {6},
      );
    }
    ExcelStyleHelper.setColumnWidths(
      promotionsSheet,
      const [26, 18, 16, 14, 14, 20, 22, 12],
    );

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('فشل إنشاء ملف إكسيل التقارير الشامل');
    }

    final defaultName =
        'تقارير_النظام_${_fmtDate(start)}_إلى_${_fmtDate(end)}.xlsx';
    return _saveFile(bytes, defaultName);
  }

  Future<String?> _saveFile(List<int> bytes, String defaultFileName) async {
    String? outputFile;
    try {
      outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ ملف إكسيل التقارير الشامل',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
    } catch (_) {}

    if (outputFile == null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        outputFile = '${dir.path}/$defaultFileName';
      } catch (_) {
        outputFile = '${Directory.current.path}/$defaultFileName';
      }
    }
    if (!outputFile.endsWith('.xlsx')) {
      outputFile = '$outputFile.xlsx';
    }
    final file = File(outputFile);
    await file.writeAsBytes(bytes);
    return outputFile;
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtPayment(String method) {
    return switch (method.toLowerCase().trim()) {
      'cash' => 'نقدي',
      'card' || 'visa' => 'بطاقة / فيزا',
      'installment' => 'تقسيط',
      'credit' => 'آجل',
      'mixed' || 'split' => 'مختلط',
      _ => method,
    };
  }

  String _fmtInstStatus(String status) {
    return switch (status) {
      'active' => 'نشط',
      'completed' => 'مكتمل',
      'overdue' => 'متأخر',
      'cancelled' => 'ملغي',
      _ => status,
    };
  }
}
