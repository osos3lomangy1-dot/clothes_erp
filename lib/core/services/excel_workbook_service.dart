import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/installments/domain/services/installment_calculator.dart';
import '../../features/partners/domain/entities/partner_entity.dart';
import '../../features/products/domain/entities/activity_type.dart';
import '../../features/settings/data/services/activity_settings_service.dart';
import '../constants/retail_sector.dart';
import '../database/app_database.dart';
import '../database/branch_provider.dart';
import '../database/tx_writer.dart';
import '../di/injection.dart';
import 'excel_style_helper.dart';
import 'excel_workbook_models.dart';

/// Full Linked Excel Workbook Exporter + Shop Migration & Smart Column Mapper.
///
/// Designed to be completely standalone and testable with an in-memory [AppDatabase]
/// while leaving all legacy [ExcelService] methods untouched.
class ExcelWorkbookService {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _txWriter;
  final ActivitySettingsService? _activitySettingsService;
  final _uuid = const Uuid();

  // Canonical Arabic sheet names used across Full Export & Migration Template
  static const sheetDashboard = 'الملخص_التنفيذي';
  static const sheetProducts = 'المنتجات_والمخزون';
  static const sheetCustomers = 'العملاء';
  static const sheetSuppliers = 'الموردين';
  static const sheetPartners = 'الشركاء';
  static const sheetSales = 'الفواتير';
  static const sheetSaleItems = 'تفاصيل_الفواتير';
  static const sheetInstallments = 'عقود_التقسيط';
  static const sheetInstallmentPayments = 'دفعات_التقسيط';
  static const sheetExpenses = 'المصروفات';
  static const sheetPurchases = 'المشتريات';
  static const sheetReturns = 'المرتجعات';
  static const sheetLowStock = 'نواقص_المخزون';
  static const sheetShifts = 'الورديات_والدرج';
  static const sheetWallets = 'المحافظ_الإلكترونية';
  static const sheetInventoryLogs = 'حركات_المخزن';
  static const sheetPartyPayments = 'تحصيلات_العملاء_والموردين';
  static const sheetCashMovements = 'حركات_الدرج';
  static const sheetStagnant = 'الأصناف_الراكدة';
  static const sheetInstructions = 'التعليمات';

  ExcelWorkbookService(
    this._db,
    this._branchProvider,
    this._txWriter, {
    ActivitySettingsService? activitySettingsService,
  }) : _activitySettingsService = activitySettingsService;

  Future<String> _resolveDefaultActivityType(String? override) async {
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    final svc =
        _activitySettingsService ??
        (getIt.isRegistered<ActivitySettingsService>()
            ? getIt<ActivitySettingsService>()
            : null);
    if (svc != null) {
      try {
        final enabled = await svc.getEnabledActivities();
        if (enabled.isNotEmpty && enabled.length < ActivityType.values.length) {
          return enabled.first.code;
        }
      } catch (_) {}
    }

    final metaRows = await _db.select(_db.appMeta).get();
    final enabledFromMeta = <String>[];
    String? sectorMode;
    for (final r in metaRows) {
      if (r.key.startsWith('activity.') && r.value == '1') {
        enabledFromMeta.add(r.key.replaceFirst('activity.', ''));
      } else if (r.key == RetailSector.metaKey) {
        sectorMode = r.value;
      }
    }
    if (enabledFromMeta.isNotEmpty &&
        enabledFromMeta.length < ActivityType.values.length) {
      return enabledFromMeta.first;
    }
    switch (sectorMode) {
      case RetailSector.houseware:
        return ActivityType.homeLiving.code;
      case RetailSector.supermarket:
        return ActivityType.supermarketGroceries.code;
      case RetailSector.hospitality:
        return ActivityType.restaurantsCafes.code;
      default:
        return ActivityType.clothing.code;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. FIELD SPECIFICATIONS FOR SMART COLUMN MAPPER
  // ═══════════════════════════════════════════════════════════════════════════

  static List<ExcelFieldSpec> fieldSpecsFor(ExcelImportEntity entity) {
    switch (entity) {
      case ExcelImportEntity.products:
        return const [
          ExcelFieldSpec(
            key: 'productName',
            arabicLabel: 'اسم المنتج',
            required: true,
            hint: 'مثال: تيشيرت قطن بولو',
          ),
          ExcelFieldSpec(
            key: 'categoryName',
            arabicLabel: 'التصنيف / القسم',
            hint: 'مثال: تيشيرتات (الافتراضي: عام)',
          ),
          ExcelFieldSpec(
            key: 'sku',
            arabicLabel: 'الكود / الباركود (SKU)',
            hint: 'يُولَّد تلقائياً إن تُرك فارغاً',
          ),
          ExcelFieldSpec(
            key: 'size',
            arabicLabel: 'المقاس',
            hint: 'الافتراضي: قياسي',
          ),
          ExcelFieldSpec(
            key: 'color',
            arabicLabel: 'اللون',
            hint: 'الافتراضي: افتراضي',
          ),
          ExcelFieldSpec(key: 'costPrice', arabicLabel: 'سعر التكلفة (ج.م)'),
          ExcelFieldSpec(
            key: 'sellPrice',
            arabicLabel: 'سعر البيع القطاعي (ج.م)',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'wholesalePrice',
            arabicLabel: 'سعر الجملة (ج.م)',
          ),
          ExcelFieldSpec(
            key: 'quantity',
            arabicLabel: 'الكمية / الرصيد الحالي',
          ),
          ExcelFieldSpec(key: 'minStock', arabicLabel: 'حد الطلب للتنبيه'),
        ];
      case ExcelImportEntity.customers:
        return const [
          ExcelFieldSpec(
            key: 'name',
            arabicLabel: 'اسم العميل',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'phone',
            arabicLabel: 'رقم الهاتف',
            required: true,
            hint: 'مفتاح الربط الفريد للعميل',
          ),
          ExcelFieldSpec(
            key: 'customerType',
            arabicLabel: 'نوع العميل (قطاعي / جملة)',
          ),
          ExcelFieldSpec(key: 'discountPercent', arabicLabel: 'نسبة الخصم (%)'),
          ExcelFieldSpec(key: 'loyaltyPoints', arabicLabel: 'نقاط الولاء'),
        ];
      case ExcelImportEntity.suppliers:
        return const [
          ExcelFieldSpec(
            key: 'name',
            arabicLabel: 'اسم المورد',
            required: true,
          ),
          ExcelFieldSpec(key: 'phone', arabicLabel: 'رقم الهاتف'),
          ExcelFieldSpec(
            key: 'companyName',
            arabicLabel: 'اسم الشركة / المصنع',
          ),
          ExcelFieldSpec(key: 'address', arabicLabel: 'العنوان'),
          ExcelFieldSpec(
            key: 'balance',
            arabicLabel: 'الرصيد المستحق للمورد (ج.م)',
          ),
        ];
      case ExcelImportEntity.installments:
        return const [
          ExcelFieldSpec(
            key: 'customerPhone',
            arabicLabel: 'هاتف العميل',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'customerName',
            arabicLabel: 'اسم العميل',
            hint: 'يُستخدم لإنشاء العميل تلقائياً إن لم يكن مسجلاً',
          ),
          ExcelFieldSpec(
            key: 'total',
            arabicLabel: 'إجمالي العقد / الفاتورة (ج.م)',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'downPayment',
            arabicLabel: 'المقدم المدفوع (ج.م)',
          ),
          ExcelFieldSpec(
            key: 'interestPercent',
            arabicLabel: 'نسبة الفائدة (%)',
          ),
          ExcelFieldSpec(
            key: 'durationMonths',
            arabicLabel: 'عدد الشهور',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'remaining',
            arabicLabel: 'المتبقي الحالي (ج.م)',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'startDate',
            arabicLabel: 'تاريخ بداية العقد (YYYY-MM-DD)',
          ),
          ExcelFieldSpec(
            key: 'status',
            arabicLabel: 'حالة العقد (نشط / متأخر / مكتمل)',
          ),
        ];
      case ExcelImportEntity.expenses:
        return const [
          ExcelFieldSpec(
            key: 'category',
            arabicLabel: 'بند المصروف',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'amount',
            arabicLabel: 'المبلغ (ج.م)',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'expenseDate',
            arabicLabel: 'تاريخ المصروف (YYYY-MM-DD)',
          ),
          ExcelFieldSpec(key: 'notes', arabicLabel: 'ملاحظات'),
        ];
      case ExcelImportEntity.historicalSales:
        return const [
          ExcelFieldSpec(
            key: 'shortRef',
            arabicLabel: 'رقم الفاتورة (اختياري)',
          ),
          ExcelFieldSpec(
            key: 'total',
            arabicLabel: 'إجمالي الفاتورة (ج.م)',
            required: true,
          ),
          ExcelFieldSpec(
            key: 'paymentMethod',
            arabicLabel: 'طريقة الدفع (cash / card)',
          ),
          ExcelFieldSpec(
            key: 'date',
            arabicLabel: 'تاريخ الفاتورة (YYYY-MM-DD)',
          ),
          ExcelFieldSpec(
            key: 'customerName',
            arabicLabel: 'اسم العميل (اختياري)',
          ),
        ];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. FULL LINKED WORKBOOK EXPORT (12 RELATIONAL SHEETS WITH LIVE FORMULAS)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Builds the complete multi-sheet Excel workbook bytes with live formulas.
  Future<({Uint8List bytes, ExcelFullExportResult meta})>
  buildFullWorkbookBytes() async {
    final products = await (_db.select(
      _db.products,
    )..where((p) => p.deletedAt.isNull())).get();
    final variants = await (_db.select(
      _db.productVariants,
    )..where((v) => v.deletedAt.isNull())).get();
    final categories = await (_db.select(
      _db.categories,
    )..where((c) => c.deletedAt.isNull())).get();
    final customers = await (_db.select(
      _db.customers,
    )..where((c) => c.deletedAt.isNull())).get();
    final suppliers = await (_db.select(
      _db.suppliers,
    )..where((s) => s.deletedAt.isNull())).get();
    final users = await (_db.select(
      _db.users,
    )..where((u) => u.deletedAt.isNull())).get();
    final sales =
        await (_db.select(_db.sales)
              ..where((s) => s.deletedAt.isNull())
              ..orderBy([(s) => drift.OrderingTerm.desc(s.date)]))
            .get();
    final saleItems = await _db.select(_db.saleItems).get();
    final installments =
        await (_db.select(_db.customerInstallments)
              ..where((c) => c.deletedAt.isNull())
              ..orderBy([(c) => drift.OrderingTerm.desc(c.startDate)]))
            .get();
    final installmentPayments =
        await (_db.select(_db.installmentPayments)
              ..where((p) => p.deletedAt.isNull())
              ..orderBy([(p) => drift.OrderingTerm.desc(p.paidAt)]))
            .get();
    final expenses =
        await (_db.select(_db.expenses)
              ..where((e) => e.deletedAt.isNull())
              ..orderBy([(e) => drift.OrderingTerm.desc(e.expenseDate)]))
            .get();
    final purchases =
        await (_db.select(_db.purchases)
              ..where((p) => p.deletedAt.isNull())
              ..orderBy([(p) => drift.OrderingTerm.desc(p.purchaseDate)]))
            .get();
    final returns =
        await (_db.select(_db.returns)
              ..where((r) => r.deletedAt.isNull())
              ..orderBy([(r) => drift.OrderingTerm.desc(r.date)]))
            .get();
    final shifts =
        await (_db.select(_db.shifts)
              ..where((s) => s.deletedAt.isNull())
              ..orderBy([(s) => drift.OrderingTerm.desc(s.openedAt)]))
            .get();
    final wallets = await (_db.select(
      _db.cashWallets,
    )..where((w) => w.deletedAt.isNull())).get();
    final inventoryLogs =
        await (_db.select(_db.inventoryLogs)
              ..orderBy([(l) => drift.OrderingTerm.desc(l.createdAt)])
              ..limit(2000))
            .get();
    final customerPayments =
        await (_db.select(_db.customerPayments)
              ..where((p) => p.deletedAt.isNull())
              ..orderBy([(p) => drift.OrderingTerm.desc(p.paymentDate)]))
            .get();
    final supplierPayments =
        await (_db.select(_db.supplierPayments)
              ..orderBy([(p) => drift.OrderingTerm.desc(p.paymentDate)]))
            .get();
    final cashMovements =
        await (_db.select(_db.cashMovements)
              ..where((m) => m.deletedAt.isNull())
              ..orderBy([(m) => drift.OrderingTerm.desc(m.createdAt)])
              ..limit(2000))
            .get();
    final partners = await _loadPartners();

    final catMap = {for (final c in categories) c.id: c.name};
    final prodMap = {for (final p in products) p.id: p};
    final variantMap = {for (final v in variants) v.id: v};
    final custMap = {for (final c in customers) c.id: c};
    final supMap = {for (final s in suppliers) s.id: s};
    final userMap = {for (final u in users) u.id: u.displayName};
    final saleMap = {for (final s in sales) s.id: s};
    final instMap = {for (final i in installments) i.id: i};

    // Only keep sale items belonging to non-deleted sales
    final validSaleItems = saleItems
        .where((i) => saleMap.containsKey(i.saleId))
        .toList();

    final excel = Excel.createExcel();
    final headerStyle = _headerStyle();
    final accentHeaderStyle = _accentHeaderStyle();
    final highlightStyle = _highlightRowStyle();

    // Create all sheets in clean logical order
    final dashSheet = excel[sheetDashboard];
    final prodSheet = excel[sheetProducts];
    final custSheet = excel[sheetCustomers];
    final supSheet = excel[sheetSuppliers];
    final partnerSheet = excel[sheetPartners];
    final salesSheet = excel[sheetSales];
    final itemsSheet = excel[sheetSaleItems];
    final instSheet = excel[sheetInstallments];
    final paySheet = excel[sheetInstallmentPayments];
    final expSheet = excel[sheetExpenses];
    final purSheet = excel[sheetPurchases];
    final retSheet = excel[sheetReturns];
    final lowStockSheet = excel[sheetLowStock];
    final shiftsSheet = excel[sheetShifts];
    final walletsSheet = excel[sheetWallets];
    final invLogsSheet = excel[sheetInventoryLogs];
    final partyPaySheet = excel[sheetPartyPayments];
    final cashMovSheet = excel[sheetCashMovements];
    final stagnantSheet = excel[sheetStagnant];

    excel.setDefaultSheet(sheetDashboard);
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Row end indices (header = row 1, data starts at row 2)
    final pEnd = variants.length + 1;
    final cEnd = customers.length + 1;
    final supEnd = suppliers.length + 1;
    final sEnd = sales.length + 1;
    final siEnd = validSaleItems.length + 1;
    final insEnd = installments.length + 1;
    final payEnd = installmentPayments.length + 1;
    final expEnd = expenses.length + 1;
    final purEnd = purchases.length + 1;
    final retEnd = returns.length + 1;

    // ─── Sheet 1: الملخص_التنفيذي (Live Linked Dashboard) ───────────────────
    _appendStyledHeader(dashSheet, const [
      'المؤشر المالي / التشغيلي',
      'القيمة (مربوطة بالمعادلات)',
      'الوحدة / البيان',
    ], accentHeaderStyle);

    final dashRows = <(String, CellValue, String)>[
      (
        'إجمالي المبيعات (الفواتير المكتملة)',
        sales.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetSales'!J2:J$sEnd,\"مكتملة\",'$sheetSales'!H2:H$sEnd)",
              ),
        'ج.م — مربوط بشيت الفواتير',
      ),
      (
        'إجمالي تكلفة البضاعة المباعة (COGS)',
        validSaleItems.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue("SUM('$sheetSaleItems'!L2:L$siEnd)"),
        'ج.م — مربوط بشيت تفاصيل الفواتير',
      ),
      (
        'مجمل ربح المبيعات',
        FormulaCellValue('B2-B3'),
        'ج.م — المبيعات ناقص التكلفة',
      ),
      (
        'إجمالي المصروفات التشغيلية',
        expenses.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetExpenses'!C2:C$expEnd,\"مصروف تشغيلي\",'$sheetExpenses'!D2:D$expEnd)",
              ),
        'ج.م — مربوط بشيت المصروفات',
      ),
      (
        'صافي الربح التشغيلي',
        FormulaCellValue('B4-B5'),
        'ج.م — مجمل الربح ناقص المصروفات',
      ),
      (
        'قيمة المخزون الحالي (بالتكلفة)',
        variants.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue("SUM('$sheetProducts'!K2:K$pEnd)"),
        'ج.م — مربوط بشيت المنتجات والمخزون',
      ),
      (
        'قيمة المخزون الحالي (بسعر البيع)',
        variants.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue("SUM('$sheetProducts'!L2:L$pEnd)"),
        'ج.م — مربوط بشيت المنتجات والمخزون',
      ),
      (
        'إجمالي رصيد التقسيط المتبقي على العملاء',
        installments.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetInstallments'!O2:O$insEnd,\"نشط\",'$sheetInstallments'!L2:L$insEnd)+SUMIF('$sheetInstallments'!O2:O$insEnd,\"متأخر\",'$sheetInstallments'!L2:L$insEnd)",
              ),
        'ج.م — مربوط بشيت عقود التقسيط',
      ),
      (
        'إجمالي أرصدة الموردين المستحقة',
        suppliers.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue("SUM('$sheetSuppliers'!E2:E$supEnd)"),
        'ج.م — مربوط بشيت الموردين',
      ),
      (
        'إجمالي المرتجعات',
        returns.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue("SUM('$sheetReturns'!E2:E$retEnd)"),
        'ج.م — مربوط بشيت المرتجعات',
      ),
      (
        'إجمالي فواتير المشتريات',
        purchases.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue("SUM('$sheetPurchases'!E2:E$purEnd)"),
        'ج.م — مربوط بشيت المشتريات',
      ),
      (
        'عدد الأصناف المسجلة (SKUs)',
        variants.isEmpty
            ? IntCellValue(0)
            : FormulaCellValue("COUNTA('$sheetProducts'!C2:C$pEnd)"),
        'صنف',
      ),
      (
        'عدد العملاء المسجلين',
        customers.isEmpty
            ? IntCellValue(0)
            : FormulaCellValue("COUNTA('$sheetCustomers'!A2:A$cEnd)"),
        'عميل',
      ),
      (
        'إجمالي عدد الفواتير',
        sales.isEmpty
            ? IntCellValue(0)
            : FormulaCellValue("COUNTA('$sheetSales'!A2:A$sEnd)"),
        'فاتورة',
      ),
    ];

    for (var i = 0; i < dashRows.length; i++) {
      final r = dashRows[i];
      dashSheet.appendRow([TextCellValue(r.$1), r.$2, TextCellValue(r.$3)]);
    }
    ExcelStyleHelper.styleDataRows(
      dashSheet,
      startRow: 1,
      rowCount: dashRows.length,
      colCount: 3,
      currencyCols: {1},
    );
    for (var i = 0; i < dashRows.length; i++) {
      // Highlight key profit rows (row index 3 = Gross Profit, 5 = Net Profit)
      if (i == 2 || i == 4) {
        _styleRow(dashSheet, i + 1, 3, highlightStyle);
      }
    }
    _setColumnWidths(dashSheet, const [38, 24, 34]);

    // ─── Sheet 2: المنتجات_والمخزون ──────────────────────────────────────────
    _appendStyledHeader(prodSheet, const [
      'اسم المنتج',
      'التصنيف',
      'كود الصنف (SKU)',
      'المقاس',
      'اللون',
      'سعر التكلفة (ج.م)',
      'سعر البيع (ج.م)',
      'سعر الجملة (ج.م)',
      'الكمية',
      'حد الطلب',
      'قيمة المخزون بالتكلفة (ج.م)',
      'قيمة المخزون بالبيع (ج.م)',
    ], headerStyle);
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final prod = prodMap[v.productId];
      final rowNum = i + 2;
      prodSheet.appendRow([
        TextCellValue(prod?.name ?? v.productId),
        TextCellValue(
          prod != null ? (catMap[prod.categoryId] ?? 'عام') : 'عام',
        ),
        TextCellValue(v.sku),
        TextCellValue(v.size),
        TextCellValue(v.color),
        DoubleCellValue(v.costPrice / 100.0),
        DoubleCellValue(v.sellPrice / 100.0),
        DoubleCellValue(v.wholesalePrice / 100.0),
        IntCellValue(v.quantity),
        IntCellValue(prod?.minStock ?? 5),
        FormulaCellValue('F$rowNum*I$rowNum'),
        FormulaCellValue('G$rowNum*I$rowNum'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      prodSheet,
      startRow: 1,
      rowCount: variants.length,
      colCount: 12,
      currencyCols: {5, 6, 7, 10, 11},
      centerCols: {2, 3, 4, 8, 9},
    );
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final minS = prodMap[v.productId]?.minStock ?? 5;
      if (v.quantity <= 0) {
        _styleRow(
          prodSheet,
          i + 1,
          12,
          ExcelStyleHelper.dangerRowStyle(isCurrency: false),
        );
      } else if (v.quantity <= minS) {
        _styleRow(
          prodSheet,
          i + 1,
          12,
          ExcelStyleHelper.warningRowStyle(isCurrency: false),
        );
      }
    }
    if (variants.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        prodSheet,
        rowIndex: variants.length + 1,
        cells: [
          TextCellValue('الإجمالي (${variants.length} صنف)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(I2:I$pEnd)'),
          TextCellValue(''),
          FormulaCellValue('SUM(K2:K$pEnd)'),
          FormulaCellValue('SUM(L2:L$pEnd)'),
        ],
        currencyCols: {10, 11},
      );
    }
    _setColumnWidths(prodSheet, const [
      26,
      18,
      20,
      12,
      14,
      16,
      16,
      16,
      12,
      12,
      22,
      22,
    ]);

    // ─── Sheet 3: العملاء (Linked to Sales & Installments) ──────────────────
    _appendStyledHeader(custSheet, const [
      'هاتف العميل',
      'اسم العميل',
      'النوع',
      'نسبة الخصم (%)',
      'نقاط الولاء',
      'عدد الفواتير',
      'إجمالي المشتريات (ج.م)',
      'متبقي التقسيط (ج.م)',
    ], headerStyle);
    for (var i = 0; i < customers.length; i++) {
      final c = customers[i];
      final rowNum = i + 2;
      custSheet.appendRow([
        TextCellValue(c.phone),
        TextCellValue(c.name),
        TextCellValue(c.customerType == 'wholesale' ? 'جملة' : 'قطاعي'),
        IntCellValue(c.discountPercent),
        IntCellValue(c.loyaltyPoints),
        sales.isEmpty
            ? IntCellValue(0)
            : FormulaCellValue("COUNTIF('$sheetSales'!D2:D$sEnd,A$rowNum)"),
        sales.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetSales'!D2:D$sEnd,A$rowNum,'$sheetSales'!H2:H$sEnd)",
              ),
        installments.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetInstallments'!D2:D$insEnd,A$rowNum,'$sheetInstallments'!L2:L$insEnd)",
              ),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      custSheet,
      startRow: 1,
      rowCount: customers.length,
      colCount: 8,
      currencyCols: {6, 7},
      centerCols: {0, 2, 3, 4, 5},
    );
    if (customers.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        custSheet,
        rowIndex: customers.length + 1,
        cells: [
          TextCellValue('الإجمالي (${customers.length} عميل)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$cEnd)'),
          FormulaCellValue('SUM(F2:F$cEnd)'),
          FormulaCellValue('SUM(G2:G$cEnd)'),
          FormulaCellValue('SUM(H2:H$cEnd)'),
        ],
        currencyCols: {6, 7},
      );
    }
    _setColumnWidths(custSheet, const [18, 24, 12, 15, 14, 14, 20, 20]);

    // ─── Sheet 4: الموردين (Linked to Purchases) ────────────────────────────
    _appendStyledHeader(supSheet, const [
      'اسم المورد',
      'الهاتف',
      'الشركة',
      'العنوان',
      'الرصيد المستحق (ج.م)',
      'عدد فواتير الشراء',
      'إجمالي المشتريات (ج.م)',
    ], headerStyle);
    for (var i = 0; i < suppliers.length; i++) {
      final s = suppliers[i];
      final rowNum = i + 2;
      supSheet.appendRow([
        TextCellValue(s.name),
        TextCellValue(s.phone ?? ''),
        TextCellValue(s.companyName ?? ''),
        TextCellValue(s.address ?? ''),
        DoubleCellValue(s.balance / 100.0),
        purchases.isEmpty
            ? IntCellValue(0)
            : FormulaCellValue(
                "COUNTIF('$sheetPurchases'!C2:C$purEnd,A$rowNum)",
              ),
        purchases.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetPurchases'!C2:C$purEnd,A$rowNum,'$sheetPurchases'!E2:E$purEnd)",
              ),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      supSheet,
      startRow: 1,
      rowCount: suppliers.length,
      colCount: 7,
      currencyCols: {4, 6},
      centerCols: {1, 5},
    );
    if (suppliers.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        supSheet,
        rowIndex: suppliers.length + 1,
        cells: [
          TextCellValue('الإجمالي (${suppliers.length} مورد)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$supEnd)'),
          FormulaCellValue('SUM(F2:F$supEnd)'),
          FormulaCellValue('SUM(G2:G$supEnd)'),
        ],
        currencyCols: {4, 6},
      );
    }
    _setColumnWidths(supSheet, const [24, 18, 22, 26, 20, 16, 20]);

    // ─── Sheet 5: الشركاء (Live Linked to Dashboard Net Profit) ──────────────
    _appendStyledHeader(partnerSheet, const [
      'اسم الشريك',
      'الهاتف',
      'نسبة الشراكة (%)',
      'رأس المال المساهم (ج.م)',
      'المسحوبات من الأرباح (ج.م)',
      'نصيب الربح التقديري (ج.م)',
    ], headerStyle);
    for (var i = 0; i < partners.length; i++) {
      final p = partners[i];
      final rowNum = i + 2;
      partnerSheet.appendRow([
        TextCellValue(p.name),
        TextCellValue(p.phone ?? ''),
        DoubleCellValue(p.percentage),
        DoubleCellValue(p.capital / 100.0),
        DoubleCellValue(p.totalProfitWithdrawn / 100.0),
        FormulaCellValue("'$sheetDashboard'!B6*(C$rowNum/100)"),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      partnerSheet,
      startRow: 1,
      rowCount: partners.length,
      colCount: 6,
      currencyCols: {3, 4, 5},
      centerCols: {1, 2},
    );
    if (partners.isNotEmpty) {
      final partEnd = partners.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        partnerSheet,
        rowIndex: partners.length + 1,
        cells: [
          TextCellValue('الإجمالي (${partners.length} شريك)'),
          TextCellValue(''),
          FormulaCellValue('SUM(C2:C$partEnd)'),
          FormulaCellValue('SUM(D2:D$partEnd)'),
          FormulaCellValue('SUM(E2:E$partEnd)'),
          FormulaCellValue('SUM(F2:F$partEnd)'),
        ],
        currencyCols: {3, 4, 5},
      );
    }
    _setColumnWidths(partnerSheet, const [24, 18, 16, 22, 22, 24]);

    // ─── Sheet 6: الفواتير ──────────────────────────────────────────────────
    _appendStyledHeader(salesSheet, const [
      'رقم الفاتورة',
      'التاريخ والوقت',
      'اسم العميل',
      'هاتف العميل',
      'الكاشير',
      'المبلغ قبل الخصم (ج.م)',
      'الخصم (ج.م)',
      'الصافي النهائي (ج.م)',
      'طريقة الدفع',
      'الحالة',
      'ملاحظات',
    ], headerStyle);
    for (final s in sales) {
      final cust = s.customerId != null ? custMap[s.customerId] : null;
      salesSheet.appendRow([
        TextCellValue(s.shortRef),
        TextCellValue(_formatDateTime(s.date)),
        TextCellValue(cust?.name ?? 'عميل نقدي'),
        TextCellValue(cust?.phone ?? ''),
        TextCellValue(userMap[s.cashierId] ?? s.cashierId),
        DoubleCellValue(s.subtotal / 100.0),
        DoubleCellValue(s.discountAmount / 100.0),
        DoubleCellValue(s.total / 100.0),
        TextCellValue(_formatPaymentMethod(s.paymentMethod)),
        TextCellValue(s.status == 'cancelled' ? 'ملغاة' : 'مكتملة'),
        TextCellValue(s.note ?? ''),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      salesSheet,
      startRow: 1,
      rowCount: sales.length,
      colCount: 11,
      currencyCols: {5, 6, 7},
      centerCols: {0, 1, 3, 8, 9},
    );
    for (var i = 0; i < sales.length; i++) {
      if (sales[i].status == 'cancelled') {
        _styleRow(
          salesSheet,
          i + 1,
          11,
          ExcelStyleHelper.dangerRowStyle(isCurrency: false),
        );
      }
    }
    if (sales.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        salesSheet,
        rowIndex: sales.length + 1,
        cells: [
          TextCellValue('الإجمالي (${sales.length} فاتورة)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(F2:F$sEnd)'),
          FormulaCellValue('SUM(G2:G$sEnd)'),
          FormulaCellValue('SUM(H2:H$sEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {5, 6, 7},
      );
    }
    _setColumnWidths(salesSheet, const [
      18,
      20,
      22,
      16,
      18,
      18,
      14,
      18,
      16,
      12,
      24,
    ]);

    // ─── Sheet 7: تفاصيل_الفواتير (Linked to Sales & Products) ───────────────
    _appendStyledHeader(itemsSheet, const [
      'رقم الفاتورة',
      'التاريخ',
      'كود الصنف (SKU)',
      'اسم المنتج',
      'اللون',
      'المقاس',
      'الكمية',
      'سعر بيع الوحدة (ج.م)',
      'تكلفة الوحدة (ج.م)',
      'خصم السطر (ج.م)',
      'صافي السطر (ج.م)',
      'إجمالي التكلفة (ج.م)',
      'ربح السطر (ج.م)',
    ], headerStyle);
    for (var i = 0; i < validSaleItems.length; i++) {
      final item = validSaleItems[i];
      final sale = saleMap[item.saleId];
      final variant = variantMap[item.variantId];
      final rowNum = i + 2;
      itemsSheet.appendRow([
        TextCellValue(sale?.shortRef ?? item.saleId),
        TextCellValue(sale != null ? _formatDateTime(sale.date) : ''),
        TextCellValue(variant?.sku ?? item.variantId),
        TextCellValue(item.productName),
        TextCellValue(item.color),
        TextCellValue(item.size),
        IntCellValue(item.qty),
        DoubleCellValue(item.priceSnapshot / 100.0),
        DoubleCellValue(item.costSnapshot / 100.0),
        DoubleCellValue(
          (item.lineDiscount + item.promotionDiscountPiasters) / 100.0,
        ),
        DoubleCellValue(item.lineTotal / 100.0),
        FormulaCellValue('G$rowNum*I$rowNum'),
        FormulaCellValue('K$rowNum-L$rowNum'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      itemsSheet,
      startRow: 1,
      rowCount: validSaleItems.length,
      colCount: 13,
      currencyCols: {7, 8, 9, 10, 11, 12},
      centerCols: {0, 1, 2, 4, 5, 6},
    );
    if (validSaleItems.isNotEmpty) {
      final itEnd = validSaleItems.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        itemsSheet,
        rowIndex: validSaleItems.length + 1,
        cells: [
          TextCellValue('الإجمالي (${validSaleItems.length} سطر)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(G2:G$itEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(J2:J$itEnd)'),
          FormulaCellValue('SUM(K2:K$itEnd)'),
          FormulaCellValue('SUM(L2:L$itEnd)'),
          FormulaCellValue('SUM(M2:M$itEnd)'),
        ],
        currencyCols: {9, 10, 11, 12},
      );
    }
    _setColumnWidths(itemsSheet, const [
      18,
      20,
      18,
      24,
      12,
      12,
      10,
      18,
      16,
      14,
      16,
      18,
      16,
    ]);

    // ─── Sheet 8: عقود_التقسيط (Linked to Installment Payments) ─────────────
    _appendStyledHeader(instSheet, const [
      'رقم العقد',
      'رقم الفاتورة',
      'اسم العميل',
      'هاتف العميل',
      'إجمالي الفاتورة (ج.م)',
      'المقدم (ج.م)',
      'المبلغ الممول (ج.م)',
      'نسبة الفائدة (%)',
      'عدد الشهور',
      'القسط الشهري (ج.م)',
      'إجمالي المسدد (ج.م)',
      'المتبقي الحالي (ج.م)',
      'تاريخ البداية',
      'تاريخ النهاية',
      'الحالة',
    ], headerStyle);
    for (var i = 0; i < installments.length; i++) {
      final c = installments[i];
      final cust = custMap[c.customerId];
      final sale = saleMap[c.saleId];
      final rowNum = i + 2;
      instSheet.appendRow([
        TextCellValue(c.id),
        TextCellValue(sale?.shortRef ?? c.saleId),
        TextCellValue(cust?.name ?? c.customerId),
        TextCellValue(cust?.phone ?? ''),
        DoubleCellValue(c.totalPiasters / 100.0),
        DoubleCellValue(c.downPaymentPiasters / 100.0),
        FormulaCellValue('E$rowNum-F$rowNum'),
        DoubleCellValue(c.interestBp / 100.0),
        IntCellValue(c.durationMonths),
        DoubleCellValue(c.monthlyAmountPiasters / 100.0),
        installmentPayments.isEmpty
            ? DoubleCellValue(0.0)
            : FormulaCellValue(
                "SUMIF('$sheetInstallmentPayments'!A2:A$payEnd,A$rowNum,'$sheetInstallmentPayments'!D2:D$payEnd)",
              ),
        DoubleCellValue(c.remainingPiasters / 100.0),
        TextCellValue(_formatDate(c.startDate)),
        TextCellValue(_formatDate(c.endDate)),
        TextCellValue(_formatInstallmentStatus(c.status)),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      instSheet,
      startRow: 1,
      rowCount: installments.length,
      colCount: 15,
      currencyCols: {4, 5, 6, 9, 10, 11},
      centerCols: {0, 1, 3, 7, 8, 12, 13, 14},
    );
    for (var i = 0; i < installments.length; i++) {
      if (installments[i].status == 'overdue') {
        _styleRow(
          instSheet,
          i + 1,
          15,
          ExcelStyleHelper.dangerRowStyle(isCurrency: false),
        );
      }
    }
    if (installments.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        instSheet,
        rowIndex: installments.length + 1,
        cells: [
          TextCellValue('الإجمالي (${installments.length} عقد)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$insEnd)'),
          FormulaCellValue('SUM(F2:F$insEnd)'),
          FormulaCellValue('SUM(G2:G$insEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(K2:K$insEnd)'),
          FormulaCellValue('SUM(L2:L$insEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {4, 5, 6, 10, 11},
      );
    }
    _setColumnWidths(instSheet, const [
      20,
      18,
      22,
      16,
      18,
      14,
      18,
      14,
      12,
      16,
      18,
      18,
      14,
      14,
      12,
    ]);

    // ─── Sheet 9: دفعات_التقسيط ─────────────────────────────────────────────
    _appendStyledHeader(paySheet, const [
      'رقم العقد',
      'اسم العميل',
      'تاريخ الدفع',
      'المبلغ (ج.م)',
      'طريقة الدفع',
      'رقم الإيصال',
      'ملاحظات',
    ], headerStyle);
    for (final p in installmentPayments) {
      final contract = instMap[p.customerInstallmentId];
      final cust = contract != null ? custMap[contract.customerId] : null;
      paySheet.appendRow([
        TextCellValue(p.customerInstallmentId),
        TextCellValue(cust?.name ?? ''),
        TextCellValue(_formatDateTime(p.paidAt)),
        DoubleCellValue(p.amountPiasters / 100.0),
        TextCellValue(_formatPaymentMethod(p.paymentMethod)),
        TextCellValue(p.receiptNumber ?? ''),
        TextCellValue(p.notes ?? ''),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      paySheet,
      startRow: 1,
      rowCount: installmentPayments.length,
      colCount: 7,
      currencyCols: {3},
      centerCols: {0, 2, 4, 5},
    );
    if (installmentPayments.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        paySheet,
        rowIndex: installmentPayments.length + 1,
        cells: [
          TextCellValue('الإجمالي (${installmentPayments.length} دفعة)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(D2:D$payEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {3},
      );
    }
    _setColumnWidths(paySheet, const [20, 22, 20, 16, 14, 18, 26]);

    // ─── Sheet 10: المصروفات ────────────────────────────────────────────────
    _appendStyledHeader(expSheet, const [
      'التاريخ',
      'البند',
      'التصنيف',
      'المبلغ (ج.م)',
      'الملاحظات',
      'المسجل',
    ], headerStyle);
    for (final e in expenses) {
      expSheet.appendRow([
        TextCellValue(_formatDate(e.expenseDate)),
        TextCellValue(e.category),
        TextCellValue(
          e.kind == 'supplier_payment' ? 'دفعة مورد' : 'مصروف تشغيلي',
        ),
        DoubleCellValue(e.amount / 100.0),
        TextCellValue(e.note ?? ''),
        TextCellValue(userMap[e.userId] ?? e.userId),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      expSheet,
      startRow: 1,
      rowCount: expenses.length,
      colCount: 6,
      currencyCols: {3},
      centerCols: {0, 2},
    );
    if (expenses.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        expSheet,
        rowIndex: expenses.length + 1,
        cells: [
          TextCellValue('الإجمالي (${expenses.length} مصروف)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(D2:D$expEnd)'),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {3},
      );
    }
    _setColumnWidths(expSheet, const [14, 22, 16, 16, 28, 18]);

    // ─── Sheet 11: المشتريات ────────────────────────────────────────────────
    _appendStyledHeader(purSheet, const [
      'رقم فاتورة الشراء',
      'التاريخ',
      'اسم المورد',
      'الحالة',
      'الإجمالي (ج.م)',
      'المدفوع (ج.م)',
      'المتبقي (ج.م)',
      'حالة الدفع',
      'ملاحظات',
    ], headerStyle);
    for (var i = 0; i < purchases.length; i++) {
      final p = purchases[i];
      final rowNum = i + 2;
      purSheet.appendRow([
        TextCellValue(p.invoiceNumber ?? p.id),
        TextCellValue(_formatDate(p.purchaseDate)),
        TextCellValue(supMap[p.supplierId]?.name ?? p.supplierId),
        TextCellValue(_formatPurchaseStatus(p.status)),
        DoubleCellValue(p.totalAmount / 100.0),
        DoubleCellValue(p.paidAmount / 100.0),
        FormulaCellValue('E$rowNum-F$rowNum'),
        TextCellValue(_formatPaymentStatus(p.paymentStatus)),
        TextCellValue(p.notes ?? ''),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      purSheet,
      startRow: 1,
      rowCount: purchases.length,
      colCount: 9,
      currencyCols: {4, 5, 6},
      centerCols: {0, 1, 3, 7},
    );
    if (purchases.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        purSheet,
        rowIndex: purchases.length + 1,
        cells: [
          TextCellValue('الإجمالي (${purchases.length} فاتورة)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$purEnd)'),
          FormulaCellValue('SUM(F2:F$purEnd)'),
          FormulaCellValue('SUM(G2:G$purEnd)'),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {4, 5, 6},
      );
    }
    _setColumnWidths(purSheet, const [18, 14, 22, 14, 16, 16, 16, 14, 26]);

    // ─── Sheet 12: المرتجعات ────────────────────────────────────────────────
    _appendStyledHeader(retSheet, const [
      'رقم المرتجع',
      'رقم الفاتورة الأصلية',
      'التاريخ',
      'السبب',
      'المبلغ المسترد (ج.م)',
      'طريقة الاسترداد',
      'الكاشير',
    ], headerStyle);
    for (final r in returns) {
      final sale = r.saleId != null ? saleMap[r.saleId] : null;
      retSheet.appendRow([
        TextCellValue(r.id),
        TextCellValue(sale?.shortRef ?? r.saleId ?? ''),
        TextCellValue(_formatDateTime(r.date)),
        TextCellValue(r.reason),
        DoubleCellValue(r.refundAmount / 100.0),
        TextCellValue(_formatPaymentMethod(r.paymentMethod)),
        TextCellValue(userMap[r.cashierId] ?? r.cashierId),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      retSheet,
      startRow: 1,
      rowCount: returns.length,
      colCount: 7,
      currencyCols: {4},
      centerCols: {0, 1, 2, 5},
    );
    if (returns.isNotEmpty) {
      ExcelStyleHelper.appendTotalsRow(
        retSheet,
        rowIndex: returns.length + 1,
        cells: [
          TextCellValue('الإجمالي (${returns.length} مرتجع)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$retEnd)'),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {4},
      );
    }
    _setColumnWidths(retSheet, const [20, 18, 20, 26, 18, 16, 18]);

    // ─── Sheet 13: نواقص_المخزون (Ready-to-Reorder List) ─────────────────────
    final lowStockVariants = variants.where((v) {
      final minS = prodMap[v.productId]?.minStock ?? 5;
      return v.quantity <= minS;
    }).toList();
    _appendStyledHeader(lowStockSheet, const [
      'اسم المنتج',
      'التصنيف',
      'كود الصنف (SKU)',
      'المقاس',
      'اللون',
      'الرصيد الحالي',
      'حد الطلب',
      'العجز المطلوب',
      'سعر التكلفة (ج.م)',
      'تكلفة التوريد التقديرية (ج.م)',
    ], accentHeaderStyle);
    for (var i = 0; i < lowStockVariants.length; i++) {
      final v = lowStockVariants[i];
      final prod = prodMap[v.productId];
      final minS = prod?.minStock ?? 5;
      final rowNum = i + 2;
      lowStockSheet.appendRow([
        TextCellValue(prod?.name ?? v.productId),
        TextCellValue(
          prod != null ? (catMap[prod.categoryId] ?? 'عام') : 'عام',
        ),
        TextCellValue(v.sku),
        TextCellValue(v.size),
        TextCellValue(v.color),
        IntCellValue(v.quantity),
        IntCellValue(minS),
        FormulaCellValue('MAX(1,G$rowNum-F$rowNum)'),
        DoubleCellValue(v.costPrice / 100.0),
        FormulaCellValue('H$rowNum*I$rowNum'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      lowStockSheet,
      startRow: 1,
      rowCount: lowStockVariants.length,
      colCount: 10,
      currencyCols: {8, 9},
      centerCols: {2, 3, 4, 5, 6, 7},
    );
    for (var i = 0; i < lowStockVariants.length; i++) {
      if (lowStockVariants[i].quantity <= 0) {
        _styleRow(
          lowStockSheet,
          i + 1,
          10,
          ExcelStyleHelper.dangerRowStyle(isCurrency: false),
        );
      }
    }
    if (lowStockVariants.isNotEmpty) {
      final lowEnd = lowStockVariants.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        lowStockSheet,
        rowIndex: lowStockVariants.length + 1,
        cells: [
          TextCellValue('الإجمالي (${lowStockVariants.length} صنف ناقص)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(F2:F$lowEnd)'),
          TextCellValue(''),
          FormulaCellValue('SUM(H2:H$lowEnd)'),
          TextCellValue(''),
          FormulaCellValue('SUM(J2:J$lowEnd)'),
        ],
        currencyCols: {9},
      );
    }
    _setColumnWidths(lowStockSheet, const [
      26,
      18,
      20,
      12,
      14,
      14,
      12,
      14,
      18,
      22,
    ]);

    // ─── Sheet 14: الورديات_والدرج ───────────────────────────────────────────
    _appendStyledHeader(shiftsSheet, const [
      'رقم الوردية',
      'الكاشير',
      'تاريخ الفتح',
      'تاريخ الإغلاق',
      'رصيد الافتتاح (ج.م)',
      'الرصيد المتوقع (ج.م)',
      'الرصيد الفعلي (ج.م)',
      'العجز / الزيادة (ج.م)',
      'الحالة',
    ], headerStyle);
    for (final sh in shifts) {
      shiftsSheet.appendRow([
        TextCellValue(sh.id.length >= 8 ? sh.id.substring(0, 8) : sh.id),
        TextCellValue(userMap[sh.cashierId] ?? sh.cashierId),
        TextCellValue(_formatDateTime(sh.openedAt)),
        TextCellValue(sh.closedAt != null ? _formatDateTime(sh.closedAt!) : '-'),
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
        rowIndex: shifts.length + 1,
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
    _setColumnWidths(shiftsSheet, const [14, 20, 20, 20, 18, 18, 18, 18, 12]);

    // ─── Sheet 15: المحافظ_الإلكترونية ──────────────────────────────────────
    _appendStyledHeader(walletsSheet, const [
      'اسم المحفظة',
      'النوع',
      'رقم الحساب / الهاتف',
      'الرصيد الحالي (ج.م)',
      'الحد الشهري (ج.م)',
      'المستخدم شهرياً (ج.م)',
      'الحالة',
    ], headerStyle);
    for (final w in wallets) {
      walletsSheet.appendRow([
        TextCellValue(w.name),
        TextCellValue(w.providerType),
        TextCellValue(w.phoneOrTerminal),
        DoubleCellValue(w.currentBalance / 100.0),
        DoubleCellValue(w.monthlyLimit / 100.0),
        DoubleCellValue(w.monthlyUsed / 100.0),
        TextCellValue(w.isActive ? 'نشطة' : 'متوقفة'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      walletsSheet,
      startRow: 1,
      rowCount: wallets.length,
      colCount: 7,
      currencyCols: {3, 4, 5},
      centerCols: {1, 2, 6},
    );
    if (wallets.isNotEmpty) {
      final walEnd = wallets.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        walletsSheet,
        rowIndex: wallets.length + 1,
        cells: [
          TextCellValue('الإجمالي (${wallets.length} محفظة)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(D2:D$walEnd)'),
          FormulaCellValue('SUM(E2:E$walEnd)'),
          FormulaCellValue('SUM(F2:F$walEnd)'),
          TextCellValue(''),
        ],
        currencyCols: {3, 4, 5},
      );
    }
    _setColumnWidths(walletsSheet, const [24, 18, 20, 18, 18, 20, 12]);

    // ─── Sheet 16: حركات_المخزن ──────────────────────────────────────────────
    _appendStyledHeader(invLogsSheet, const [
      'التاريخ والوقت',
      'المنتج',
      'كود الصنف (SKU)',
      'نوع الحركة',
      'التغير في الكمية',
      'السبب / المرجع',
      'المستخدم',
    ], headerStyle);
    for (final l in inventoryLogs) {
      final v = variantMap[l.variantId];
      final prod = v != null ? prodMap[v.productId] : null;
      invLogsSheet.appendRow([
        TextCellValue(_formatDateTime(l.createdAt)),
        TextCellValue(prod?.name ?? l.variantId),
        TextCellValue(v?.sku ?? ''),
        TextCellValue(l.type),
        IntCellValue(l.qtyDelta),
        TextCellValue(l.reason ?? l.refType),
        TextCellValue(userMap[l.userId] ?? l.userId),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      invLogsSheet,
      startRow: 1,
      rowCount: inventoryLogs.length,
      colCount: 7,
      centerCols: {0, 2, 3, 4},
    );
    _setColumnWidths(invLogsSheet, const [20, 24, 18, 16, 16, 28, 18]);

    // ─── Sheet 17: تحصيلات_العملاء_والموردين ─────────────────────────────────
    _appendStyledHeader(partyPaySheet, const [
      'النوع',
      'التاريخ والوقت',
      'العميل / المورد',
      'المبلغ (ج.م)',
      'طريقة الدفع',
      'رقم المرجع',
      'ملاحظات',
    ], headerStyle);
    int partyPayCount = 0;
    for (final cp in customerPayments) {
      partyPaySheet.appendRow([
        TextCellValue('تحصيل من عميل'),
        TextCellValue(_formatDateTime(cp.paymentDate)),
        TextCellValue(custMap[cp.customerId]?.name ?? cp.customerId),
        DoubleCellValue(cp.amount / 100.0),
        TextCellValue(_formatPaymentMethod(cp.paymentMethod)),
        TextCellValue(cp.referenceNumber ?? ''),
        TextCellValue(cp.notes ?? ''),
      ]);
      partyPayCount++;
    }
    for (final sp in supplierPayments) {
      partyPaySheet.appendRow([
        TextCellValue('سداد لمورد'),
        TextCellValue(_formatDateTime(sp.paymentDate)),
        TextCellValue(supMap[sp.supplierId]?.name ?? sp.supplierId),
        DoubleCellValue(sp.amount / 100.0),
        TextCellValue(_formatPaymentMethod(sp.paymentMethod)),
        TextCellValue(sp.referenceNumber ?? ''),
        TextCellValue(sp.notes ?? ''),
      ]);
      partyPayCount++;
    }
    ExcelStyleHelper.styleDataRows(
      partyPaySheet,
      startRow: 1,
      rowCount: partyPayCount,
      colCount: 7,
      currencyCols: {3},
      centerCols: {0, 1, 4, 5},
    );
    if (partyPayCount > 0) {
      final ppEnd = partyPayCount + 1;
      ExcelStyleHelper.appendTotalsRow(
        partyPaySheet,
        rowIndex: ppEnd,
        cells: [
          TextCellValue('الإجمالي ($partyPayCount سند)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(D2:D$ppEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ],
        currencyCols: {3},
      );
    }
    _setColumnWidths(partyPaySheet, const [18, 20, 24, 18, 16, 18, 26]);

    // ─── Sheet 18: حركات_الدرج ───────────────────────────────────────────────
    _appendStyledHeader(cashMovSheet, const [
      'التاريخ والوقت',
      'الاتجاه',
      'النوع',
      'الطريقة',
      'المبلغ (ج.م)',
      'البيان / الملاحظات',
    ], headerStyle);
    for (final cm in cashMovements) {
      final dt = DateTime.fromMillisecondsSinceEpoch(cm.createdAt);
      cashMovSheet.appendRow([
        TextCellValue(_formatDateTime(dt)),
        TextCellValue(cm.direction == 'in' ? 'وارد للدرج' : 'صادر من الدرج'),
        TextCellValue(cm.type),
        TextCellValue(_formatPaymentMethod(cm.method)),
        DoubleCellValue(cm.amountPiasters / 100.0),
        TextCellValue(cm.notes ?? ''),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      cashMovSheet,
      startRow: 1,
      rowCount: cashMovements.length,
      colCount: 6,
      currencyCols: {4},
      centerCols: {0, 1, 2, 3},
    );
    if (cashMovements.isNotEmpty) {
      final cmEnd = cashMovements.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        cashMovSheet,
        rowIndex: cmEnd,
        cells: [
          TextCellValue('الإجمالي (${cashMovements.length} حركة)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(E2:E$cmEnd)'),
          TextCellValue(''),
        ],
        currencyCols: {4},
      );
    }
    _setColumnWidths(cashMovSheet, const [20, 16, 18, 16, 18, 30]);

    // ─── Sheet 19: الأصناف_الراكدة (0 مبيعات آخر 30 يوم) ──────────────────────
    final since30d = DateTime.now().subtract(const Duration(days: 30));
    final recentVariantIds = <String>{};
    for (final si in validSaleItems) {
      final sale = saleMap[si.saleId];
      if (sale != null && sale.date.isAfter(since30d)) {
        recentVariantIds.add(si.variantId);
      }
    }
    final stagnantVariants = variants
        .where((v) => v.quantity > 0 && !recentVariantIds.contains(v.id))
        .toList();
    _appendStyledHeader(stagnantSheet, const [
      'اسم المنتج',
      'التصنيف',
      'كود الصنف (SKU)',
      'المقاس',
      'اللون',
      'الرصيد المتاح',
      'سعر التكلفة (ج.م)',
      'سعر البيع (ج.م)',
      'رأس المال المجمد (ج.م)',
    ], accentHeaderStyle);
    for (var i = 0; i < stagnantVariants.length; i++) {
      final v = stagnantVariants[i];
      final prod = prodMap[v.productId];
      final rowNum = i + 2;
      stagnantSheet.appendRow([
        TextCellValue(prod?.name ?? v.productId),
        TextCellValue(
          prod != null ? (catMap[prod.categoryId] ?? 'عام') : 'عام',
        ),
        TextCellValue(v.sku),
        TextCellValue(v.size),
        TextCellValue(v.color),
        IntCellValue(v.quantity),
        DoubleCellValue(v.costPrice / 100.0),
        DoubleCellValue(v.sellPrice / 100.0),
        FormulaCellValue('F$rowNum*G$rowNum'),
      ]);
    }
    ExcelStyleHelper.styleDataRows(
      stagnantSheet,
      startRow: 1,
      rowCount: stagnantVariants.length,
      colCount: 9,
      currencyCols: {6, 7, 8},
      centerCols: {2, 3, 4, 5},
    );
    if (stagnantVariants.isNotEmpty) {
      final stEnd = stagnantVariants.length + 1;
      ExcelStyleHelper.appendTotalsRow(
        stagnantSheet,
        rowIndex: stEnd,
        cells: [
          TextCellValue('الإجمالي (${stagnantVariants.length} صنف راكد)'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(F2:F$stEnd)'),
          TextCellValue(''),
          TextCellValue(''),
          FormulaCellValue('SUM(I2:I$stEnd)'),
        ],
        currencyCols: {8},
      );
    }
    _setColumnWidths(
      stagnantSheet,
      const [26, 18, 20, 12, 14, 14, 18, 18, 22],
    );

    final encoded = excel.encode();
    if (encoded == null) {
      throw Exception('فشل إنشاء ملف الإكسيل الشامل');
    }
    final bytes = Uint8List.fromList(encoded);

    return (
      bytes: bytes,
      meta: ExcelFullExportResult(
        filePath: '',
        sizeBytes: bytes.length,
        sheetCount: 19,
        productsCount: variants.length,
        customersCount: customers.length,
        suppliersCount: suppliers.length,
        salesCount: sales.length,
        installmentsCount: installments.length,
        expensesCount: expenses.length,
      ),
    );
  }

  /// Exports the full linked workbook and saves it to a user-selected file path.
  /// Returns `null` if the user cancels the save dialog.
  Future<ExcelFullExportResult?> exportFullWorkbook() async {
    final built = await buildFullWorkbookBytes();
    final nowStr = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final defaultName = 'Bay3ah_Full_Export_$nowStr.xlsx';
    final path = await _saveFile(
      built.bytes,
      defaultName,
      'حفظ التصدير الشامل للنظام (Excel)',
    );
    if (path == null) return null;
    return ExcelFullExportResult(
      filePath: path,
      sizeBytes: built.bytes.length,
      sheetCount: built.meta.sheetCount,
      productsCount: built.meta.productsCount,
      customersCount: built.meta.customersCount,
      suppliersCount: built.meta.suppliersCount,
      salesCount: built.meta.salesCount,
      installmentsCount: built.meta.installmentsCount,
      expensesCount: built.meta.expensesCount,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. READY-TO-FILL SHOP MIGRATION TEMPLATE
  // ═══════════════════════════════════════════════════════════════════════════

  Uint8List buildMigrationTemplateBytes() {
    final excel = Excel.createExcel();
    final headerStyle = _headerStyle();
    final accentHeaderStyle = _accentHeaderStyle();

    final infoSheet = excel[sheetInstructions];
    final prodSheet = excel[sheetProducts];
    final custSheet = excel[sheetCustomers];
    final supSheet = excel[sheetSuppliers];
    final instSheet = excel[sheetInstallments];

    excel.setDefaultSheet(sheetInstructions);
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    _appendStyledHeader(infoSheet, const [
      'خطوة',
      'التعليمات والإرشادات لنقل بيانات محلك إلى بيعة',
    ], accentHeaderStyle);
    final instructions = const [
      (
        '1',
        'املأ الشيتات التي تحتاجها فقط (المنتجات والمخزون، العملاء، الموردين، عقود التقسيط).',
      ),
      (
        '2',
        'لا تغيّر أسماء الشيتات في القالب ليتم التعرف عليها تلقائياً، واحذف صفوف الأمثلة قبل الاستيراد أو عدّلها.',
      ),
      ('3', 'الأسعار كلها بالجنيه المصري (مثال: 350 أو 350.50).'),
      (
        '4',
        'في شيت المنتجات: إذا تركت عمود SKU فارغاً سيولّد النظام كوداً فريداً تلقائياً.',
      ),
      (
        '5',
        'في شيت العملاء: رقم الهاتف هو مفتاح الربط الفريد؛ اكتب نوع العميل (قطاعي) أو (جملة).',
      ),
      (
        '6',
        'في شيت عقود التقسيط: اربط كل عقد برقم هاتف العميل، وإذا لم يكن العميل مسجلاً فسيتم إنشاؤه تلقائياً.',
      ),
      (
        '7',
        'هل لديك ملف إكسيل جاهز بأسماء أعمدة مختلفة؟ يمكنك رفعه مباشرة باستخدام «ربط الأعمدة التفاعلي» بدون تعديله!',
      ),
    ];
    for (final row in instructions) {
      infoSheet.appendRow([TextCellValue(row.$1), TextCellValue(row.$2)]);
    }
    _setColumnWidths(infoSheet, const [10, 82]);

    // Products template
    _appendStyledHeader(prodSheet, const [
      'اسم المنتج',
      'التصنيف',
      'كود الصنف (SKU)',
      'المقاس',
      'اللون',
      'سعر التكلفة (ج.م)',
      'سعر البيع (ج.م)',
      'سعر الجملة (ج.م)',
      'الكمية',
      'حد الطلب',
    ], headerStyle);
    prodSheet.appendRow([
      TextCellValue('تيشيرت بولو قطن'),
      TextCellValue('تيشيرتات'),
      TextCellValue('POLO-BLK-L'),
      TextCellValue('L'),
      TextCellValue('أسود'),
      DoubleCellValue(220),
      DoubleCellValue(350),
      DoubleCellValue(300),
      IntCellValue(25),
      IntCellValue(5),
    ]);
    prodSheet.appendRow([
      TextCellValue('بنطلون جينز سليم'),
      TextCellValue('بناطيل'),
      TextCellValue('JEANS-BLU-34'),
      TextCellValue('34'),
      TextCellValue('أزرق غامق'),
      DoubleCellValue(380),
      DoubleCellValue(590),
      DoubleCellValue(510),
      IntCellValue(15),
      IntCellValue(3),
    ]);
    _setColumnWidths(prodSheet, const [24, 16, 18, 12, 14, 16, 16, 16, 12, 12]);

    // Customers template
    _appendStyledHeader(custSheet, const [
      'اسم العميل',
      'هاتف العميل',
      'النوع',
      'نسبة الخصم (%)',
      'نقاط الولاء',
    ], headerStyle);
    custSheet.appendRow([
      TextCellValue('أحمد محمود'),
      TextCellValue('01012345678'),
      TextCellValue('قطاعي'),
      IntCellValue(0),
      IntCellValue(50),
    ]);
    custSheet.appendRow([
      TextCellValue('محل الأناقة للجملة'),
      TextCellValue('01198765432'),
      TextCellValue('جملة'),
      IntCellValue(10),
      IntCellValue(0),
    ]);
    _setColumnWidths(custSheet, const [24, 18, 14, 16, 14]);

    // Suppliers template
    _appendStyledHeader(supSheet, const [
      'اسم المورد',
      'الهاتف',
      'الشركة',
      'العنوان',
      'الرصيد المستحق (ج.م)',
    ], headerStyle);
    supSheet.appendRow([
      TextCellValue('مصنع النيل للملابس'),
      TextCellValue('01234567890'),
      TextCellValue('شركة النيل للتصنيع'),
      TextCellValue('العاشر من رمضان'),
      DoubleCellValue(15000),
    ]);
    _setColumnWidths(supSheet, const [24, 18, 22, 24, 20]);

    // Installments template
    _appendStyledHeader(instSheet, const [
      'هاتف العميل',
      'اسم العميل',
      'إجمالي الفاتورة (ج.م)',
      'المقدم (ج.م)',
      'نسبة الفائدة (%)',
      'عدد الشهور',
      'المتبقي الحالي (ج.م)',
      'تاريخ البداية',
      'الحالة',
    ], headerStyle);
    instSheet.appendRow([
      TextCellValue('01012345678'),
      TextCellValue('أحمد محمود'),
      DoubleCellValue(2400),
      DoubleCellValue(400),
      DoubleCellValue(10),
      IntCellValue(6),
      DoubleCellValue(1100),
      TextCellValue(_formatDate(DateTime.now())),
      TextCellValue('نشط'),
    ]);
    _setColumnWidths(instSheet, const [18, 22, 18, 14, 16, 12, 18, 16, 12]);

    final encoded = excel.encode();
    if (encoded == null) {
      throw Exception('فشل إنشاء قالب النقل');
    }
    return Uint8List.fromList(encoded);
  }

  /// Saves the migration template `.xlsx` to a user-chosen path.
  Future<String?> exportMigrationTemplate() async {
    final bytes = buildMigrationTemplateBytes();
    return _saveFile(
      bytes,
      'Bay3ah_Import_Template.xlsx',
      'حفظ قالب نقل البيانات الجاهز (Excel)',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. WORKBOOK INSPECTION & SMART COLUMN MAPPER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Inspects any arbitrary `.xlsx` file so the UI can show sheets, headers,
  /// sample rows, and suggested column mappings.
  ExcelWorkbookInspection inspectWorkbook(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final infos = <ExcelSheetInfo>[];

    for (final entry in excel.tables.entries) {
      final name = entry.key;
      final sheet = entry.value;
      if (name == sheetInstructions || name == sheetDashboard) continue;
      if (sheet.rows.isEmpty) continue;

      final headerRow = sheet.rows.first;
      final headers = <String>[];
      for (var i = 0; i < headerRow.length; i++) {
        final txt = _cellText(headerRow[i]);
        headers.add(txt.isEmpty ? 'عمود ${i + 1}' : txt);
      }

      // Trim trailing empty columns
      while (headers.isNotEmpty &&
          headers.last.startsWith('عمود ') &&
          sheet.rows
              .skip(1)
              .every(
                (r) =>
                    headers.length - 1 >= r.length ||
                    _cellText(r[headers.length - 1]).isEmpty,
              )) {
        headers.removeLast();
      }
      if (headers.isEmpty) continue;

      final samples = <List<String>>[];
      int nonEmptyCount = 0;
      for (var r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final values = List<String>.generate(
          headers.length,
          (c) => c < row.length ? _cellText(row[c]) : '',
        );
        if (values.every((v) => v.isEmpty)) continue;
        nonEmptyCount++;
        if (samples.length < 3) {
          samples.add(values);
        }
      }

      infos.add(
        ExcelSheetInfo(
          name: name,
          headers: headers,
          sampleRows: samples,
          dataRowCount: nonEmptyCount,
          detectedEntity: _detectEntityFromSheet(name, headers),
        ),
      );
    }

    return ExcelWorkbookInspection(sheets: infos);
  }

  /// Suggests initial column mapping for [entity] based on Arabic/English synonyms.
  ExcelColumnMapping suggestMapping(
    ExcelSheetInfo sheet,
    ExcelImportEntity entity,
  ) {
    final map = <String, int?>{};
    final specs = fieldSpecsFor(entity);
    for (final spec in specs) {
      map[spec.key] = null;
    }

    final normalizedHeaders = sheet.headers
        .map((h) => _normalizeHeader(h))
        .toList();

    for (var i = 0; i < normalizedHeaders.length; i++) {
      final h = normalizedHeaders[i];
      if (h.isEmpty) continue;

      switch (entity) {
        case ExcelImportEntity.products:
          if (map['productName'] == null &&
              _matchesAny(h, [
                'منتج',
                'صنف',
                'موديل',
                'product',
                'item',
                'name',
              ]) &&
              !_matchesAny(h, [
                'كود',
                'sku',
                'barcode',
                'باركود',
                'تصنيف',
                'عميل',
                'مورد',
              ])) {
            map['productName'] = i;
          } else if (map['categoryName'] == null &&
              _matchesAny(h, ['تصنيف', 'قسم', 'فئة', 'category', 'dept'])) {
            map['categoryName'] = i;
          } else if (map['sku'] == null &&
              _matchesAny(h, ['sku', 'كود', 'باركود', 'barcode', 'code'])) {
            map['sku'] = i;
          } else if (map['size'] == null &&
              _matchesAny(h, ['مقاس', 'قياس', 'size'])) {
            map['size'] = i;
          } else if (map['color'] == null &&
              _matchesAny(h, ['لون', 'color', 'colour'])) {
            map['color'] = i;
          } else if (map['costPrice'] == null &&
              _matchesAny(h, ['تكلفة', 'شراء', 'cost', 'buy']) &&
              !_matchesAny(h, ['قيمة المخزون', 'اجمالي'])) {
            map['costPrice'] = i;
          } else if (map['wholesalePrice'] == null &&
              _matchesAny(h, ['جملة', 'جمله', 'wholesale'])) {
            map['wholesalePrice'] = i;
          } else if (map['sellPrice'] == null &&
              _matchesAny(h, [
                'بيع',
                'قطاعي',
                'سعر',
                'sell',
                'sale',
                'retail',
                'price',
              ]) &&
              !_matchesAny(h, ['تكلفة', 'جملة', 'جمله', 'قيمة المخزون'])) {
            map['sellPrice'] = i;
          } else if (map['quantity'] == null &&
              _matchesAny(h, [
                'كمية',
                'كميه',
                'جرد',
                'رصيد',
                'مخزون',
                'qty',
                'quantity',
                'stock',
              ]) &&
              !_matchesAny(h, ['قيمة', 'حد'])) {
            map['quantity'] = i;
          } else if (map['minStock'] == null &&
              _matchesAny(h, ['حد الطلب', 'حد ادنى', 'تنبيه', 'min'])) {
            map['minStock'] = i;
          }
          break;

        case ExcelImportEntity.customers:
          if (map['phone'] == null &&
              _matchesAny(h, [
                'هاتف',
                'موبايل',
                'تليفون',
                'جوال',
                'phone',
                'mobile',
                'tel',
              ])) {
            map['phone'] = i;
          } else if (map['name'] == null &&
              _matchesAny(h, ['اسم', 'عميل', 'customer', 'client', 'name'])) {
            map['name'] = i;
          } else if (map['customerType'] == null &&
              _matchesAny(h, ['نوع', 'فئة', 'type', 'tier'])) {
            map['customerType'] = i;
          } else if (map['discountPercent'] == null &&
              _matchesAny(h, ['خصم', 'discount'])) {
            map['discountPercent'] = i;
          } else if (map['loyaltyPoints'] == null &&
              _matchesAny(h, ['نقاط', 'ولاء', 'points', 'loyalty'])) {
            map['loyaltyPoints'] = i;
          }
          break;

        case ExcelImportEntity.suppliers:
          if (map['phone'] == null &&
              _matchesAny(h, ['هاتف', 'موبايل', 'تليفون', 'phone', 'mobile'])) {
            map['phone'] = i;
          } else if (map['companyName'] == null &&
              _matchesAny(h, ['شركة', 'شركه', 'مصنع', 'company'])) {
            map['companyName'] = i;
          } else if (map['address'] == null &&
              _matchesAny(h, ['عنوان', 'address', 'location'])) {
            map['address'] = i;
          } else if (map['balance'] == null &&
              _matchesAny(h, ['رصيد', 'مستحق', 'مديونية', 'balance', 'due'])) {
            map['balance'] = i;
          } else if (map['name'] == null &&
              _matchesAny(h, ['اسم', 'مورد', 'supplier', 'vendor', 'name'])) {
            map['name'] = i;
          }
          break;

        case ExcelImportEntity.installments:
          if (map['customerPhone'] == null &&
              _matchesAny(h, ['هاتف', 'موبايل', 'تليفون', 'phone', 'mobile'])) {
            map['customerPhone'] = i;
          } else if (map['customerName'] == null &&
              _matchesAny(h, ['اسم', 'عميل', 'customer', 'name'])) {
            map['customerName'] = i;
          } else if (map['total'] == null &&
              _matchesAny(h, [
                'اجمالي',
                'إجمالي',
                'قيمة العقد',
                'فاتورة',
                'total',
              ]) &&
              !_matchesAny(h, ['مسدد', 'رقم', 'number', 'id'])) {
            map['total'] = i;
          } else if (map['downPayment'] == null &&
              _matchesAny(h, ['مقدم', 'دفعة اولى', 'down'])) {
            map['downPayment'] = i;
          } else if (map['interestPercent'] == null &&
              _matchesAny(h, ['فائدة', 'فائده', 'نسبة', 'interest', 'rate'])) {
            map['interestPercent'] = i;
          } else if (map['durationMonths'] == null &&
              _matchesAny(h, [
                'شهور',
                'أشهر',
                'اشهر',
                'مدة',
                'months',
                'duration',
              ])) {
            map['durationMonths'] = i;
          } else if (map['remaining'] == null &&
              _matchesAny(h, ['متبقي', 'باقي', 'remaining', 'balance'])) {
            map['remaining'] = i;
          } else if (map['startDate'] == null &&
              _matchesAny(h, [
                'تاريخ البداية',
                'بداية',
                'تاريخ',
                'start',
                'date',
              ]) &&
              !_matchesAny(h, ['نهاية', 'end'])) {
            map['startDate'] = i;
          } else if (map['status'] == null &&
              _matchesAny(h, ['حالة', 'حاله', 'status'])) {
            map['status'] = i;
          }
          break;

        case ExcelImportEntity.expenses:
          if (map['category'] == null &&
              _matchesAny(h, [
                'بند',
                'تصنيف',
                'مصروف',
                'نوع',
                'category',
                'title',
              ])) {
            map['category'] = i;
          } else if (map['amount'] == null &&
              _matchesAny(h, ['مبلغ', 'قيمة', 'قيمة المصروف', 'amount'])) {
            map['amount'] = i;
          } else if (map['expenseDate'] == null &&
              _matchesAny(h, ['تاريخ', 'date'])) {
            map['expenseDate'] = i;
          } else if (map['notes'] == null &&
              _matchesAny(h, ['ملاحظ', 'بيان', 'وصف', 'note'])) {
            map['notes'] = i;
          }
          break;

        case ExcelImportEntity.historicalSales:
          if (map['total'] == null &&
              _matchesAny(h, ['اجمالي', 'إجمالي', 'مبلغ', 'total', 'amount'])) {
            map['total'] = i;
          } else if (map['shortRef'] == null &&
              _matchesAny(h, ['رقم', 'فاتورة', 'مرجع', 'ref', 'invoice'])) {
            map['shortRef'] = i;
          } else if (map['paymentMethod'] == null &&
              _matchesAny(h, ['دفع', 'طريقة', 'payment', 'method'])) {
            map['paymentMethod'] = i;
          } else if (map['date'] == null && _matchesAny(h, ['تاريخ', 'date'])) {
            map['date'] = i;
          } else if (map['customerName'] == null &&
              _matchesAny(h, ['عميل', 'زبون', 'customer'])) {
            map['customerName'] = i;
          }
          break;
      }
    }

    return ExcelColumnMapping(
      sheetName: sheet.name,
      entity: entity,
      fieldToColumnIndex: map,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. PRE-COMMIT ANALYSIS (MULTI-SHEET & CUSTOM MAPPED SHEET)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Analyzes all recognized sheets in a multi-sheet workbook (Bay3ah template
  /// or full export) at once and reports conflicts + validation issues.
  Future<WorkbookImportPreview> analyzeMultiSheetWorkbook(
    Uint8List bytes, {
    bool lenientMode = false,
  }) async {
    final inspection = inspectWorkbook(bytes);
    final mappings = <ExcelColumnMapping>[];
    final seenEntities = <ExcelImportEntity>{};

    for (final sheetInfo in inspection.sheets) {
      final entity = sheetInfo.detectedEntity;
      if (entity == null || seenEntities.contains(entity)) continue;
      seenEntities.add(entity);
      mappings.add(suggestMapping(sheetInfo, entity));
    }

    return analyzeWithMappings(bytes, mappings, lenientMode: lenientMode);
  }

  /// Analyzes a single arbitrary sheet using user-selected column mappings.
  Future<WorkbookImportPreview> analyzeSheetWithMapping(
    Uint8List bytes,
    ExcelColumnMapping mapping, {
    bool lenientMode = false,
  }) {
    return analyzeWithMappings(bytes, [mapping], lenientMode: lenientMode);
  }

  /// Core analyzer supporting 1 or many sheets with explicit column mappings.
  Future<WorkbookImportPreview> analyzeWithMappings(
    Uint8List bytes,
    List<ExcelColumnMapping> mappings, {
    bool lenientMode = false,
  }) async {
    final excel = Excel.decodeBytes(bytes);

    final newProducts = <MigrationProductRow>[];
    final productConflicts = <MigrationProductConflict>[];
    final newCustomers = <MigrationCustomerRow>[];
    final customerConflicts = <MigrationCustomerConflict>[];
    final newSuppliers = <MigrationSupplierRow>[];
    final supplierConflicts = <MigrationSupplierConflict>[];
    final newInstallments = <MigrationInstallmentRow>[];
    final newExpenses = <MigrationExpenseRow>[];
    final newHistoricalSales = <MigrationHistoricalSaleRow>[];
    final issues = <ExcelRowIssue>[];

    // Preload existing lookup maps from DB
    final existingVariants = await (_db.select(
      _db.productVariants,
    )..where((v) => v.deletedAt.isNull())).get();
    final existingProducts = await (_db.select(
      _db.products,
    )..where((p) => p.deletedAt.isNull())).get();
    final existingCustomers = await (_db.select(
      _db.customers,
    )..where((c) => c.deletedAt.isNull())).get();
    final existingSuppliers = await (_db.select(
      _db.suppliers,
    )..where((s) => s.deletedAt.isNull())).get();

    final prodNameById = {for (final p in existingProducts) p.id: p.name};
    final variantBySku = {
      for (final v in existingVariants) v.sku.trim().toLowerCase(): v,
    };
    final customerByPhone = {
      for (final c in existingCustomers) _normalizePhone(c.phone): c,
    };
    final supplierByKey = <String, Supplier>{};
    for (final s in existingSuppliers) {
      supplierByKey[s.name.trim().toLowerCase()] = s;
      final ph = _normalizePhone(s.phone ?? '');
      if (ph.isNotEmpty) {
        supplierByKey['phone:$ph'] = s;
      }
    }

    // Track in-file duplicates cleanly
    final seenSkusInFile = <String>{};
    final seenPhonesInFile = <String>{};
    final seenSuppliersInFile = <String>{};

    for (final mapping in mappings) {
      final sheet = excel.tables[mapping.sheetName];
      if (sheet == null || sheet.rows.length <= 1) continue;

      switch (mapping.entity) {
        case ExcelImportEntity.products:
          _parseProductsSheet(
            sheet: sheet,
            sheetName: mapping.sheetName,
            colMap: mapping.fieldToColumnIndex,
            variantBySku: variantBySku,
            prodNameById: prodNameById,
            seenSkusInFile: seenSkusInFile,
            newProducts: newProducts,
            conflicts: productConflicts,
            issues: issues,
            lenientMode: lenientMode,
          );
          break;
        case ExcelImportEntity.customers:
          _parseCustomersSheet(
            sheet: sheet,
            sheetName: mapping.sheetName,
            colMap: mapping.fieldToColumnIndex,
            customerByPhone: customerByPhone,
            seenPhonesInFile: seenPhonesInFile,
            newCustomers: newCustomers,
            conflicts: customerConflicts,
            issues: issues,
            lenientMode: lenientMode,
          );
          break;
        case ExcelImportEntity.suppliers:
          _parseSuppliersSheet(
            sheet: sheet,
            sheetName: mapping.sheetName,
            colMap: mapping.fieldToColumnIndex,
            supplierByKey: supplierByKey,
            seenSuppliersInFile: seenSuppliersInFile,
            newSuppliers: newSuppliers,
            conflicts: supplierConflicts,
            issues: issues,
          );
          break;
        case ExcelImportEntity.installments:
          _parseInstallmentsSheet(
            sheet: sheet,
            sheetName: mapping.sheetName,
            colMap: mapping.fieldToColumnIndex,
            newInstallments: newInstallments,
            issues: issues,
          );
          break;
        case ExcelImportEntity.expenses:
          _parseExpensesSheet(
            sheet: sheet,
            sheetName: mapping.sheetName,
            colMap: mapping.fieldToColumnIndex,
            newExpenses: newExpenses,
            issues: issues,
            lenientMode: lenientMode,
          );
          break;
        case ExcelImportEntity.historicalSales:
          _parseHistoricalSalesSheet(
            sheet: sheet,
            sheetName: mapping.sheetName,
            colMap: mapping.fieldToColumnIndex,
            newSales: newHistoricalSales,
            issues: issues,
            lenientMode: lenientMode,
          );
          break;
      }
    }

    return WorkbookImportPreview(
      newProducts: newProducts,
      productConflicts: productConflicts,
      newCustomers: newCustomers,
      customerConflicts: customerConflicts,
      newSuppliers: newSuppliers,
      supplierConflicts: supplierConflicts,
      newInstallments: newInstallments,
      newExpenses: newExpenses,
      newHistoricalSales: newHistoricalSales,
      issues: issues,
    );
  }

  void _parseProductsSheet({
    required Sheet sheet,
    required String sheetName,
    required Map<String, int?> colMap,
    required Map<String, ProductVariant> variantBySku,
    required Map<String, String> prodNameById,
    required Set<String> seenSkusInFile,
    required List<MigrationProductRow> newProducts,
    required List<MigrationProductConflict> conflicts,
    required List<ExcelRowIssue> issues,
    bool lenientMode = false,
  }) {
    final cName = colMap['productName'];
    final cSell = colMap['sellPrice'];
    if (cName == null) {
      issues.add(
        ExcelRowIssue(
          entity: ExcelImportEntity.products,
          sheetName: sheetName,
          rowNumber: 1,
          message: 'لم يتم تحديد عمود «اسم المنتج».',
        ),
      );
      return;
    }

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isRowEmpty(row)) continue;
      final rowNum = r + 1;

      final prodName = _valueAt(row, cName);
      if (prodName.isEmpty) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.products,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'اسم المنتج فارغ — تم تخطي الصف.',
          ),
        );
        continue;
      }

      final catName = _valueAt(row, colMap['categoryName']);
      var sku = _valueAt(row, colMap['sku']);
      if (sku.isEmpty) {
        sku = 'MIG-${_uuid.v4().substring(0, 8).toUpperCase()}';
        if (lenientMode) {
          issues.add(
            ExcelRowIssue(
              entity: ExcelImportEntity.products,
              sheetName: sheetName,
              rowNumber: rowNum,
              message: 'تم توليد كود SKU تلقائياً ($sku) لعدم وجوده.',
              severity: ExcelIssueSeverity.warning,
            ),
          );
        }
      }
      final skuKey = sku.toLowerCase();
      if (seenSkusInFile.contains(skuKey)) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.products,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'كود الصنف ($sku) مكرر داخل نفس الملف — تم تخطي التكرار.',
            severity: ExcelIssueSeverity.warning,
          ),
        );
        continue;
      }
      seenSkusInFile.add(skuKey);

      final size = _valueAt(row, colMap['size']);
      final color = _valueAt(row, colMap['color']);
      final costVal = _parseDouble(_valueAt(row, colMap['costPrice']));
      final sellVal = cSell != null ? _parseDouble(_valueAt(row, cSell)) : 0.0;
      final wholesaleVal = _parseDouble(
        _valueAt(row, colMap['wholesalePrice']),
      );
      final qtyVal = _parseInt(_valueAt(row, colMap['quantity']));
      final minVal = _parseInt(_valueAt(row, colMap['minStock']), fallback: 5);

      if (costVal < 0 || sellVal < 0 || wholesaleVal < 0 || qtyVal < 0) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.products,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'الأسعار أو الكمية لا يمكن أن تكون سالبة.',
          ),
        );
        continue;
      }

      final parsed = MigrationProductRow(
        rowNumber: rowNum,
        productName: prodName,
        categoryName: catName.isEmpty ? 'عام' : catName,
        sku: sku,
        size: size.isEmpty ? 'قياسي' : size,
        color: color.isEmpty ? 'افتراضي' : color,
        costPricePiasters: (costVal * 100).round(),
        sellPricePiasters: (sellVal * 100).round(),
        wholesalePricePiasters: (wholesaleVal * 100).round(),
        quantity: qtyVal,
        minStock: minVal < 0 ? 5 : minVal,
      );

      final existing = variantBySku[skuKey];
      if (existing != null) {
        conflicts.add(
          MigrationProductConflict(
            row: parsed,
            existingVariantId: existing.id,
            existingProductId: existing.productId,
            existingProductName:
                prodNameById[existing.productId] ?? existing.productId,
            existingQty: existing.quantity,
            existingSellPiasters: existing.sellPrice,
          ),
        );
      } else {
        newProducts.add(parsed);
      }
    }
  }

  void _parseCustomersSheet({
    required Sheet sheet,
    required String sheetName,
    required Map<String, int?> colMap,
    required Map<String, Customer> customerByPhone,
    required Set<String> seenPhonesInFile,
    required List<MigrationCustomerRow> newCustomers,
    required List<MigrationCustomerConflict> conflicts,
    required List<ExcelRowIssue> issues,
    bool lenientMode = false,
  }) {
    final cName = colMap['name'];
    final cPhone = colMap['phone'];
    if (cName == null || (cPhone == null && !lenientMode)) {
      issues.add(
        ExcelRowIssue(
          entity: ExcelImportEntity.customers,
          sheetName: sheetName,
          rowNumber: 1,
          message: 'يجب تحديد عمودي «اسم العميل» و«رقم الهاتف».',
        ),
      );
      return;
    }

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isRowEmpty(row)) continue;
      final rowNum = r + 1;

      final name = _valueAt(row, cName);
      var phone = cPhone != null ? _normalizePhone(_valueAt(row, cPhone)) : '';
      if (name.isEmpty || (phone.isEmpty && !lenientMode)) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.customers,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'اسم العميل أو رقم الهاتف فارغ — تم تخطي الصف.',
          ),
        );
        continue;
      }
      if (phone.isEmpty && lenientMode) {
        phone = 'N/A-$rowNum';
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.customers,
            sheetName: sheetName,
            rowNumber: rowNum,
            message:
                'هاتف العميل ($name) مفقود — تم تعبئته بقيمة افتراضية ($phone).',
            severity: ExcelIssueSeverity.warning,
          ),
        );
      }

      if (seenPhonesInFile.contains(phone)) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.customers,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'رقم الهاتف ($phone) مكرر داخل الملف — تم تخطي التكرار.',
            severity: ExcelIssueSeverity.warning,
          ),
        );
        continue;
      }
      seenPhonesInFile.add(phone);

      final rawType = _valueAt(row, colMap['customerType']).toLowerCase();
      final customerType =
          (rawType.contains('جمل') || rawType.contains('wholesale'))
          ? 'wholesale'
          : 'retail';
      final discount = _parseInt(
        _valueAt(row, colMap['discountPercent']),
      ).clamp(0, 100);
      final points = _parseInt(
        _valueAt(row, colMap['loyaltyPoints']),
      ).clamp(0, 100000000);

      final parsed = MigrationCustomerRow(
        rowNumber: rowNum,
        name: name,
        phone: phone,
        customerType: customerType,
        discountPercent: discount,
        loyaltyPoints: points,
      );

      final existing = customerByPhone[phone];
      if (existing != null) {
        conflicts.add(
          MigrationCustomerConflict(
            row: parsed,
            existingCustomerId: existing.id,
            existingName: existing.name,
          ),
        );
      } else {
        newCustomers.add(parsed);
      }
    }
  }

  void _parseSuppliersSheet({
    required Sheet sheet,
    required String sheetName,
    required Map<String, int?> colMap,
    required Map<String, Supplier> supplierByKey,
    required Set<String> seenSuppliersInFile,
    required List<MigrationSupplierRow> newSuppliers,
    required List<MigrationSupplierConflict> conflicts,
    required List<ExcelRowIssue> issues,
  }) {
    final cName = colMap['name'];
    if (cName == null) {
      issues.add(
        ExcelRowIssue(
          entity: ExcelImportEntity.suppliers,
          sheetName: sheetName,
          rowNumber: 1,
          message: 'يجب تحديد عمود «اسم المورد».',
        ),
      );
      return;
    }

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isRowEmpty(row)) continue;
      final rowNum = r + 1;

      final name = _valueAt(row, cName);
      if (name.isEmpty) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.suppliers,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'اسم المورد فارغ — تم تخطي الصف.',
          ),
        );
        continue;
      }

      final nameKey = name.toLowerCase();
      if (seenSuppliersInFile.contains(nameKey)) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.suppliers,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'اسم المورد ($name) مكرر داخل الملف — تم تخطي التكرار.',
            severity: ExcelIssueSeverity.warning,
          ),
        );
        continue;
      }
      seenSuppliersInFile.add(nameKey);

      final phoneRaw = _normalizePhone(_valueAt(row, colMap['phone']));
      final company = _valueAt(row, colMap['companyName']);
      final address = _valueAt(row, colMap['address']);
      final balanceVal = _parseDouble(_valueAt(row, colMap['balance']));

      final parsed = MigrationSupplierRow(
        rowNumber: rowNum,
        name: name,
        phone: phoneRaw.isEmpty ? null : phoneRaw,
        companyName: company.isEmpty ? null : company,
        address: address.isEmpty ? null : address,
        balancePiasters: (balanceVal * 100).round(),
      );

      final existing =
          supplierByKey[nameKey] ??
          (phoneRaw.isNotEmpty ? supplierByKey['phone:$phoneRaw'] : null);
      if (existing != null) {
        conflicts.add(
          MigrationSupplierConflict(
            row: parsed,
            existingSupplierId: existing.id,
            existingName: existing.name,
          ),
        );
      } else {
        newSuppliers.add(parsed);
      }
    }
  }

  void _parseInstallmentsSheet({
    required Sheet sheet,
    required String sheetName,
    required Map<String, int?> colMap,
    required List<MigrationInstallmentRow> newInstallments,
    required List<ExcelRowIssue> issues,
  }) {
    final cPhone = colMap['customerPhone'];
    final cTotal = colMap['total'];
    final cDuration = colMap['durationMonths'];
    final cRemaining = colMap['remaining'];

    if (cPhone == null ||
        cTotal == null ||
        cDuration == null ||
        cRemaining == null) {
      issues.add(
        ExcelRowIssue(
          entity: ExcelImportEntity.installments,
          sheetName: sheetName,
          rowNumber: 1,
          message:
              'يجب تحديد أعمدة «هاتف العميل» و«الإجمالي» و«عدد الشهور» و«المتبقي الحالي».',
        ),
      );
      return;
    }

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isRowEmpty(row)) continue;
      final rowNum = r + 1;

      final phone = _normalizePhone(_valueAt(row, cPhone));
      final custName = _valueAt(row, colMap['customerName']);
      final totalVal = _parseDouble(_valueAt(row, cTotal));
      final downVal = _parseDouble(_valueAt(row, colMap['downPayment']));
      final interestPct = _parseDouble(
        _valueAt(row, colMap['interestPercent']),
      );
      final duration = _parseInt(_valueAt(row, cDuration));
      final remainingVal = _parseDouble(_valueAt(row, cRemaining));
      final startDate =
          _parseDate(_valueAt(row, colMap['startDate'])) ?? DateTime.now();
      final statusRaw = _valueAt(row, colMap['status']).toLowerCase();

      if (phone.isEmpty) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.installments,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'هاتف العميل فارغ — لا يمكن ربط عقد التقسيط.',
          ),
        );
        continue;
      }
      if (totalVal <= 0 || downVal < 0 || downVal > totalVal) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.installments,
            sheetName: sheetName,
            rowNumber: rowNum,
            message:
                'إجمالي العقد أو المقدم غير صالح (يجب أن يكون المقدم <= الإجمالي).',
          ),
        );
        continue;
      }
      if (duration < 1 || duration > 120) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.installments,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'عدد الشهور يجب أن يكون بين 1 و 120 شهراً.',
          ),
        );
        continue;
      }
      if (remainingVal < 0) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.installments,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'المبلغ المتبقي لا يمكن أن يكون سالباً.',
          ),
        );
        continue;
      }
      final interestBp = (interestPct * 100).round();
      if (interestBp < 0 || interestBp > 10000) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.installments,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'نسبة الفائدة يجب أن تكون بين 0% و 100%.',
          ),
        );
        continue;
      }

      final remainingPiasters = (remainingVal * 100).round();
      String status = 'active';
      if (statusRaw.contains('ملغ') || statusRaw.contains('cancel')) {
        status = 'cancelled';
      } else if (remainingPiasters == 0 ||
          statusRaw.contains('مكتمل') ||
          statusRaw.contains('complete')) {
        status = 'completed';
      } else if (statusRaw.contains('متأخر') || statusRaw.contains('overdue')) {
        status = 'overdue';
      }

      newInstallments.add(
        MigrationInstallmentRow(
          rowNumber: rowNum,
          customerPhone: phone,
          customerName: custName.isEmpty ? 'عميل $phone' : custName,
          totalPiasters: (totalVal * 100).round(),
          downPaymentPiasters: (downVal * 100).round(),
          interestBp: interestBp,
          durationMonths: duration,
          remainingPiasters: remainingPiasters,
          startDate: startDate,
          status: status,
        ),
      );
    }
  }

  void _parseExpensesSheet({
    required Sheet sheet,
    required String sheetName,
    required Map<String, int?> colMap,
    required List<MigrationExpenseRow> newExpenses,
    required List<ExcelRowIssue> issues,
    bool lenientMode = false,
  }) {
    final cCat = colMap['category'];
    final cAmount = colMap['amount'];
    if (cAmount == null || (cCat == null && !lenientMode)) {
      issues.add(
        ExcelRowIssue(
          entity: ExcelImportEntity.expenses,
          sheetName: sheetName,
          rowNumber: 1,
          message: 'يجب تحديد عمودي «بند المصروف» و«المبلغ».',
        ),
      );
      return;
    }

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isRowEmpty(row)) continue;
      final rowNum = r + 1;

      var category = cCat != null ? _valueAt(row, cCat) : '';
      if (category.isEmpty) {
        if (lenientMode) {
          category = 'مصروفات عامة';
          issues.add(
            ExcelRowIssue(
              entity: ExcelImportEntity.expenses,
              sheetName: sheetName,
              rowNumber: rowNum,
              message: 'بند المصروف فارغ — تم تعيين «مصروفات عامة» تلقائياً.',
              severity: ExcelIssueSeverity.warning,
            ),
          );
        } else {
          issues.add(
            ExcelRowIssue(
              entity: ExcelImportEntity.expenses,
              sheetName: sheetName,
              rowNumber: rowNum,
              message: 'بند المصروف فارغ — تم تخطي الصف.',
            ),
          );
          continue;
        }
      }

      final amountVal = _parseDouble(_valueAt(row, cAmount));
      if (amountVal <= 0) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.expenses,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'مبلغ المصروف يجب أن يكون أكبر من صفر.',
          ),
        );
        continue;
      }

      final parsedDate = _parseDate(_valueAt(row, colMap['expenseDate']));
      if (parsedDate == null && lenientMode) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.expenses,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'تاريخ المصروف غير محدد — تم استخدام تاريخ اليوم.',
            severity: ExcelIssueSeverity.warning,
          ),
        );
      }
      final notes = _valueAt(row, colMap['notes']);

      newExpenses.add(
        MigrationExpenseRow(
          rowNumber: rowNum,
          category: category,
          amountPiasters: (amountVal * 100).round(),
          expenseDate: parsedDate ?? DateTime.now(),
          notes: notes.isEmpty ? null : notes,
        ),
      );
    }
  }

  void _parseHistoricalSalesSheet({
    required Sheet sheet,
    required String sheetName,
    required Map<String, int?> colMap,
    required List<MigrationHistoricalSaleRow> newSales,
    required List<ExcelRowIssue> issues,
    bool lenientMode = false,
  }) {
    final cTotal = colMap['total'];
    if (cTotal == null) {
      issues.add(
        ExcelRowIssue(
          entity: ExcelImportEntity.historicalSales,
          sheetName: sheetName,
          rowNumber: 1,
          message: 'يجب تحديد عمود «إجمالي الفاتورة».',
        ),
      );
      return;
    }

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isRowEmpty(row)) continue;
      final rowNum = r + 1;

      final totalVal = _parseDouble(_valueAt(row, cTotal));
      if (totalVal <= 0) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.historicalSales,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'إجمالي الفاتورة يجب أن يكون أكبر من صفر.',
          ),
        );
        continue;
      }

      var shortRef = _valueAt(row, colMap['shortRef']);
      if (shortRef.isEmpty) {
        shortRef = 'HIST-${_uuid.v4().substring(0, 6).toUpperCase()}';
        if (lenientMode) {
          issues.add(
            ExcelRowIssue(
              entity: ExcelImportEntity.historicalSales,
              sheetName: sheetName,
              rowNumber: rowNum,
              message: 'تم توليد رقم فاتورة مرجعي ($shortRef) تلقائياً.',
              severity: ExcelIssueSeverity.warning,
            ),
          );
        }
      }

      final payRaw = _valueAt(row, colMap['paymentMethod']).toLowerCase();
      final paymentMethod =
          (payRaw.contains('card') ||
              payRaw.contains('فيزا') ||
              payRaw.contains('بطاقة'))
          ? 'card'
          : 'cash';

      final parsedDate = _parseDate(_valueAt(row, colMap['date']));
      if (parsedDate == null && lenientMode) {
        issues.add(
          ExcelRowIssue(
            entity: ExcelImportEntity.historicalSales,
            sheetName: sheetName,
            rowNumber: rowNum,
            message: 'تاريخ الفاتورة مفقود — تم استخدام تاريخ اليوم.',
            severity: ExcelIssueSeverity.warning,
          ),
        );
      }
      final custName = _valueAt(row, colMap['customerName']);

      newSales.add(
        MigrationHistoricalSaleRow(
          rowNumber: rowNum,
          shortRef: shortRef,
          totalPiasters: (totalVal * 100).round(),
          paymentMethod: paymentMethod,
          date: parsedDate ?? DateTime.now(),
          customerName: custName.isEmpty ? null : custName,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. ATOMIC TRANSACTIONAL COMMIT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Commits a reviewed [WorkbookImportPreview] inside a single SQLite
  /// transaction preserving all foreign keys, CHECK constraints, and audit logs.
  Future<WorkbookImportResult> executeWorkbookImport({
    required WorkbookImportPreview preview,
    required String userId,
    String? defaultActivityType,
  }) async {
    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final resolvedActivityType = await _resolveDefaultActivityType(
      defaultActivityType,
    );

    int productsAdded = 0;
    int productsUpdated = 0;
    int productsSkipped = 0;
    int customersAdded = 0;
    int customersUpdated = 0;
    int customersSkipped = 0;
    int suppliersAdded = 0;
    int suppliersUpdated = 0;
    int suppliersSkipped = 0;
    int installmentsAdded = 0;

    await _db.transaction(() async {
      // ── 1. Categories & Products Cache ───────────────────────────────────
      final existingCats = await (_db.select(
        _db.categories,
      )..where((c) => c.deletedAt.isNull())).get();
      final catByName = {
        for (final c in existingCats) c.name.trim().toLowerCase(): c.id,
      };

      final existingProds = await (_db.select(
        _db.products,
      )..where((p) => p.deletedAt.isNull())).get();
      final prodByKey = {
        for (final p in existingProds)
          '${p.name.trim().toLowerCase()}||${p.categoryId}': p.id,
      };

      Future<String> getOrCreateCategory(String name) async {
        final key = name.trim().toLowerCase();
        final cached = catByName[key];
        if (cached != null) return cached;
        final id = _uuid.v4();
        await _db
            .into(_db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: id,
                branchId: branchId,
                name: name.trim(),
                createdAt: now,
                updatedAt: now,
              ),
            );
        catByName[key] = id;
        return id;
      }

      Future<String> getOrCreateProduct(
        String name,
        String categoryId,
        int minStock,
      ) async {
        final key = '${name.trim().toLowerCase()}||$categoryId';
        final cached = prodByKey[key];
        if (cached != null) return cached;
        final id = _uuid.v4();
        await _db
            .into(_db.products)
            .insert(
              ProductsCompanion.insert(
                id: id,
                branchId: branchId,
                name: name.trim(),
                categoryId: categoryId,
                activityType: drift.Value(resolvedActivityType),
                minStock: drift.Value(minStock),
                createdAt: now,
                updatedAt: now,
              ),
            );
        prodByKey[key] = id;
        return id;
      }

      // ── 2. Insert New Products & Variants ────────────────────────────────
      for (final row in preview.newProducts) {
        final catId = await getOrCreateCategory(row.categoryName);
        final prodId = await getOrCreateProduct(
          row.productName,
          catId,
          row.minStock,
        );
        final variantId = _uuid.v4();

        await _db
            .into(_db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                id: variantId,
                branchId: branchId,
                productId: prodId,
                sku: row.sku,
                color: row.color,
                size: row.size,
                quantity: drift.Value(row.quantity),
                costPrice: row.costPricePiasters,
                sellPrice: row.sellPricePiasters,
                wholesalePrice: drift.Value(row.wholesalePricePiasters),
                createdAt: now,
                updatedAt: now,
              ),
            );

        if (row.quantity > 0) {
          await _db
              .into(_db.inventoryLogs)
              .insert(
                InventoryLogsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  variantId: variantId,
                  type: 'in',
                  qtyDelta: row.quantity,
                  refType: 'excel_migration',
                  reason: const drift.Value('استيراد ونقل بيانات من إكسيل'),
                  userId: userId,
                  createdAt: now,
                ),
              );
        }
        productsAdded++;
      }

      // ── 3. Resolve Product Conflicts ─────────────────────────────────────
      for (final c in preview.productConflicts) {
        if (c.action == ExcelConflictAction.skip) {
          productsSkipped++;
          continue;
        }
        final newQty = c.action == ExcelConflictAction.addQuantity
            ? c.existingQty + c.row.quantity
            : c.row.quantity;
        final delta = newQty - c.existingQty;

        await (_db.update(
          _db.productVariants,
        )..where((v) => v.id.equals(c.existingVariantId))).write(
          ProductVariantsCompanion(
            costPrice: drift.Value(c.row.costPricePiasters),
            sellPrice: drift.Value(c.row.sellPricePiasters),
            wholesalePrice: drift.Value(c.row.wholesalePricePiasters),
            quantity: drift.Value(newQty),
            updatedAt: drift.Value(now),
          ),
        );

        if (delta != 0) {
          await _db
              .into(_db.inventoryLogs)
              .insert(
                InventoryLogsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  variantId: c.existingVariantId,
                  type: delta > 0 ? 'in' : 'out',
                  qtyDelta: delta,
                  refType: 'excel_migration_update',
                  reason: const drift.Value('تحديث مخزون من استيراد إكسيل'),
                  userId: userId,
                  createdAt: now,
                ),
              );
        }
        productsUpdated++;
      }

      // ── 4. Customers (New + Conflicts) ───────────────────────────────────
      final existingCustomers = await _db.select(_db.customers).get();
      final customerIdByPhone = {
        for (final c in existingCustomers) _normalizePhone(c.phone): c.id,
      };

      for (final row in preview.newCustomers) {
        // Guard against soft-deleted row with same UNIQUE phone
        final existingAny = customerIdByPhone[row.phone];
        if (existingAny != null) {
          await (_db.update(
            _db.customers,
          )..where((c) => c.id.equals(existingAny))).write(
            CustomersCompanion(
              name: drift.Value(row.name),
              customerType: drift.Value(row.customerType),
              discountPercent: drift.Value(row.discountPercent),
              loyaltyPoints: drift.Value(row.loyaltyPoints),
              deletedAt: const drift.Value(null),
              updatedAt: drift.Value(now),
            ),
          );
          customersUpdated++;
          continue;
        }

        final id = _uuid.v4();
        await _db
            .into(_db.customers)
            .insert(
              CustomersCompanion.insert(
                id: id,
                branchId: branchId,
                name: row.name,
                phone: row.phone,
                customerType: drift.Value(row.customerType),
                discountPercent: drift.Value(row.discountPercent),
                loyaltyPoints: drift.Value(row.loyaltyPoints),
                createdAt: now,
                updatedAt: now,
              ),
            );
        customerIdByPhone[row.phone] = id;
        customersAdded++;
      }

      for (final c in preview.customerConflicts) {
        if (c.action == ExcelConflictAction.skip) {
          customersSkipped++;
          continue;
        }
        await (_db.update(
          _db.customers,
        )..where((t) => t.id.equals(c.existingCustomerId))).write(
          CustomersCompanion(
            name: drift.Value(c.row.name),
            customerType: drift.Value(c.row.customerType),
            discountPercent: drift.Value(c.row.discountPercent),
            loyaltyPoints: drift.Value(c.row.loyaltyPoints),
            updatedAt: drift.Value(now),
          ),
        );
        customersUpdated++;
      }

      // ── 5. Suppliers (New + Conflicts) ───────────────────────────────────
      for (final row in preview.newSuppliers) {
        await _db
            .into(_db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                name: row.name,
                phone: drift.Value(row.phone),
                companyName: drift.Value(row.companyName),
                address: drift.Value(row.address),
                balance: drift.Value(row.balancePiasters),
                createdAt: now,
                updatedAt: now,
              ),
            );
        suppliersAdded++;
      }

      for (final c in preview.supplierConflicts) {
        if (c.action == ExcelConflictAction.skip) {
          suppliersSkipped++;
          continue;
        }
        await (_db.update(
          _db.suppliers,
        )..where((t) => t.id.equals(c.existingSupplierId))).write(
          SuppliersCompanion(
            phone: drift.Value(c.row.phone),
            companyName: drift.Value(c.row.companyName),
            address: drift.Value(c.row.address),
            balance: drift.Value(c.row.balancePiasters),
            updatedAt: drift.Value(now),
          ),
        );
        suppliersUpdated++;
      }

      // ── 6. Open Installment Contracts (No Phantom Cash Movements) ────────
      for (final row in preview.newInstallments) {
        String? customerId = customerIdByPhone[row.customerPhone];
        if (customerId == null) {
          customerId = _uuid.v4();
          await _db
              .into(_db.customers)
              .insert(
                CustomersCompanion.insert(
                  id: customerId,
                  branchId: branchId,
                  name: row.customerName,
                  phone: row.customerPhone,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          customerIdByPhone[row.customerPhone] = customerId;
          customersAdded++;
        }

        final principal = row.principalPiasters;
        final interestAmount = (principal * row.interestBp / 10000).round();
        final financedTotal = principal + interestAmount;
        final monthlyAmount = (financedTotal / row.durationMonths).round();
        final endDate = InstallmentCalculator.addMonths(
          row.startDate,
          row.durationMonths,
        );
        final contractId = _uuid.v4();

        await _db
            .into(_db.customerInstallments)
            .insert(
              CustomerInstallmentsCompanion.insert(
                id: contractId,
                branchId: branchId,
                saleId:
                    row.referenceCode ??
                    'MIGRATED_EXCEL_${contractId.substring(0, 8).toUpperCase()}',
                customerId: customerId,
                totalPiasters: row.totalPiasters,
                downPaymentPiasters: drift.Value(row.downPaymentPiasters),
                principalPiasters: principal,
                interestBp: row.interestBp,
                monthlyAmountPiasters: monthlyAmount,
                remainingPiasters: row.remainingPiasters,
                durationMonths: row.durationMonths,
                startDate: row.startDate,
                endDate: endDate,
                status: drift.Value(row.status),
                createdBy: userId,
                createdAt: now,
                updatedAt: now,
              ),
            );
        installmentsAdded++;
      }

      // 5. Expenses
      for (final row in preview.newExpenses) {
        await _db
            .into(_db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                category: row.category,
                amount: row.amountPiasters,
                note: drift.Value(row.notes),
                expenseDate: row.expenseDate,
                userId: userId,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // 6. Historical Sales
      for (final row in preview.newHistoricalSales) {
        await _db
            .into(_db.sales)
            .insert(
              SalesCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                shortRef: row.shortRef,
                cashierId: userId,
                subtotal: row.totalPiasters,
                discountType: 'none',
                total: row.totalPiasters,
                paymentMethod: row.paymentMethod,
                note: drift.Value(
                  row.customerName != null
                      ? 'مبيعات سابقة مستوردة - ${row.customerName}'
                      : 'مبيعات سابقة مستوردة',
                ),
                date: row.date,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });

    final expensesAdded = preview.newExpenses.length;
    final historicalSalesAdded = preview.newHistoricalSales.length;

    // Audit log + sync queue entry via TxWriter
    await _txWriter.write(
      writeFn: () async {},
      branchId: branchId,
      entity: 'excel_migration',
      entityId: 'workbook_import',
      operation: 'import',
      userId: userId,
      payload: jsonEncode({
        'productsAdded': productsAdded,
        'productsUpdated': productsUpdated,
        'customersAdded': customersAdded,
        'customersUpdated': customersUpdated,
        'suppliersAdded': suppliersAdded,
        'suppliersUpdated': suppliersUpdated,
        'installmentsAdded': installmentsAdded,
        'expensesAdded': expensesAdded,
        'historicalSalesAdded': historicalSalesAdded,
      }),
    );

    return WorkbookImportResult(
      productsAdded: productsAdded,
      productsUpdated: productsUpdated,
      productsSkipped: productsSkipped,
      customersAdded: customersAdded,
      customersUpdated: customersUpdated,
      customersSkipped: customersSkipped,
      suppliersAdded: suppliersAdded,
      suppliersUpdated: suppliersUpdated,
      suppliersSkipped: suppliersSkipped,
      installmentsAdded: installmentsAdded,
      expensesAdded: expensesAdded,
      historicalSalesAdded: historicalSalesAdded,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<PartnerEntity>> _loadPartners() async {
    try {
      final row = await (_db.select(
        _db.appMeta,
      )..where((t) => t.key.equals('partners_registry'))).getSingleOrNull();
      if (row == null || row.value.trim().isEmpty) return const [];
      final decoded = jsonDecode(row.value) as List<dynamic>;
      return decoded
          .map((e) => PartnerEntity.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _saveFile(
    Uint8List bytes,
    String defaultFileName,
    String dialogTitle,
  ) async {
    String? outputPath;
    bool pickerErrored = false;
    try {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
    } catch (_) {
      pickerErrored = true;
    }

    if (outputPath == null && !pickerErrored) {
      // User intentionally cancelled the save dialog
      return null;
    }
    if (outputPath == null) {
      final dir = await getApplicationDocumentsDirectory();
      outputPath = '${dir.path}/$defaultFileName';
    }
    if (!outputPath.toLowerCase().endsWith('.xlsx')) {
      outputPath = '$outputPath.xlsx';
    }
    final file = File(outputPath);
    await file.writeAsBytes(bytes, flush: true);
    return outputPath;
  }

  ExcelImportEntity? _detectEntityFromSheet(
    String sheetName,
    List<String> headers,
  ) {
    final s = _normalizeHeader(sheetName);
    if (_matchesAny(s, [
      'منتج',
      'مخزون',
      'اصناف',
      'أصناف',
      'product',
      'inventory',
      'stock',
    ])) {
      return ExcelImportEntity.products;
    }
    if (_matchesAny(s, ['عملاء', 'عميل', 'زبائن', 'customer', 'client'])) {
      return ExcelImportEntity.customers;
    }
    if (_matchesAny(s, ['مورد', 'supplier', 'vendor'])) {
      return ExcelImportEntity.suppliers;
    }
    if (_matchesAny(s, ['تقسيط', 'اقساط', 'أقساط', 'installment']) &&
        !_matchesAny(s, ['دفعات', 'payment'])) {
      return ExcelImportEntity.installments;
    }
    if (_matchesAny(s, ['مصروف', 'مصاريف', 'expense'])) {
      return ExcelImportEntity.expenses;
    }
    if (_matchesAny(s, ['مبيعات', 'فواتير', 'sales', 'invoice'])) {
      return ExcelImportEntity.historicalSales;
    }

    // Fallback: inspect headers for arbitrary single-sheet shop files
    final joined = headers.map(_normalizeHeader).join(' ');
    if (_matchesAny(joined, [
      'sku',
      'مقاس',
      'تكلفة',
      'سعر البيع',
      'سعر الجملة',
    ])) {
      return ExcelImportEntity.products;
    }
    if (_matchesAny(joined, ['عدد الشهور', 'القسط', 'المقدم']) &&
        _matchesAny(joined, ['متبقي', 'فائدة'])) {
      return ExcelImportEntity.installments;
    }
    if (_matchesAny(joined, ['شركة', 'مصنع', 'رصيد مستحق', 'مورد'])) {
      return ExcelImportEntity.suppliers;
    }
    if (_matchesAny(joined, ['هاتف', 'موبايل', 'phone']) &&
        _matchesAny(joined, ['عميل', 'نقاط', 'خصم'])) {
      return ExcelImportEntity.customers;
    }
    return null;
  }

  CellStyle _headerStyle() => ExcelStyleHelper.headerStyle();

  CellStyle _accentHeaderStyle() => ExcelStyleHelper.accentHeaderStyle();

  CellStyle _highlightRowStyle() =>
      ExcelStyleHelper.highlightRowStyle(isCurrency: true);

  void _appendStyledHeader(Sheet sheet, List<String> titles, CellStyle style) {
    ExcelStyleHelper.appendStyledHeader(sheet, titles, style: style);
  }

  void _styleRow(Sheet sheet, int rowIndex, int colCount, CellStyle style) {
    ExcelStyleHelper.styleRow(sheet, rowIndex, colCount, style);
  }

  void _setColumnWidths(Sheet sheet, List<double> widths) {
    ExcelStyleHelper.setColumnWidths(sheet, widths);
  }

  String _valueAt(List<Data?> row, int? colIndex) {
    if (colIndex == null || colIndex < 0 || colIndex >= row.length) return '';
    return _cellText(row[colIndex]);
  }

  bool _isRowEmpty(List<Data?> row) {
    if (row.every((c) => _cellText(c).isEmpty)) return true;
    final firstCell = _cellText(row.firstOrNull);
    return firstCell.startsWith('الإجمالي');
  }

  String _cellText(Data? data) {
    final val = data?.value;
    if (val == null) return '';
    return switch (val) {
      TextCellValue() => val.value.toString().trim(),
      IntCellValue() => val.value.toString(),
      DoubleCellValue() => val.value.toString(),
      BoolCellValue() => val.value.toString(),
      DateCellValue() =>
        '${val.year.toString().padLeft(4, '0')}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}',
      DateTimeCellValue() =>
        '${val.year.toString().padLeft(4, '0')}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}',
      FormulaCellValue() => val.formula.trim(),
      _ => val.toString().trim(),
    };
  }

  String _normalizeHeader(String text) {
    return _toWesternDigits(text)
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesAny(String normalized, List<String> keywords) {
    for (final k in keywords) {
      if (normalized.contains(_normalizeHeader(k))) return true;
    }
    return false;
  }

  String _toWesternDigits(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      final aIdx = arabic.indexOf(ch);
      if (aIdx != -1) {
        buf.write(aIdx);
      } else {
        final pIdx = persian.indexOf(ch);
        if (pIdx != -1) {
          buf.write(pIdx);
        } else {
          buf.write(ch);
        }
      }
    }
    return buf.toString();
  }

  String _normalizePhone(String raw) {
    final cleaned = _toWesternDigits(raw).replaceAll(RegExp(r'[\s\-\(\)]'), '');
    return cleaned.trim();
  }

  double _parseDouble(String raw) {
    final cleaned = _toWesternDigits(
      raw,
    ).replaceAll(',', '').replaceAll('ج.م', '').replaceAll('%', '').trim();
    if (cleaned.isEmpty) return 0.0;
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseInt(String raw, {int fallback = 0}) {
    final cleaned = _toWesternDigits(raw).replaceAll(',', '').trim();
    if (cleaned.isEmpty) return fallback;
    final asInt = int.tryParse(cleaned);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(cleaned);
    if (asDouble != null) return asDouble.round();
    return fallback;
  }

  DateTime? _parseDate(String raw) {
    final cleaned = _toWesternDigits(raw).trim();
    if (cleaned.isEmpty) return null;
    final iso = DateTime.tryParse(cleaned);
    if (iso != null) return iso;
    // Support DD/MM/YYYY or YYYY/MM/DD
    final parts = cleaned.split(RegExp(r'[/\-]'));
    if (parts.length == 3) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      final c = int.tryParse(parts[2]);
      if (a != null && b != null && c != null) {
        if (a > 1900) return DateTime(a, b, c);
        if (c > 1900) return DateTime(c, b, a);
      }
    }
    return null;
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime d) {
    final l = d.toLocal();
    return '${_formatDate(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _formatPaymentMethod(String m) {
    switch (m) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
        return 'فيزا / بطاقة';
      case 'installment':
        return 'تقسيط';
      case 'mixed':
        return 'مختلط';
      default:
        return m;
    }
  }

  String _formatInstallmentStatus(String s) {
    switch (s) {
      case 'active':
        return 'نشط';
      case 'completed':
        return 'مكتمل';
      case 'overdue':
        return 'متأخر';
      case 'cancelled':
        return 'ملغي';
      default:
        return s;
    }
  }

  String _formatPurchaseStatus(String s) {
    switch (s) {
      case 'received':
        return 'مستلمة';
      case 'cancelled':
        return 'ملغاة';
      default:
        return 'قيد الانتظار';
    }
  }

  String _formatPaymentStatus(String s) {
    switch (s) {
      case 'paid':
        return 'مدفوعة';
      case 'partial':
        return 'مدفوعة جزئياً';
      default:
        return 'غير مدفوعة';
    }
  }
}
