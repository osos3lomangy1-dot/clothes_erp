import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/services/local_backup_service.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/services/cashier_permissions_service.dart';
import '../../../invoices/data/services/receipt_settings_service.dart';

enum AssistantActionRoute {
  reports,
  products,
  purchases,
  installments,
  expenses,
  settings,
  employees,
  shifts,
  partners,
  excelMigration,
  receiptCustomizer,
  returns,
}

enum AssistantCommandKind {
  toggleBlindShiftClosing,
  toggleManagerPinProtection,
  toggleAllowManualDiscount,
  toggleAutoBackup,
  updateStoreName,
  updateStorePhone,
  recordPurchase,
  addProduct,
  updateProductPriceOrStock,
  recordExpense,
  paySupplier,
  addCustomer,
  collectInstallment,
}

class AssistantPendingCommand {
  final AssistantCommandKind kind;
  final String title;
  final String description;
  final bool? boolValue;
  final String? stringValue;
  final bool touchesFeatureGate;
  final Map<String, dynamic> payload;

  const AssistantPendingCommand({
    required this.kind,
    required this.title,
    required this.description,
    this.boolValue,
    this.stringValue,
    this.touchesFeatureGate = false,
    this.payload = const {},
  });
}

class AssistantActionDraft {
  final AssistantCommandKind kind;
  final Map<String, dynamic> fields;
  final String? missingField;
  final String? promptForMissing;

  const AssistantActionDraft({
    required this.kind,
    this.fields = const {},
    this.missingField,
    this.promptForMissing,
  });

  bool get isComplete => missingField == null;
}

class AssistantTurnResult {
  final List<AssistantInsight> insights;
  final AssistantActionDraft? activeDraft;

  const AssistantTurnResult({
    required this.insights,
    this.activeDraft,
  });
}

class AssistantInsight {
  final String id;
  final String title;
  final String summary;
  final List<String> details;
  final bool isAlert;
  final String? actionLabel;
  final AssistantActionRoute? actionRoute;
  final String? requiredFeatureKey;
  final AssistantPendingCommand? pendingCommand;
  final List<String> followUpPrompts;

  const AssistantInsight({
    required this.id,
    required this.title,
    required this.summary,
    this.details = const [],
    this.isAlert = false,
    this.actionLabel,
    this.actionRoute,
    this.requiredFeatureKey,
    this.pendingCommand,
    this.followUpPrompts = const [],
  });
}

@lazySingleton
class OfflineSmartAssistantService {
  final AppDatabase _db;

  OfflineSmartAssistantService(this._db);

  /// Normalizes Arabic characters (`أ/إ/آ -> ا`, `ة -> ه`, `ى -> ي`),
  /// strips diacritics, converts Arabic-Indic digits, and collapses spaces.
  static String normalizeArabic(String input) {
    var s = Money.normalizeDigits(input).toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  Future<int> _computeNetProfitForRange(DateTime start, DateTime end) async {
    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(start) &
              s.date.isSmallerOrEqualValue(end) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final totalSales = salesRows.fold<int>(0, (s, r) => s + r.total);

    int totalCost = 0;
    if (salesRows.isNotEmpty) {
      final saleIds = salesRows.map((s) => s.id).toList();
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleId.isIn(saleIds)))
          .get();
      totalCost = items.fold<int>(0, (s, i) => s + (i.costSnapshot * i.qty));
    }

    final expensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(start) &
              e.expenseDate.isSmallerOrEqualValue(end) &
              e.deletedAt.isNull()))
        .get();
    final totalExpenses = expensesRows.fold<int>(0, (s, e) => s + e.amount);

    final walletRows = await (_db.select(_db.walletTransactions)
          ..where((w) =>
              w.type.isNotValue('topup_from_drawer') &
              w.createdAt.isBiggerOrEqualValue(start) &
              w.createdAt.isSmallerOrEqualValue(end) &
              w.deletedAt.isNull()))
        .get();
    final walletProfit = walletRows.fold<int>(0, (s, w) => s + w.commission);

    final repairRows = await (_db.select(_db.repairTickets)
          ..where((r) =>
              r.status.equals('delivered') &
              r.deliveredAt.isBiggerOrEqualValue(start) &
              r.deliveredAt.isSmallerOrEqualValue(end) &
              r.deletedAt.isNull()))
        .get();
    final repairProfit = repairRows.fold<int>(
      0,
      (s, r) => s + (r.finalCost - r.partsCost),
    );

    return totalSales - totalCost - totalExpenses + walletProfit + repairProfit;
  }

  Future<AssistantInsight> getTodayProfitInsight() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final yStart = start.subtract(const Duration(days: 1));
    final yEnd = end.subtract(const Duration(days: 1));

    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(start) &
              s.date.isSmallerOrEqualValue(end) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final totalSales = salesRows.fold<int>(0, (s, r) => s + r.total);

    int totalCost = 0;
    if (salesRows.isNotEmpty) {
      final saleIds = salesRows.map((s) => s.id).toList();
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleId.isIn(saleIds)))
          .get();
      totalCost = items.fold<int>(0, (s, i) => s + (i.costSnapshot * i.qty));
    }

    final expensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(start) &
              e.expenseDate.isSmallerOrEqualValue(end) &
              e.deletedAt.isNull()))
        .get();
    final totalExpenses = expensesRows.fold<int>(0, (s, e) => s + e.amount);

    final netProfit = await _computeNetProfitForRange(start, end);
    final yesterdayProfit = await _computeNetProfitForRange(yStart, yEnd);
    final diff = netProfit - yesterdayProfit;
    final cmpLabel = diff > 0
        ? 'أعلى من أمس بمقدار +${Money(diff).toDisplay()} ج.م'
        : (diff < 0
            ? 'أقل من أمس بمقدار ${Money(diff.abs()).toDisplay()} ج.م'
            : 'مساوٍ لصافي ربح أمس');

    return AssistantInsight(
      id: 'today_profit',
      title: 'صافي ربح اليوم ومقارنته بأمس',
      summary: '${Money(netProfit).toDisplay()} ج.م',
      details: [
        cmpLabel,
        'إجمالي المبيعات: ${Money(totalSales).toDisplay()} ج.م (${salesRows.length} فاتورة)',
        'تكلفة البضاعة: ${Money(totalCost).toDisplay()} ج.م | مصروفات اليوم: ${Money(totalExpenses).toDisplay()} ج.م',
        'صافي ربح أمس: ${Money(yesterdayProfit).toDisplay()} ج.م',
      ],
      isAlert: netProfit < 0,
      actionLabel: 'التقرير المالي الشامل',
      actionRoute: AssistantActionRoute.reports,
      requiredFeatureKey: FeatureKeys.reports,
    );
  }

  /// Diagnoses sales changes by comparing invoice count, AOV, return rate,
  /// and discount rate between the last 7 days and the prior 7 days.
  Future<AssistantInsight> getSalesDiagnosisInsight() async {
    final now = DateTime.now();
    final curStart = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final curEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final prevStart = curStart.subtract(const Duration(days: 7));
    final prevEnd = curStart.subtract(const Duration(milliseconds: 1));

    Future<({int count, int revenue, int discounts, int returns})> loadPeriod(
      DateTime s,
      DateTime e,
    ) async {
      final sales = await (_db.select(_db.sales)
            ..where((r) =>
                r.date.isBiggerOrEqualValue(s) &
                r.date.isSmallerOrEqualValue(e) &
                r.deletedAt.isNull() &
                r.status.isNotValue('cancelled')))
          .get();
      final rets = await (_db.select(_db.returns)
            ..where((r) =>
                r.date.isBiggerOrEqualValue(s) &
                r.date.isSmallerOrEqualValue(e) &
                r.deletedAt.isNull()))
          .get();
      return (
        count: sales.length,
        revenue: sales.fold<int>(0, (sum, r) => sum + r.total),
        discounts: sales.fold<int>(0, (sum, r) => sum + r.discountValue),
        returns: rets.fold<int>(0, (sum, r) => sum + r.refundAmount),
      );
    }

    final cur = await loadPeriod(curStart, curEnd);
    final prev = await loadPeriod(prevStart, prevEnd);

    final curAov = cur.count > 0 ? cur.revenue ~/ cur.count : 0;
    final prevAov = prev.count > 0 ? prev.revenue ~/ prev.count : 0;
    final curRetPct =
        cur.revenue > 0 ? ((cur.returns / cur.revenue) * 100).toStringAsFixed(1) : '0.0';
    final curDiscPct = (cur.revenue + cur.discounts) > 0
        ? ((cur.discounts / (cur.revenue + cur.discounts)) * 100).toStringAsFixed(1)
        : '0.0';

    final diagnosis = cur.count < prev.count
        ? 'انخفض عدد الفواتير من ${prev.count} إلى ${cur.count} فاتورة.'
        : (curAov < prevAov
            ? 'انخفض متوسط قيمة الفاتورة من ${Money(prevAov).toDisplay()} إلى ${Money(curAov).toDisplay()} ج.م.'
            : 'الأداء مستقر أو أفضل مقارنة بالفترة السابقة.');

    return AssistantInsight(
      id: 'sales_diagnosis',
      title: 'تشخيص تغير المبيعات (آخر 7 أيام مقابل السابقة)',
      summary: diagnosis,
      details: [
        'إجمالي الفترة الحالية: ${Money(cur.revenue).toDisplay()} ج.م (${cur.count} فاتورة) | السابقة: ${Money(prev.revenue).toDisplay()} ج.م (${prev.count} فاتورة)',
        'متوسط الفاتورة (AOV): ${Money(curAov).toDisplay()} ج.م (السابق: ${Money(prevAov).toDisplay()} ج.م)',
        'نسبة المرتجعات: $curRetPct% (${Money(cur.returns).toDisplay()} ج.م)',
        'نسبة الخصومات: $curDiscPct% (${Money(cur.discounts).toDisplay()} ج.م)',
      ],
      isAlert: cur.revenue < prev.revenue,
      actionLabel: 'فتح التقارير التحليلية',
      actionRoute: AssistantActionRoute.reports,
      requiredFeatureKey: FeatureKeys.reports,
    );
  }

  /// Recommends stagnant high-stock products with good profit margins for promotions.
  Future<AssistantInsight> getPromotionsAdvisorInsight() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentSales = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
    ])
          ..where(
            _db.sales.date.isBiggerOrEqualValue(since) &
                _db.sales.deletedAt.isNull() &
                _db.sales.status.isNotValue('cancelled'),
          ))
        .get();
    final soldIds =
        recentSales.map((r) => r.readTable(_db.saleItems).variantId).toSet();

    final stockRows = await (_db.select(_db.productVariants).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])
          ..where(
            _db.productVariants.deletedAt.isNull() &
                _db.products.deletedAt.isNull() &
                _db.productVariants.quantity.isBiggerOrEqualValue(3),
          ))
        .get();

    final candidates = <({String label, int marginPct, int qty})>[];
    for (final r in stockRows) {
      final v = r.readTable(_db.productVariants);
      final p = r.readTable(_db.products);
      if (soldIds.contains(v.id)) continue;
      if (v.sellPrice <= 0 || v.sellPrice <= v.costPrice) continue;
      final marginPct = (((v.sellPrice - v.costPrice) / v.sellPrice) * 100).round();
      if (marginPct >= 20) {
        candidates.add((
          label: '${p.name} (${v.size}) — رصيد ${v.quantity} | هامش $marginPct% | بيع ${Money(v.sellPrice).toDisplay()} ج.م',
          marginPct: marginPct,
          qty: v.quantity,
        ));
      }
    }
    candidates.sort((a, b) => b.marginPct.compareTo(a.marginPct));

    return AssistantInsight(
      id: 'promotions_advisor',
      title: 'مستشار العروض وتصريف البضاعة',
      summary: candidates.isEmpty
          ? 'لا توجد أصناف راكدة ذات مخزون مرتفع وهامش ربح >= 20% حالياً'
          : 'نقترح عمل خصم 10%-15% على ${candidates.length} صنف راكد بهامش ربح جيد',
      details: candidates.take(6).map((c) => c.label).toList(),
      actionLabel: 'إدارة المنتجات والأسعار',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  /// Unified Store Pulse: today sales, net profit, expenses, open drawer cash,
  /// critical low stock, and overdue installments.
  Future<AssistantInsight> getStorePulseInsight() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(start) &
              s.date.isSmallerOrEqualValue(end) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final todaySales = salesRows.fold<int>(0, (s, r) => s + r.total);

    final expensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(start) &
              e.expenseDate.isSmallerOrEqualValue(end) &
              e.deletedAt.isNull()))
        .get();
    final todayExpenses = expensesRows.fold<int>(0, (s, e) => s + e.amount);
    final netProfit = await _computeNetProfitForRange(start, end);

    final openShift = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();
    int? expectedDrawer;
    if (openShift != null) {
      final movements = await (_db.select(_db.cashMovements)
            ..where((m) =>
                m.shiftId.equals(openShift.id) &
                m.method.equals('cash') &
                m.deletedAt.isNull()))
          .get();
      final cashIn = movements
          .where((m) => m.direction == 'in')
          .fold<int>(0, (s, m) => s + m.amountPiasters);
      final cashOut = movements
          .where((m) => m.direction == 'out')
          .fold<int>(0, (s, m) => s + m.amountPiasters);
      expectedDrawer = openShift.openingBalance + cashIn - cashOut;
    }

    final stockout = await getStockoutVelocityInsight();
    final overdue = await getOverdueInstallmentsInsight();

    return AssistantInsight(
      id: 'store_pulse',
      title: 'نبض المحل الفوري الآن',
      summary:
          'مبيعات اليوم: ${Money(todaySales).toDisplay()} ج.م | صافي الربح: ${Money(netProfit).toDisplay()} ج.م',
      details: [
        'مصروفات اليوم: ${Money(todayExpenses).toDisplay()} ج.م',
        expectedDrawer != null
            ? 'رصيد الدرج المتوقع للوردية المفتوحة: ${Money(expectedDrawer).toDisplay()} ج.م'
            : 'لا توجد وردية مفتوحة حالياً',
        'النواقص الحرجة: ${stockout.summary}',
        'الأقساط المتأخرة: ${overdue.summary}',
      ],
      isAlert: stockout.isAlert || overdue.isAlert,
      actionLabel: 'التقرير المالي الشامل',
      actionRoute: AssistantActionRoute.reports,
      requiredFeatureKey: FeatureKeys.reports,
    );
  }

  Future<AssistantInsight> getTopProfitableProductsInsight() async {
    final rows = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
      innerJoin(
        _db.productVariants,
        _db.productVariants.id.equalsExp(_db.saleItems.variantId),
      ),
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])
          ..where(
            _db.sales.deletedAt.isNull() &
                _db.sales.status.isNotValue('cancelled'),
          ))
        .get();

    final Map<String, ({String name, int profit, int qty})> map = {};
    for (final r in rows) {
      final si = r.readTable(_db.saleItems);
      final p = r.readTable(_db.products);
      final v = r.readTable(_db.productVariants);
      final unitCost = v.costPrice > 0 ? v.costPrice : si.costSnapshot;
      final profit = (si.priceSnapshot - unitCost) * si.qty;
      final prev = map[v.id];
      map[v.id] = (
        name: '${p.name} (${v.size})',
        profit: (prev?.profit ?? 0) + profit,
        qty: (prev?.qty ?? 0) + si.qty,
      );
    }

    final sorted = map.values.toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));
    final top5 = sorted.take(5).toList();

    return AssistantInsight(
      id: 'top_products',
      title: 'أعلى 5 أصناف ربحاً',
      summary: top5.isEmpty
          ? 'لا توجد مبيعات مسجلة بعد'
          : 'الأعلى: ${top5.first.name} (${Money(top5.first.profit).toDisplay()} ج.م)',
      details: [
        for (var i = 0; i < top5.length; i++)
          '${i + 1}. ${top5[i].name} — ربح ${Money(top5[i].profit).toDisplay()} ج.م (${top5[i].qty} قطعة)',
      ],
      actionLabel: 'فتح التقارير',
      actionRoute: AssistantActionRoute.reports,
      requiredFeatureKey: FeatureKeys.reports,
    );
  }

  Future<AssistantInsight> getStagnantProductsInsight() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentSales = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
    ])
          ..where(
            _db.sales.date.isBiggerOrEqualValue(since) &
                _db.sales.deletedAt.isNull() &
                _db.sales.status.isNotValue('cancelled'),
          ))
        .get();
    final soldVariantIds =
        recentSales.map((r) => r.readTable(_db.saleItems).variantId).toSet();

    final stockRows = await (_db.select(_db.productVariants).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])
          ..where(
            _db.productVariants.deletedAt.isNull() &
                _db.products.deletedAt.isNull() &
                _db.productVariants.quantity.isBiggerThanValue(0),
          ))
        .get();

    final stagnant = <String>[];
    for (final r in stockRows) {
      final v = r.readTable(_db.productVariants);
      final p = r.readTable(_db.products);
      if (!soldVariantIds.contains(v.id)) {
        stagnant.add('${p.name} (${v.size}) — متاح: ${v.quantity}');
      }
    }

    return AssistantInsight(
      id: 'stagnant_products',
      title: 'الأصناف الراكدة (آخر 30 يوماً)',
      summary: stagnant.isEmpty
          ? 'جميع الأصناف المتوفرة تحركت خلال آخر 30 يوماً'
          : '${stagnant.length} صنف لم يُبع خلال آخر 30 يوماً',
      details: stagnant.take(8).toList(),
      isAlert: stagnant.isNotEmpty,
      actionLabel: 'إدارة المنتجات',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  Future<AssistantInsight> getStockoutVelocityInsight() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentSales = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
    ])
          ..where(
            _db.sales.date.isBiggerOrEqualValue(since) &
                _db.sales.deletedAt.isNull() &
                _db.sales.status.isNotValue('cancelled'),
          ))
        .get();

    final Map<String, int> qtySold30d = {};
    for (final r in recentSales) {
      final si = r.readTable(_db.saleItems);
      qtySold30d[si.variantId] = (qtySold30d[si.variantId] ?? 0) + si.qty;
    }

    final stockRows = await (_db.select(_db.productVariants).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])
          ..where(
            _db.productVariants.deletedAt.isNull() &
                _db.products.deletedAt.isNull(),
          ))
        .get();

    final alerts = <String>[];
    for (final r in stockRows) {
      final v = r.readTable(_db.productVariants);
      final p = r.readTable(_db.products);
      final sold = qtySold30d[v.id] ?? 0;
      final dailyRate = sold / 30.0;
      final daysLeft = dailyRate > 0 ? (v.quantity / dailyRate).floor() : 999;

      if (v.quantity <= p.minStock || (dailyRate > 0 && daysLeft <= 7)) {
        final msg = dailyRate > 0
            ? '${p.name}: متبقي ${v.quantity} (يكفي ~$daysLeft يوم)'
            : '${p.name}: متبقي ${v.quantity} (أقل من حد الطلب ${p.minStock})';
        alerts.add(msg);
      }
    }

    return AssistantInsight(
      id: 'stockout_alerts',
      title: 'توقع نفاد المخزون ومعدل البيع اليومي',
      summary: alerts.isEmpty
          ? 'مستويات المخزون آمنة حالياً'
          : '${alerts.length} صنف بحاجة لإعادة طلب قريباً',
      details: alerts.take(8).toList(),
      isAlert: alerts.isNotEmpty,
      actionLabel: 'فتح قائمة المنتجات',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  Future<AssistantInsight> getMonthlyBudgetComparisonInsight() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final expensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(monthStart) &
              e.expenseDate.isSmallerOrEqualValue(now) &
              e.deletedAt.isNull()))
        .get();
    final spentPiasters = expensesRows.fold<int>(0, (s, e) => s + e.amount);

    final budgetRow = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('finance.monthly_expense_budget')))
        .getSingleOrNull();
    final budgetPiasters = int.tryParse(budgetRow?.value ?? '') ?? 0;

    if (budgetPiasters <= 0) {
      return AssistantInsight(
        id: 'budget_comparison',
        title: 'مقارنة مصاريف الشهر بالميزانية',
        summary: 'مصروفات الشهر الحالي: ${Money(spentPiasters).toDisplay()} ج.م',
        details: const [
          'لم يتم تحديد ميزانية شهرية بعد — يمكنك ضبطها من استبيان الوضع المالي.',
        ],
        actionLabel: 'عرض المصروفات',
        actionRoute: AssistantActionRoute.expenses,
        requiredFeatureKey: FeatureKeys.expenses,
      );
    }

    final pct = ((spentPiasters / budgetPiasters) * 100).round();
    final remaining = budgetPiasters - spentPiasters;
    return AssistantInsight(
      id: 'budget_comparison',
      title: 'مقارنة مصاريف الشهر بالميزانية',
      summary: 'صُرف $pct% من الميزانية (${Money(spentPiasters).toDisplay()} / ${Money(budgetPiasters).toDisplay()} ج.م)',
      details: [
        remaining >= 0
            ? 'المتبقي من الميزانية: ${Money(remaining).toDisplay()} ج.م'
            : 'تجاوز للميزانية بمقدار: ${Money(remaining.abs()).toDisplay()} ج.م',
      ],
      isAlert: spentPiasters > budgetPiasters,
      actionLabel: 'إدارة المصروفات',
      actionRoute: AssistantActionRoute.expenses,
      requiredFeatureKey: FeatureKeys.expenses,
    );
  }

  Future<AssistantInsight> getOverdueInstallmentsInsight() async {
    final now = DateTime.now();
    final rows = await (_db.select(_db.customerInstallments)
          ..where(
            (i) =>
                i.deletedAt.isNull() &
                i.remainingPiasters.isBiggerThanValue(0) &
                (i.status.equals('overdue') |
                    (i.status.equals('active') &
                        i.endDate.isSmallerThanValue(now))),
          ))
        .get();

    final totalOverdue =
        rows.fold<int>(0, (s, r) => s + r.remainingPiasters);

    return AssistantInsight(
      id: 'overdue_installments',
      title: 'الأقساط المتأخرة',
      summary: rows.isEmpty
          ? 'لا توجد عقود تقسيط متأخرة'
          : '${rows.length} عقد متأخر بإجمالي ${Money(totalOverdue).toDisplay()} ج.م',
      details: [
        for (final r in rows.take(6))
          'عقد #${r.id.substring(0, r.id.length >= 6 ? 6 : r.id.length)} — متبقي ${Money(r.remainingPiasters).toDisplay()} ج.م',
      ],
      isAlert: rows.isNotEmpty,
      actionLabel: 'إدارة التقسيط',
      actionRoute: AssistantActionRoute.installments,
      requiredFeatureKey: FeatureKeys.installments,
    );
  }

  Future<AssistantInsight> getSuppliersDuesInsight() async {
    final rows = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull() & s.balance.isBiggerThanValue(0))
          ..orderBy([(s) => OrderingTerm.desc(s.balance)]))
        .get();
    final totalDues = rows.fold<int>(0, (s, r) => s + r.balance);

    return AssistantInsight(
      id: 'suppliers_dues',
      title: 'مستحقات الموردين',
      summary: rows.isEmpty
          ? 'لا توجد مستحقات حالية للموردين'
          : 'إجمالي المستحق لـ ${rows.length} مورد: ${Money(totalDues).toDisplay()} ج.م',
      details: [
        for (final s in rows.take(6))
          '${s.name}: ${Money(s.balance).toDisplay()} ج.م',
      ],
      isAlert: totalDues > 0,
      actionLabel: 'الموردين والمشتريات',
      actionRoute: AssistantActionRoute.purchases,
      requiredFeatureKey: FeatureKeys.suppliers,
    );
  }

  Future<AssistantInsight?> searchProductByNameInsight(String rawQuery) async {
    final normQuery = normalizeArabic(rawQuery);
    const stopWords = [
      'سعر',
      'رصيد',
      'ربح',
      'مخزون',
      'كميه',
      'صنف',
      'منتج',
      'بكام',
      'كام',
      'شوف',
      'ابحث',
      'بحث',
      'عن',
      'في',
      'هل',
      'يوجد',
      'عندنا',
      'المنتج',
      'الصنف',
    ];
    var clean = normQuery;
    for (final w in stopWords) {
      clean = clean.replaceAll(RegExp('(^|\\s)$w(\\s|\$)'), ' ');
    }
    clean = clean.trim();
    if (clean.length < 2) return null;

    final rows = await (_db.select(_db.productVariants).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productVariants.productId),
      ),
    ])
          ..where(
            _db.productVariants.deletedAt.isNull() &
                _db.products.deletedAt.isNull(),
          ))
        .get();

    final matches = <String>[];
    String? firstSummary;
    for (final r in rows) {
      final p = r.readTable(_db.products);
      final v = r.readTable(_db.productVariants);
      final normProd = normalizeArabic(p.name);
      final fullName = normalizeArabic('${p.name} ${v.size} ${v.color} ${v.sku}');
      if (fullName.contains(clean) ||
          (normProd.length >= 2 && normQuery.contains(normProd))) {
        final unitProfit = v.sellPrice - v.costPrice;
        firstSummary ??=
            '${p.name} — الرصيد: ${v.quantity} | السعر: ${Money(v.sellPrice).toDisplay()} ج.م | الربح: ${Money(unitProfit).toDisplay()} ج.م';
        matches.add(
          '${p.name} (${v.size} - ${v.color}): متاح ${v.quantity} | بيع ${Money(v.sellPrice).toDisplay()} ج.م | تكلفة ${Money(v.costPrice).toDisplay()} ج.م | ربح القطعة ${Money(unitProfit).toDisplay()} ج.م',
        );
      }
    }

    if (matches.isEmpty) return null;
    return AssistantInsight(
      id: 'product_lookup',
      title: 'نتيجة البحث عن الصنف: $clean',
      summary: firstSummary!,
      details: matches.take(6).toList(),
      actionLabel: 'فتح المنتجات',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  /// Interactive How-To Guide (11 topics) for Arabic & Egyptian colloquial queries.
  AssistantInsight? matchHowToGuide(String rawQuery) {
    final q = normalizeArabic(rawQuery);
    final isQuestion = q.contains('ازاي') ||
        q.contains('كيف') ||
        q.contains('طريقه') ||
        q.contains('اعمل') ||
        q.contains('اغير') ||
        q.contains('اضيف') ||
        q.contains('فين') ||
        q.contains('خطوات');
    if (!isQuestion) return null;

    if (q.contains('اسم المحل') ||
        q.contains('اسم المتجر') ||
        q.contains('الفاتوره') ||
        q.contains('الايصال') ||
        q.contains('الشعار')) {
      return const AssistantInsight(
        id: 'howto_receipt',
        title: 'دليل: تغيير اسم المحل وتخصيص الفاتورة',
        summary: 'يمكنك تعديل اسم المحل وبيانات الإيصال خلال ثوانٍ:',
        details: [
          '1. افتح "تخصيص الفاتورة الحرارية" من الإعدادات أو الزر بالأسفل.',
          '2. عدّل اسم المتجر، رقم الهاتف، العنوان، والرسالة الترحيبية.',
          '3. اضغط حفظ [F12] لتطبيق التغيير فوراً على كل الفواتير.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.receiptCustomizer,
      );
    }

    final isEncyclopediaQuery = q.contains('فرق') ||
        q.contains('باقه') ||
        q.contains('هديه') ||
        q.contains('تضخم') ||
        q.contains('غلاء') ||
        q.contains('استبدال') ||
        q.contains('ترتيب المحل') ||
        q.contains('عرض البضاعه') ||
        q.contains('سيوله') ||
        q.contains('50/30/20');

    if (!isEncyclopediaQuery &&
        (q.contains('خصم') || q.contains('منع الخصم') || q.contains('تعديل السعر'))) {
      return const AssistantInsight(
        id: 'howto_discount_guard',
        title: 'دليل: منع الخصم اليدوي أو تعديل السعر للكاشير',
        summary: 'لحماية الأسعار ومنع الخصومات غير المصرح بها:',
        details: [
          '1. افتح "إعدادات النظام" -> قسم "صلاحيات الكاشير".',
          '2. عطّل خيار "السماح بالخصم اليدوي للكاشير".',
          '3. كما يمكنك تفعيل "حماية المدير بالرقم السري" لاعتماد المرتجعات.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.settings,
      );
    }

    if (q.contains('كاشير') || q.contains('موظف') || q.contains('pin')) {
      return const AssistantInsight(
        id: 'howto_employees',
        title: 'دليل: إضافة كاشير وتعيين رمز PIN',
        summary: 'خطوات إنشاء حساب كاشير للدخول السريع بالـ PIN:',
        details: [
          '1. افتح شاشة "الموظفين والصلاحيات".',
          '2. اضغط "إضافة موظف جديد" واختر الدور (كاشير أو مدير).',
          '3. أدخل رمز PIN من 4 أرقام للدخول السريع واضغط حفظ.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.employees,
        requiredFeatureKey: FeatureKeys.employees,
      );
    }

    if (q.contains('نسخ') || q.contains('احتياطي') || q.contains('باك اب')) {
      return const AssistantInsight(
        id: 'howto_backup',
        title: 'دليل: النسخ الاحتياطي للبيانات',
        summary: 'لأخذ نسخة احتياطية فورية أو تفعيل النسخ التلقائي:',
        details: [
          '1. افتح "إعدادات النظام" -> قسم "النسخ الاحتياطي".',
          '2. اختر مجلد الحفظ وفعّل النسخ التلقائي اليومي وعند الإغلاق.',
          '3. أو اضغط "إنشاء نسخة احتياطية الآن" للحفظ الفوري.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.settings,
      );
    }

    if (q.contains('اكسيل') || q.contains('استيراد') || q.contains('شيت')) {
      return const AssistantInsight(
        id: 'howto_excel',
        title: 'دليل: استيراد البيانات من ملف إكسيل',
        summary: 'لنقل المنتجات والعملاء والأقساط والمصروفات دفعة واحدة:',
        details: [
          '1. افتح "مركز الإكسيل واستيراد البيانات".',
          '2. اختر ملف الإكسيل (يمكنك تفعيل الاستيراد المرن للبيانات الناقصة).',
          '3. راجع المعاينة واضغط "تأكيد وحفظ البيانات".',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.excelMigration,
      );
    }

    if (q.contains('ورديه') || q.contains('تقفيل') || q.contains('الدرج')) {
      return const AssistantInsight(
        id: 'howto_shift',
        title: 'دليل: فتح وتقفيل الوردية ومطابقة الدرج',
        summary: 'لإنهاء الوردية ومطابقة النقدية الفعلية:',
        details: [
          '1. افتح شاشة "الورديات وتصفية الدرج".',
          '2. اضغط "تقفيل الوردية" وأدخل المبلغ الفعلي المعدود في الدرج.',
          '3. راجع العجز/الزيادة واطبع تقرير Z.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.shifts,
        requiredFeatureKey: FeatureKeys.shifts,
      );
    }

    if (q.contains('تقسيط') || q.contains('قسط')) {
      return const AssistantInsight(
        id: 'howto_installments',
        title: 'دليل: البيع بالتقسيط ومتابعة الأقساط',
        summary: 'لتفعيل التقسيط وتحصيل الأقساط الشهرية:',
        details: [
          '1. تأكد من تفعيل ميزة "نظام التقسيط" من إعدادات النظام.',
          '2. عند البيع في الكاشير اختر عميلاً ثم طريقة الدفع "تقسيط".',
          '3. تابع الأقساط المستحقة وسجل السداد من شاشة "التقسيط".',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.installments,
        requiredFeatureKey: FeatureKeys.installments,
      );
    }

    if (q.contains('تعدد') || q.contains('نشاط') || q.contains('متاجر') || q.contains('ميزات')) {
      return const AssistantInsight(
        id: 'howto_presets',
        title: 'دليل: تبديل نشاط المتجر وتعدد الأنشطة',
        summary: 'لتخصيص النظام لملابس، موبايلات، مطاعم، أو أكثر من نشاط:',
        details: [
          '1. افتح "إعدادات النظام" -> "نمط النشاط التجاري والميزات".',
          '2. اختر القالب المناسب أو فعّل/عطّل أي ميزة منفردة.',
          '3. تُعزل الشاشات غير المطلوبة تلقائياً للحفاظ على بساطة الواجهة.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.settings,
      );
    }

    if (q.contains('شريك') || q.contains('شركاء') || q.contains('راس مال')) {
      return const AssistantInsight(
        id: 'howto_partners',
        title: 'دليل: إضافة شريك وتسجيل رأس المال',
        summary: 'لتسجيل حصص الشركاء ومتابعة المسحوبات والأرباح:',
        details: [
          '1. افتح شاشة "الشركاء ورأس المال".',
          '2. اضغط "إضافة شريك" وأدخل الاسم، النسبة %، ورأس المال.',
          '3. تُحسب حصة كل شريك من صافي الربح تلقائياً.',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.partners,
        requiredFeatureKey: FeatureKeys.partners,
      );
    }

    if (!isEncyclopediaQuery &&
        (q.contains('سعر') || q.contains('صنف') || q.contains('منتج'))) {
      return const AssistantInsight(
        id: 'howto_products',
        title: 'دليل: إضافة صنف أو تعديل السعر الرسمي',
        summary: 'لإضافة منتجات جديدة أو تحديث أسعار البيع والتكلفة:',
        details: [
          '1. افتح شاشة "المنتجات والمخزون".',
          '2. اضغط [F3] لإضافة صنف جديد أو اضغط تعديل على الصنف الحالي.',
          '3. حدّث السعر الرسمي واضغط حفظ [F12].',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.products,
        requiredFeatureKey: FeatureKeys.inventory,
      );
    }

    if (q.contains('مرتجع') || q.contains('ارجاع') || q.contains('استبدال')) {
      return const AssistantInsight(
        id: 'howto_returns',
        title: 'دليل: عمل مرتجع أو استبدال فاتورة',
        summary: 'لإرجاع صنف للمخزون واسترداد قيمته من الدرج:',
        details: [
          '1. افتح شاشة "مرتجعات المبيعات".',
          '2. ابحث برقم الفاتورة أو اسم العميل [F2] واختر الفاتورة.',
          '3. حدد الكمية وسبب الإرجاع ثم اضغط تنفيذ [F12].',
        ],
        actionLabel: 'فتح الشاشة الآن',
        actionRoute: AssistantActionRoute.returns,
      );
    }

    final phoneMatch = RegExp(
      r'(?:تغيير|تعديل) (?:رقم )?(?:هاتف|تليفون|موبايل)(?: المحل| المتجر| الفاتوره)?(?: الي)?\s+([+\d\s-]+)$',
    ).firstMatch(q);
    if (phoneMatch != null) {
      final rawPhone = Money.normalizeDigits(phoneMatch.group(1)!).trim();
      if (rawPhone.isNotEmpty) {
        return AssistantInsight(
          id: 'cmd_update_phone',
          title: 'تأكيد تعديل رقم هاتف الفاتورة',
          summary: 'هل تريد تغيير رقم هاتف المتجر في الفواتير إلى "$rawPhone"؟',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateStorePhone,
            title: 'تغيير رقم هاتف الفاتورة',
            description: rawPhone,
            stringValue: rawPhone,
            touchesFeatureGate: false,
          ),
        );
      }
    }

    return null;
  }

  /// Parses direct settings commands into a pending confirmation command.
  AssistantInsight? parseCommand(String rawQuery) {
    final q = normalizeArabic(rawQuery);
    if (q.contains('ازاي') ||
        q.contains('كيف') ||
        q.contains('طريقه') ||
        q.contains('خطوات') ||
        rawQuery.trim().endsWith('؟') ||
        rawQuery.trim().endsWith('?')) {
      return null;
    }
    final enable = q.contains('فعل') ||
        q.contains('تفعيل') ||
        q.contains('شغل') ||
        q.contains('تشغيل') ||
        q.contains('اسمح') ||
        q.contains('سماح');
    final disable = q.contains('عطل') ||
        q.contains('تعطيل') ||
        q.contains('اقفل') ||
        q.contains('ايقاف') ||
        q.contains('امنع') ||
        q.contains('منع');

    if ((enable || disable) && q.contains('الجرد الاعمي')) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_blind_shift',
        title: 'تأكيد تعديل إعداد النظام',
        summary: target
            ? 'هل تريد تفعيل "الجرد الأعمى عند تقفيل الوردية"؟'
            : 'هل تريد تعطيل "الجرد الأعمى عند تقفيل الوردية"؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleBlindShiftClosing,
          title: 'الجرد الأعمى عند تقفيل الوردية',
          description: target ? 'تفعيل الميزة' : 'تعطيل الميزة',
          boolValue: target,
          touchesFeatureGate: true,
        ),
      );
    }

    if ((enable || disable) &&
        (q.contains('حمايه المدير') ||
            q.contains('pin المدير') ||
            q.contains('حمايه pin') ||
            q.contains('الرقم السري للمدير'))) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_manager_pin',
        title: 'تأكيد تعديل إعداد الأمان',
        summary: target
            ? 'هل تريد تفعيل "حماية المدير بالرقم السري"؟'
            : 'هل تريد تعطيل "حماية المدير بالرقم السري"؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleManagerPinProtection,
          title: 'حماية المدير بالرقم السري',
          description: target ? 'تفعيل الحماية' : 'تعطيل الحماية',
          boolValue: target,
          touchesFeatureGate: true,
        ),
      );
    }

    if ((enable || disable) &&
        (q.contains('الخصم اليدوي') || q.contains('خصم الكاشير'))) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_manual_discount',
        title: 'تأكيد تعديل صلاحيات الكاشير',
        summary: target
            ? 'هل تريد السماح للكاشير بالخصم اليدوي؟'
            : 'هل تريد منع الخصم اليدوي عن الكاشير؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleAllowManualDiscount,
          title: 'الخصم اليدوي للكاشير',
          description: target ? 'السماح بالخصم اليدوي' : 'منع الخصم اليدوي',
          boolValue: target,
          touchesFeatureGate: false,
        ),
      );
    }

    if ((enable || disable) &&
        (q.contains('النسخ الاحتياطي التلقائي') ||
            q.contains('النسخ التلقائي'))) {
      final target = enable && !disable;
      return AssistantInsight(
        id: 'cmd_auto_backup',
        title: 'تأكيد تعديل النسخ الاحتياطي',
        summary: target
            ? 'هل تريد تفعيل النسخ الاحتياطي التلقائي؟'
            : 'هل تريد إيقاف النسخ الاحتياطي التلقائي؟',
        details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
        pendingCommand: AssistantPendingCommand(
          kind: AssistantCommandKind.toggleAutoBackup,
          title: 'النسخ الاحتياطي التلقائي',
          description: target ? 'تفعيل' : 'تعطيل',
          boolValue: target,
          touchesFeatureGate: false,
        ),
      );
    }

    final renameMatch = RegExp(
      r'(?:تغيير اسم (?:المحل|المتجر)(?: الي)?|سمي المحل)\s+(.+)$',
    ).firstMatch(q);
    if (renameMatch != null) {
      final rawName = rawQuery
          .replaceFirst(
            RegExp(
              r'^(?:تغيير اسم (?:المحل|المتجر)(?:\s+(?:إلى|الى|الي))?|سمي المحل)\s+',
            ),
            '',
          )
          .trim();
      if (rawName.isNotEmpty) {
        return AssistantInsight(
          id: 'cmd_rename_store',
          title: 'تأكيد تغيير اسم المتجر',
          summary: 'هل تريد تغيير اسم المتجر في الفواتير إلى "$rawName"؟',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateStoreName,
            title: 'تغيير اسم المتجر',
            description: rawName,
            stringValue: rawName,
            touchesFeatureGate: false,
          ),
        );
      }
    }

    final phoneMatch = RegExp(
      r'(?:تغيير|تعديل) (?:رقم )?(?:هاتف|تليفون|موبايل)(?: المحل| المتجر| الفاتوره)?(?: الي)?\s+([+\d\s-]+)$',
    ).firstMatch(q);
    if (phoneMatch != null) {
      final rawPhone = Money.normalizeDigits(phoneMatch.group(1)!).trim();
      if (rawPhone.isNotEmpty) {
        return AssistantInsight(
          id: 'cmd_update_phone',
          title: 'تأكيد تعديل رقم هاتف الفاتورة',
          summary: 'هل تريد تغيير رقم هاتف المتجر في الفواتير إلى "$rawPhone"؟',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateStorePhone,
            title: 'تغيير رقم هاتف الفاتورة',
            description: rawPhone,
            stringValue: rawPhone,
            touchesFeatureGate: false,
          ),
        );
      }
    }

    return null;
  }

  /// Executes an approved [AssistantPendingCommand] strictly for `admin` role.
  Future<String> executeCommand(
    AssistantPendingCommand cmd, {
    required String userId,
    required String userRole,
    required FeatureGate gate,
  }) async {
    final isAdmin = userRole.toLowerCase() == 'admin';
    if (!isAdmin) {
      if (cmd.kind == AssistantCommandKind.addCustomer) {
        final custEnabled = await gate.isEnabled(FeatureKeys.customers);
        if (!custEnabled || !CashierPermissionsService.current.allowManageCustomers) {
          throw Exception('غير مصرح: إضافة العملاء متاحة للمدير أو الكاشير المصرح له فقط');
        }
      } else if (cmd.kind == AssistantCommandKind.collectInstallment) {
        final instEnabled = await gate.isEnabled(FeatureKeys.installments);
        if (!instEnabled) {
          throw Exception('غير مصرح: تحصيل الأقساط غير مفعل أو متاح للمدير فقط');
        }
      } else {
        throw Exception('غير مصرح: تنفيذ تعديلات الإعدادات متاح لحساب المدير (admin) فقط');
      }
    }

    switch (cmd.kind) {
      case AssistantCommandKind.toggleBlindShiftClosing:
        await gate.setFeatureEnabled(
          FeatureKeys.blindShiftClosing,
          cmd.boolValue ?? true,
          userId: userId,
        );
        return 'تم ${cmd.boolValue == true ? 'تفعيل' : 'تعطيل'} الجرد الأعمى بنجاح.';
      case AssistantCommandKind.toggleManagerPinProtection:
        await gate.setFeatureEnabled(
          FeatureKeys.managerPinProtection,
          cmd.boolValue ?? true,
          userId: userId,
        );
        return 'تم ${cmd.boolValue == true ? 'تفعيل' : 'تعطيل'} حماية المدير بالرقم السري بنجاح.';
      case AssistantCommandKind.toggleAllowManualDiscount:
        final updated = CashierPermissionsService.current.copyWith(
          allowManualDiscount: cmd.boolValue ?? false,
        );
        await CashierPermissionsService.save(gate, updated, userId: userId);
        return 'تم ${cmd.boolValue == true ? 'السماح بالخصم اليدوي للكاشير' : 'منع الخصم اليدوي عن الكاشير'} بنجاح.';
      case AssistantCommandKind.toggleAutoBackup:
        await gate.setMeta(
          BackupMetaKeys.autoEnabled,
          (cmd.boolValue ?? true) ? '1' : '0',
          userId: userId,
        );
        return 'تم ${cmd.boolValue == true ? 'تفعيل' : 'تعطيل'} النسخ الاحتياطي التلقائي بنجاح.';
      case AssistantCommandKind.updateStoreName:
        final newName = (cmd.stringValue ?? '').trim();
        if (newName.isEmpty) {
          throw Exception('اسم المتجر لا يمكن أن يكون فارغاً');
        }
        final updated = ReceiptSettingsService.current.copyWith(
          storeName: newName,
        );
        await ReceiptSettingsService.save(updated, gate, userId: userId);
        return 'تم تحديث اسم المتجر إلى "$newName" بنجاح.';
      case AssistantCommandKind.updateStorePhone:
        final newPhone = (cmd.stringValue ?? '').trim();
        if (newPhone.isEmpty) {
          throw Exception('رقم الهاتف لا يمكن أن يكون فارغاً');
        }
        final updated = ReceiptSettingsService.current.copyWith(
          storePhone: newPhone,
        );
        await ReceiptSettingsService.save(updated, gate, userId: userId);
        return 'تم تحديث رقم هاتف الفاتورة إلى "$newPhone" بنجاح.';
      case AssistantCommandKind.recordPurchase:
        return _execRecordPurchase(cmd.payload, userId: userId);
      case AssistantCommandKind.addProduct:
        return _execAddProduct(cmd.payload, userId: userId);
      case AssistantCommandKind.updateProductPriceOrStock:
        return _execUpdateProductPriceOrStock(cmd.payload, userId: userId);
      case AssistantCommandKind.recordExpense:
        return _execRecordExpense(cmd.payload, userId: userId);
      case AssistantCommandKind.paySupplier:
        return _execPaySupplier(cmd.payload, userId: userId);
      case AssistantCommandKind.addCustomer:
        return _execAddCustomer(cmd.payload, userId: userId);
      case AssistantCommandKind.collectInstallment:
        return _execCollectInstallment(cmd.payload, userId: userId);
    }
  }

  Future<String> _execAddCustomer(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final name = (payload['customerName'] as String? ?? '').trim();
    final phone = Money.normalizeDigits(payload['phone'] as String? ?? '').trim();
    if (name.isEmpty || phone.isEmpty) {
      throw Exception('اسم العميل ورقم الهاتف مطلوبان');
    }
    final now = DateTime.now();
    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final custId = _genId('cust');
      await _db.into(_db.customers).insert(
            CustomersCompanion.insert(
              id: custId,
              branchId: branchId,
              name: name,
              phone: phone,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_add_customer',
        entity: 'customer',
        entityId: custId,
        newValue: '$name ($phone)',
        now: now,
      );
      return 'تمت إضافة العميل "$name" ($phone) بنجاح.';
    });
  }

  Future<String> _execCollectInstallment(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final customerName = (payload['customerName'] as String? ?? '').trim();
    final amountEgp = (payload['amountEgp'] as num?)?.toDouble() ?? 0;
    if (customerName.isEmpty || amountEgp <= 0) {
      throw Exception('بيانات تحصيل القسط غير مكتملة');
    }
    final amountPiasters = (amountEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final customers = await (_db.select(_db.customers)
            ..where((c) => c.deletedAt.isNull()))
          .get();
      final norm = normalizeArabic(customerName);
      Customer? targetCust;
      for (final c in customers) {
        if (normalizeArabic(c.name) == norm ||
            normalizeArabic(c.name).contains(norm)) {
          targetCust = c;
          break;
        }
      }
      if (targetCust == null) {
        throw Exception('لم يتم العثور على عميل باسم "$customerName"');
      }

      final plans = await (_db.select(_db.customerInstallments)
            ..where((i) =>
                i.customerId.equals(targetCust!.id) &
                i.deletedAt.isNull() &
                (i.status.equals('overdue') | i.status.equals('active'))))
          .get();
      if (plans.isEmpty) {
        throw Exception('لا توجد عقود تقسيط نشطة أو متأخرة للعميل "${targetCust.name}"');
      }

      plans.sort((a, b) {
        if (a.status == 'overdue' && b.status != 'overdue') return -1;
        if (b.status == 'overdue' && a.status != 'overdue') return 1;
        return a.endDate.compareTo(b.endDate);
      });
      final plan = plans.first;
      final newRemaining = (plan.remainingPiasters - amountPiasters)
          .clamp(0, plan.totalPiasters);
      final newStatus = newRemaining == 0 ? 'completed' : 'active';
      final payId = _genId('ipay');

      await _db.into(_db.installmentPayments).insert(
            InstallmentPaymentsCompanion.insert(
              id: payId,
              branchId: branchId,
              customerInstallmentId: plan.id,
              amountPiasters: amountPiasters,
              paymentMethod: 'cash',
              paidAt: now,
              notes: const Value('تحصيل قسط عبر المساعد الذكي'),
              recordedBy: userId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (_db.update(_db.customerInstallments)
            ..where((i) => i.id.equals(plan.id)))
          .write(
        CustomerInstallmentsCompanion(
          remainingPiasters: Value(newRemaining),
          status: Value(newStatus),
          updatedAt: Value(now),
        ),
      );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_collect_installment',
        entity: 'customer_installment',
        entityId: plan.id,
        oldValue: Money(plan.remainingPiasters).toDisplay(),
        newValue: Money(newRemaining).toDisplay(),
        now: now,
      );
      return 'تم تحصيل قسط ${Money(amountPiasters).toDisplay()} ج.م من "${targetCust.name}"؛ المتبقي: ${Money(newRemaining).toDisplay()} ج.م.';
    });
  }

  Future<String> _resolveBranchId() async {
    final row = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals('branch.active_id')))
        .getSingleOrNull();
    final val = row?.value.trim() ?? '';
    return val.isNotEmpty ? val : 'branch_main';
  }

  String _genId(String prefix) {
    final us = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_$us';
  }

  Future<String> _ensureDefaultCategoryId(String branchId, DateTime now) async {
    final existing = await (_db.select(_db.categories)
          ..where((c) => c.deletedAt.isNull()))
        .get();
    if (existing.isNotEmpty) return existing.first.id;
    final catId = _genId('cat');
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: catId,
            branchId: branchId,
            name: 'عام',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return catId;
  }

  Future<void> _insertAudit({
    required String branchId,
    required String userId,
    required String action,
    required String entity,
    required String entityId,
    String? oldValue,
    String? newValue,
    required DateTime now,
  }) async {
    await _db.into(_db.auditLogs).insert(
          AuditLogsCompanion.insert(
            id: _genId('aud'),
            branchId: branchId,
            userId: userId,
            action: action,
            entity: entity,
            entityId: entityId,
            oldValue: Value(oldValue),
            newValue: Value(newValue),
            createdAt: now,
          ),
        );
  }

  Future<String> _execRecordPurchase(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final productName = (payload['productName'] as String? ?? '').trim();
    final supplierName = (payload['supplierName'] as String? ?? '').trim();
    final costEgp = (payload['costEgp'] as num?)?.toDouble() ?? 0;
    final qty = (payload['qty'] as num?)?.toInt() ?? 0;
    final isCredit = payload['paymentType'] == 'credit';

    if (productName.isEmpty || supplierName.isEmpty || costEgp <= 0 || qty <= 0) {
      throw Exception('بيانات فاتورة الشراء غير مكتملة');
    }

    final costPiasters = (costEgp * 100).round();
    final totalPiasters = costPiasters * qty;
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();

      // Match or create supplier
      final suppliers = await (_db.select(_db.suppliers)
            ..where((s) => s.deletedAt.isNull()))
          .get();
      final normSup = normalizeArabic(supplierName);
      Supplier? matchedSup;
      for (final s in suppliers) {
        if (normalizeArabic(s.name) == normSup ||
            normalizeArabic(s.name).contains(normSup)) {
          matchedSup = s;
          break;
        }
      }
      final String supplierId;
      if (matchedSup != null) {
        supplierId = matchedSup.id;
        if (isCredit) {
          await (_db.update(_db.suppliers)
                ..where((s) => s.id.equals(supplierId)))
              .write(
            SuppliersCompanion(
              balance: Value(matchedSup.balance + totalPiasters),
              updatedAt: Value(now),
            ),
          );
        }
      } else {
        supplierId = _genId('sup');
        await _db.into(_db.suppliers).insert(
              SuppliersCompanion.insert(
                id: supplierId,
                branchId: branchId,
                name: supplierName,
                balance: Value(isCredit ? totalPiasters : 0),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // Match or create product + variant
      final products = await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get();
      final normProd = normalizeArabic(productName);
      Product? matchedProd;
      for (final p in products) {
        if (normalizeArabic(p.name) == normProd ||
            normalizeArabic(p.name).contains(normProd)) {
          matchedProd = p;
          break;
        }
      }

      final String variantId;
      if (matchedProd != null) {
        final variants = await (_db.select(_db.productVariants)
              ..where((v) =>
                  v.productId.equals(matchedProd!.id) & v.deletedAt.isNull()))
            .get();
        if (variants.isNotEmpty) {
          final v = variants.first;
          variantId = v.id;
          await (_db.update(_db.productVariants)
                ..where((t) => t.id.equals(variantId)))
              .write(
            ProductVariantsCompanion(
              quantity: Value(v.quantity + qty),
              costPrice: Value(costPiasters),
              updatedAt: Value(now),
            ),
          );
        } else {
          variantId = _genId('var');
          await _db.into(_db.productVariants).insert(
                ProductVariantsCompanion.insert(
                  id: variantId,
                  branchId: branchId,
                  productId: matchedProd.id,
                  sku: 'SKU-${now.millisecondsSinceEpoch}',
                  color: '-',
                  size: '-',
                  quantity: Value(qty),
                  costPrice: costPiasters,
                  sellPrice: (costPiasters * 1.3).round(),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
      } else {
        final catId = await _ensureDefaultCategoryId(branchId, now);
        final prodId = _genId('prd');
        await _db.into(_db.products).insert(
              ProductsCompanion.insert(
                id: prodId,
                branchId: branchId,
                name: productName,
                categoryId: catId,
                createdAt: now,
                updatedAt: now,
              ),
            );
        variantId = _genId('var');
        await _db.into(_db.productVariants).insert(
              ProductVariantsCompanion.insert(
                id: variantId,
                branchId: branchId,
                productId: prodId,
                sku: 'SKU-${now.millisecondsSinceEpoch}',
                color: '-',
                size: '-',
                quantity: Value(qty),
                costPrice: costPiasters,
                sellPrice: (costPiasters * 1.3).round(),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // Insert Purchase & PurchaseItem
      final purchaseId = _genId('pur');
      await _db.into(_db.purchases).insert(
            PurchasesCompanion.insert(
              id: purchaseId,
              branchId: branchId,
              supplierId: supplierId,
              invoiceNumber: Value('PUR-${now.millisecondsSinceEpoch % 100000}'),
              purchaseDate: now,
              totalAmount: totalPiasters,
              paidAmount: Value(isCredit ? 0 : totalPiasters),
              status: const Value('received'),
              paymentStatus: Value(isCredit ? 'unpaid' : 'paid'),
              notes: const Value('تم التسجيل عبر المساعد الذكي'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.into(_db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              id: _genId('pi'),
              purchaseId: purchaseId,
              variantId: variantId,
              qty: qty,
              costPrice: costPiasters,
              totalCost: totalPiasters,
              createdAt: now,
            ),
          );

      // Stock movement (InventoryLogs) + AuditLog
      await _db.into(_db.inventoryLogs).insert(
            InventoryLogsCompanion.insert(
              id: _genId('inv'),
              branchId: branchId,
              variantId: variantId,
              type: 'purchase',
              qtyDelta: qty,
              refType: 'purchase',
              refId: Value(purchaseId),
              reason: Value('شراء من $supplierName'),
              userId: userId,
              createdAt: now,
            ),
          );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_record_purchase',
        entity: 'purchase',
        entityId: purchaseId,
        newValue:
            '$productName x$qty @ ${Money(costPiasters).toDisplay()} (${isCredit ? 'credit' : 'cash'})',
        now: now,
      );

      return 'تم تسجيل فاتورة شراء "$productName" ($qty قطعة من $supplierName) بإجمالي ${Money(totalPiasters).toDisplay()} ج.م (${isCredit ? 'آجل على حساب المورد' : 'نقدي'}).';
    });
  }

  Future<String> _execAddProduct(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final name = (payload['productName'] as String? ?? '').trim();
    final costEgp = (payload['costEgp'] as num?)?.toDouble() ?? 0;
    final sellEgp = (payload['sellEgp'] as num?)?.toDouble() ?? 0;
    final qty = (payload['qty'] as num?)?.toInt() ?? 0;

    if (name.isEmpty || costEgp < 0 || sellEgp <= 0 || qty < 0) {
      throw Exception('بيانات الصنف الجديد غير مكتملة');
    }

    final costPiasters = (costEgp * 100).round();
    final sellPiasters = (sellEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final catId = await _ensureDefaultCategoryId(branchId, now);
      final prodId = _genId('prd');
      final varId = _genId('var');

      await _db.into(_db.products).insert(
            ProductsCompanion.insert(
              id: prodId,
              branchId: branchId,
              name: name,
              categoryId: catId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db.into(_db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: varId,
              branchId: branchId,
              productId: prodId,
              sku: 'SKU-${now.millisecondsSinceEpoch}',
              color: '-',
              size: '-',
              quantity: Value(qty),
              costPrice: costPiasters,
              sellPrice: sellPiasters,
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (qty > 0) {
        await _db.into(_db.inventoryLogs).insert(
              InventoryLogsCompanion.insert(
                id: _genId('inv'),
                branchId: branchId,
                variantId: varId,
                type: 'initial_stock',
                qtyDelta: qty,
                refType: 'product',
                refId: Value(prodId),
                reason: const Value('إضافة صنف عبر المساعد الذكي'),
                userId: userId,
                createdAt: now,
              ),
            );
      }
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_add_product',
        entity: 'product',
        entityId: prodId,
        newValue:
            '$name | تكلفة: ${Money(costPiasters).toDisplay()} | بيع: ${Money(sellPiasters).toDisplay()} | كمية: $qty',
        now: now,
      );

      return 'تمت إضافة الصنف "$name" (تكلفة ${Money(costPiasters).toDisplay()}، بيع ${Money(sellPiasters).toDisplay()} ج.م، رصيد $qty) بنجاح.';
    });
  }

  Future<String> _execUpdateProductPriceOrStock(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final mode = (payload['mode'] as String? ?? 'price').trim();
    final productName = (payload['productName'] as String? ?? '').trim();
    final numVal = (payload['value'] as num?)?.toDouble() ?? 0;

    if (productName.isEmpty) {
      throw Exception('اسم الصنف مطلوب');
    }

    final now = DateTime.now();
    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final products = await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get();
      final norm = normalizeArabic(productName);
      Product? targetProd;
      for (final p in products) {
        if (normalizeArabic(p.name) == norm ||
            normalizeArabic(p.name).contains(norm)) {
          targetProd = p;
          break;
        }
      }
      if (targetProd == null) {
        throw Exception('لم يتم العثور على صنف باسم "$productName"');
      }

      final variants = await (_db.select(_db.productVariants)
            ..where((v) =>
                v.productId.equals(targetProd!.id) & v.deletedAt.isNull()))
          .get();
      if (variants.isEmpty) {
        throw Exception('لا توجد وحدات متاحة للصنف "${targetProd.name}"');
      }
      final v = variants.first;

      if (mode == 'price') {
        final newSellPiasters = (numVal * 100).round();
        if (newSellPiasters <= 0) {
          throw Exception('سعر البيع يجب أن يكون أكبر من صفر');
        }
        await (_db.update(_db.productVariants)
              ..where((t) => t.id.equals(v.id)))
            .write(
          ProductVariantsCompanion(
            sellPrice: Value(newSellPiasters),
            updatedAt: Value(now),
          ),
        );
        await _insertAudit(
          branchId: branchId,
          userId: userId,
          action: 'assistant_update_price',
          entity: 'product_variant',
          entityId: v.id,
          oldValue: Money(v.sellPrice).toDisplay(),
          newValue: Money(newSellPiasters).toDisplay(),
          now: now,
        );
        return 'تم تعديل سعر بيع "${targetProd.name}" إلى ${Money(newSellPiasters).toDisplay()} ج.م.';
      } else {
        final delta = numVal.round();
        final nextQty = v.quantity + delta;
        if (nextQty < 0) {
          throw Exception('الرصيد الناتج لا يمكن أن يكون سالباً');
        }
        await (_db.update(_db.productVariants)
              ..where((t) => t.id.equals(v.id)))
            .write(
          ProductVariantsCompanion(
            quantity: Value(nextQty),
            updatedAt: Value(now),
          ),
        );
        await _db.into(_db.inventoryLogs).insert(
              InventoryLogsCompanion.insert(
                id: _genId('inv'),
                branchId: branchId,
                variantId: v.id,
                type: 'adjustment',
                qtyDelta: delta,
                refType: 'product',
                refId: Value(targetProd.id),
                reason: const Value('تعديل رصيد عبر المساعد الذكي'),
                userId: userId,
                createdAt: now,
              ),
            );
        await _insertAudit(
          branchId: branchId,
          userId: userId,
          action: 'assistant_adjust_stock',
          entity: 'product_variant',
          entityId: v.id,
          oldValue: '${v.quantity}',
          newValue: '$nextQty',
          now: now,
        );
        return 'تم تحديث رصيد "${targetProd.name}" إلى $nextQty قطعة.';
      }
    });
  }

  Future<String> _execRecordExpense(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final category = (payload['category'] as String? ?? '').trim();
    final amountEgp = (payload['amountEgp'] as num?)?.toDouble() ?? 0;
    if (category.isEmpty || amountEgp <= 0) {
      throw Exception('بيانات المصروف غير مكتملة');
    }
    final amountPiasters = (amountEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final expId = _genId('exp');
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: expId,
              branchId: branchId,
              category: category,
              amount: amountPiasters,
              kind: const Value('operating'),
              note: const Value('تم التسجيل عبر المساعد الذكي'),
              userId: userId,
              expenseDate: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_record_expense',
        entity: 'expense',
        entityId: expId,
        newValue: '$category: ${Money(amountPiasters).toDisplay()}',
        now: now,
      );
      return 'تم تسجيل مصروف "$category" بمبلغ ${Money(amountPiasters).toDisplay()} ج.م بنجاح.';
    });
  }

  Future<String> _execPaySupplier(
    Map<String, dynamic> payload, {
    required String userId,
  }) async {
    final supplierName = (payload['supplierName'] as String? ?? '').trim();
    final amountEgp = (payload['amountEgp'] as num?)?.toDouble() ?? 0;
    if (supplierName.isEmpty || amountEgp <= 0) {
      throw Exception('بيانات سداد المورد غير مكتملة');
    }
    final amountPiasters = (amountEgp * 100).round();
    final now = DateTime.now();

    return _db.transaction(() async {
      final branchId = await _resolveBranchId();
      final suppliers = await (_db.select(_db.suppliers)
            ..where((s) => s.deletedAt.isNull()))
          .get();
      final norm = normalizeArabic(supplierName);
      Supplier? targetSup;
      for (final s in suppliers) {
        if (normalizeArabic(s.name) == norm ||
            normalizeArabic(s.name).contains(norm)) {
          targetSup = s;
          break;
        }
      }
      if (targetSup == null) {
        throw Exception('لم يتم العثور على مورد باسم "$supplierName"');
      }

      final newBalance = targetSup.balance - amountPiasters;
      final payId = _genId('spay');
      await _db.into(_db.supplierPayments).insert(
            SupplierPaymentsCompanion.insert(
              id: payId,
              branchId: branchId,
              supplierId: targetSup.id,
              amount: amountPiasters,
              paymentDate: now,
              paymentMethod: const Value('cash'),
              notes: const Value('سداد عبر المساعد الذكي'),
              createdBy: userId,
              createdAt: now,
            ),
          );
      await (_db.update(_db.suppliers)
            ..where((s) => s.id.equals(targetSup!.id)))
          .write(
        SuppliersCompanion(
          balance: Value(newBalance),
          updatedAt: Value(now),
        ),
      );
      await _insertAudit(
        branchId: branchId,
        userId: userId,
        action: 'assistant_pay_supplier',
        entity: 'supplier_payment',
        entityId: payId,
        oldValue: Money(targetSup.balance).toDisplay(),
        newValue: Money(newBalance).toDisplay(),
        now: now,
      );
      return 'تم تسجيل سداد ${Money(amountPiasters).toDisplay()} ج.م للمورد "${targetSup.name}"؛ الرصيد الحالي: ${Money(newBalance).toDisplay()} ج.م.';
    });
  }

  /// Parses ERP operational commands into a (possibly incomplete) [AssistantActionDraft].
  AssistantActionDraft? parseErpDraft(String rawQuery) {
    final normalizedDigits = Money.normalizeDigits(rawQuery).trim();
    final q = normalizeArabic(normalizedDigits);

    // 0. Add Customer: "ضيف عميل [اسم] [رقم هاتف]"
    if (q.startsWith('ضيف عميل') ||
        q.startsWith('اضف عميل') ||
        q.startsWith('اضافه عميل') ||
        q.startsWith('عميل جديد')) {
      final body = normalizedDigits
          .replaceFirst(
            RegExp(r'^(?:ضيف\s+عميل|اضف\s+عميل|أضف\s+عميل|اضافه\s+عميل|إضافة\s+عميل|عميل\s+جديد)\s*'),
            '',
          )
          .trim();
      final phoneMatch = RegExp(r'(\+?\d{8,15})$').firstMatch(body);
      String? phone;
      String? custName;
      if (phoneMatch != null) {
        phone = phoneMatch.group(1)!.trim();
        custName = body.substring(0, phoneMatch.start).trim();
      } else if (body.isNotEmpty) {
        custName = body;
      }
      final fields = <String, dynamic>{
        if (custName != null && custName.isNotEmpty) 'customerName': custName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      };
      return _finalizeDraft(AssistantCommandKind.addCustomer, fields);
    }

    // 0b. Collect Installment: "العميل [اسم] دفع قسط [مبلغ]" / "تحصيل قسط [اسم] [مبلغ]"
    if (q.contains('دفع قسط') || q.startsWith('تحصيل قسط')) {
      String body = normalizedDigits;
      double? amount;
      String? custName;
      final custPayMatch = RegExp(
        r'^(?:العميل\s+)?(.+?)\s+دفع\s+قسط(?:\s+(\d+(?:\.\d+)?))?',
      ).firstMatch(body);
      if (custPayMatch != null) {
        custName = custPayMatch.group(1)?.trim();
        if (custPayMatch.group(2) != null) {
          amount = double.tryParse(custPayMatch.group(2)!);
        }
      } else {
        body = body.replaceFirst(RegExp(r'^تحصيل\s+قسط\s*'), '').trim();
        final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
        if (amtMatch != null) {
          amount = double.tryParse(amtMatch.group(1)!);
          custName = body.substring(0, amtMatch.start).trim();
        } else if (body.isNotEmpty) {
          custName = body;
        }
      }
      final fields = <String, dynamic>{
        if (custName != null && custName.isNotEmpty) 'customerName': custName,
        if (amount != null && amount > 0) 'amountEgp': amount,
      };
      return _finalizeDraft(AssistantCommandKind.collectInstallment, fields);
    }

    // 1. Pay Supplier: "دفعت للمورد [اسم] [مبلغ]" / "سداد مورد [اسم] [مبلغ]"
    if (q.startsWith('دفعت للمورد') ||
        q.startsWith('دفعت لمورد') ||
        q.startsWith('سداد مورد') ||
        q.startsWith('سدد للمورد')) {
      final body = normalizedDigits
          .replaceFirst(
            RegExp(r'^(?:دفعت\s+(?:للمورد|لمورد)|سداد\s+مورد|سدد\s+للمورد)\s*'),
            '',
          )
          .trim();
      final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
      double? amount;
      String? supName;
      if (amtMatch != null) {
        amount = double.tryParse(amtMatch.group(1)!);
        supName = body.substring(0, amtMatch.start).trim();
      } else if (body.isNotEmpty) {
        supName = body;
      }
      final fields = <String, dynamic>{
        if (supName != null && supName.isNotEmpty) 'supplierName': supName,
        if (amount != null && amount > 0) 'amountEgp': amount,
      };
      return _finalizeDraft(AssistantCommandKind.paySupplier, fields);
    }

    // 2. Record Expense: "سجل مصروف [بند] [مبلغ]" / "دفعت [بند] [مبلغ]"
    if (q.startsWith('سجل مصروف') ||
        q.startsWith('اضف مصروف') ||
        q.startsWith('مصروف جديد') ||
        (q.startsWith('دفعت ') && !q.contains('مورد'))) {
      final body = normalizedDigits
          .replaceFirst(
            RegExp(r'^(?:سجل\s+مصروف|اضف\s+مصروف|أضف\s+مصروف|مصروف\s+جديد|دفعت)\s*'),
            '',
          )
          .trim();
      final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
      double? amount;
      String? category;
      if (amtMatch != null) {
        amount = double.tryParse(amtMatch.group(1)!);
        category = body.substring(0, amtMatch.start).trim();
      } else if (body.isNotEmpty) {
        category = body;
      }
      final fields = <String, dynamic>{
        if (category != null && category.isNotEmpty) 'category': category,
        if (amount != null && amount > 0) 'amountEgp': amount,
      };
      return _finalizeDraft(AssistantCommandKind.recordExpense, fields);
    }

    // 3. Update Product Price or Stock: "خلي سعر [صنف] [سعر]" / "زود رصيد [صنف] [عدد]"
    if (q.startsWith('خلي سعر ') ||
        q.startsWith('عدل سعر ') ||
        q.startsWith('غير سعر ')) {
      final body = normalizedDigits
          .replaceFirst(RegExp(r'^(?:خلي|عدل|غير|عدّل)\s+سعر\s+'), '')
          .trim();
      final numMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
      double? val;
      String? prodName;
      if (numMatch != null) {
        val = double.tryParse(numMatch.group(1)!);
        prodName = body.substring(0, numMatch.start).trim();
      } else if (body.isNotEmpty) {
        prodName = body;
      }
      final fields = <String, dynamic>{
        'mode': 'price',
        if (prodName != null && prodName.isNotEmpty) 'productName': prodName,
        if (val != null && val > 0) 'value': val,
      };
      return _finalizeDraft(AssistantCommandKind.updateProductPriceOrStock, fields);
    }
    if (q.startsWith('زود رصيد ') ||
        q.startsWith('زود كميه ') ||
        q.startsWith('نقص رصيد ')) {
      final isNeg = q.startsWith('نقص');
      final body = normalizedDigits
          .replaceFirst(RegExp(r'^(?:زود|نقص)\s+(?:رصيد|كميه|كمية)\s+'), '')
          .trim();
      final numMatch = RegExp(r'(\d+)\s*(?:قطعه|قطعة)?$').firstMatch(body);
      int? val;
      String? prodName;
      if (numMatch != null) {
        val = int.tryParse(numMatch.group(1)!);
        if (val != null && isNeg) val = -val;
        prodName = body.substring(0, numMatch.start).trim();
      } else if (body.isNotEmpty) {
        prodName = body;
      }
      final fields = <String, dynamic>{
        'mode': 'stock',
        if (prodName != null && prodName.isNotEmpty) 'productName': prodName,
        if (val != null && val != 0) 'value': val,
      };
      return _finalizeDraft(AssistantCommandKind.updateProductPriceOrStock, fields);
    }

    // 4. Add Product: "ضيف صنف [اسم] تكلفة [سعر] بيع [سعر] كمية [عدد]"
    if (q.startsWith('ضيف صنف') ||
        q.startsWith('اضف صنف') ||
        q.startsWith('اضافه صنف') ||
        q.startsWith('صنف جديد')) {
      final body = normalizedDigits
          .replaceFirst(
            RegExp(r'^(?:ضيف\s+صنف|اضف\s+صنف|أضف\s+صنف|اضافه\s+صنف|إضافة\s+صنف|صنف\s+جديد)\s*'),
            '',
          )
          .trim();
      final costMatch = RegExp(r'(?:تكلفه|تكلفة)\s+(\d+(?:\.\d+)?)').firstMatch(body);
      final sellMatch = RegExp(r'(?:بيع|سعر)\s+(\d+(?:\.\d+)?)').firstMatch(body);
      final qtyMatch = RegExp(r'(?:كميه|كمية|عدد)\s+(\d+)').firstMatch(body);

      String prodName = body;
      final cutIndices = [
        if (costMatch != null) costMatch.start,
        if (sellMatch != null) sellMatch.start,
        if (qtyMatch != null) qtyMatch.start,
      ];
      if (cutIndices.isNotEmpty) {
        cutIndices.sort();
        prodName = body.substring(0, cutIndices.first).trim();
      }

      final fields = <String, dynamic>{
        if (prodName.isNotEmpty) 'productName': prodName,
        if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
        if (sellMatch != null) 'sellEgp': double.tryParse(sellMatch.group(1)!),
        if (qtyMatch != null) 'qty': int.tryParse(qtyMatch.group(1)!),
      }..removeWhere((_, v) => v == null);
      return _finalizeDraft(AssistantCommandKind.addProduct, fields);
    }

    // 5. Record Purchase: "اشتريت [صنف] من المورد [اسم] بسعر [سعر] عدد [كمية] (نقدي/آجل)"
    if (q.startsWith('اشتريت') || q.startsWith('شراء ') || q.startsWith('سجل مشتريات')) {
      final body = normalizedDigits
          .replaceFirst(RegExp(r'^(?:اشتريت|شراء|سجل\s+مشتريات)\s*'), '')
          .trim();
      final isCredit = q.contains('اجل') || q.contains('آجل') || q.contains('شكك');
      final supMatch = RegExp(
        r'من\s+(?:المورد|مورد)?\s*([^\d]+?)(?=\s+(?:بسعر|سعر|عدد|كميه|كمية|نقدي|كاش|آجل|اجل)|$)',
      ).firstMatch(body);
      final costMatch = RegExp(r'(?:بسعر|سعر)\s+(\d+(?:\.\d+)?)').firstMatch(body);
      final qtyMatch = RegExp(r'(?:عدد|كميه|كمية)\s+(\d+)').firstMatch(body);

      String prodName = body;
      final cutIndices = [
        if (supMatch != null) supMatch.start,
        if (costMatch != null) costMatch.start,
        if (qtyMatch != null) qtyMatch.start,
      ];
      if (cutIndices.isNotEmpty) {
        cutIndices.sort();
        prodName = body.substring(0, cutIndices.first).trim();
      }

      final fields = <String, dynamic>{
        if (prodName.isNotEmpty) 'productName': prodName,
        if (supMatch != null && supMatch.group(1)!.trim().isNotEmpty)
          'supplierName': supMatch.group(1)!.trim(),
        if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
        if (qtyMatch != null) 'qty': int.tryParse(qtyMatch.group(1)!),
        'paymentType': isCredit ? 'credit' : 'cash',
      }..removeWhere((_, v) => v == null);
      return _finalizeDraft(AssistantCommandKind.recordPurchase, fields);
    }

    return null;
  }

  AssistantActionDraft _finalizeDraft(
    AssistantCommandKind kind,
    Map<String, dynamic> fields,
  ) {
    switch (kind) {
      case AssistantCommandKind.recordPurchase:
        if ((fields['productName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'productName',
            promptForMissing: 'ما اسم الصنف الذي اشتريته؟',
          );
        }
        if ((fields['supplierName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'supplierName',
            promptForMissing: 'من أي مورد اشتريت الصنف؟',
          );
        }
        if ((fields['costEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'costEgp',
            promptForMissing: 'كم سعر شراء القطعة الواحدة بالجنيه؟',
          );
        }
        if ((fields['qty'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'qty',
            promptForMissing: 'كم الكمية المشتراة (عدد القطع)؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.addProduct:
        if ((fields['productName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'productName',
            promptForMissing: 'ما اسم الصنف الجديد؟',
          );
        }
        if (fields['costEgp'] == null) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'costEgp',
            promptForMissing: 'كم سعر التكلفة للصنف الجديد بالجنيه؟',
          );
        }
        if ((fields['sellEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'sellEgp',
            promptForMissing: 'كم سعر البيع المقترح بالجنيه؟',
          );
        }
        if (fields['qty'] == null) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'qty',
            promptForMissing: 'كم الكمية الافتتاحية بالمخزن؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.updateProductPriceOrStock:
        final isPrice = (fields['mode'] ?? 'price') == 'price';
        if ((fields['productName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'productName',
            promptForMissing: 'ما اسم الصنف المراد تعديله؟',
          );
        }
        if (fields['value'] == null) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'value',
            promptForMissing:
                isPrice ? 'ما السعر الجديد بالجنيه؟' : 'كم الكمية المراد إضافتها/خصمها؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.recordExpense:
        if ((fields['category'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'category',
            promptForMissing: 'ما بند المصروف (مثال: كهرباء، إيجار، ضيافة)؟',
          );
        }
        if ((fields['amountEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'amountEgp',
            promptForMissing: 'كم مبلغ المصروف بالجنيه؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.paySupplier:
        if ((fields['supplierName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'supplierName',
            promptForMissing: 'ما اسم المورد المراد السداد له؟',
          );
        }
        if ((fields['amountEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'amountEgp',
            promptForMissing: 'كم المبلغ المدفوع للمورد بالجنيه؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.addCustomer:
        if ((fields['customerName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'customerName',
            promptForMissing: 'ما اسم العميل الجديد؟',
          );
        }
        if ((fields['phone'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'phone',
            promptForMissing: 'ما رقم هاتف العميل؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      case AssistantCommandKind.collectInstallment:
        if ((fields['customerName'] as String? ?? '').isEmpty) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'customerName',
            promptForMissing: 'ما اسم العميل الذي سدد القسط؟',
          );
        }
        if ((fields['amountEgp'] as num? ?? 0) <= 0) {
          return AssistantActionDraft(
            kind: kind,
            fields: fields,
            missingField: 'amountEgp',
            promptForMissing: 'كم مبلغ القسط المحصل بالجنيه؟',
          );
        }
        return AssistantActionDraft(kind: kind, fields: fields);

      default:
        return AssistantActionDraft(kind: kind, fields: fields);
    }
  }

  AssistantActionDraft advanceDraft(
    AssistantActionDraft draft,
    String userReply,
  ) {
    final cleaned = Money.normalizeDigits(userReply).trim();
    final updated = Map<String, dynamic>.from(draft.fields);
    final missing = draft.missingField;
    if (missing != null && cleaned.isNotEmpty) {
      if (missing == 'costEgp' ||
          missing == 'sellEgp' ||
          missing == 'amountEgp') {
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
        if (numMatch != null) {
          updated[missing] = double.tryParse(numMatch.group(1)!);
        }
      } else if (missing == 'qty' || missing == 'value') {
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
        if (numMatch != null) {
          updated[missing] = missing == 'qty'
              ? int.tryParse(numMatch.group(1)!.split('.').first)
              : double.tryParse(numMatch.group(1)!);
        }
      } else {
        updated[missing] = cleaned;
      }
    }
    return _finalizeDraft(draft.kind, updated);
  }

  AssistantInsight _buildDraftPromptInsight(AssistantActionDraft draft) {
    return AssistantInsight(
      id: 'draft_prompt_${draft.missingField}',
      title: 'استكمال بيانات العملية',
      summary: draft.promptForMissing ?? 'أدخل القيمة المطلوبة:',
      details: const ['يمكنك كتابة "إلغاء" في أي وقت لإلغاء المسودة.'],
    );
  }

  AssistantInsight _buildPendingCommandInsight(AssistantActionDraft draft) {
    final f = draft.fields;
    switch (draft.kind) {
      case AssistantCommandKind.recordPurchase:
        final prod = f['productName'];
        final sup = f['supplierName'];
        final cost = (f['costEgp'] as num).toDouble();
        final qty = (f['qty'] as num).toInt();
        final isCredit = f['paymentType'] == 'credit';
        final total = cost * qty;
        return AssistantInsight(
          id: 'cmd_record_purchase',
          title: 'تأكيد تسجيل فاتورة مشتريات',
          summary:
              'شراء "$prod" ($qty قطعة) من المورد "$sup" بإجمالي ${total.toStringAsFixed(2)} ج.م (${isCredit ? 'آجل' : 'نقدي'}).',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin) ويُحفظ في سجل المراجعة.'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.recordPurchase,
            title: 'تسجيل مشتريات',
            description: '$prod x$qty',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.addProduct:
        final prod = f['productName'];
        final cost = (f['costEgp'] as num).toDouble();
        final sell = (f['sellEgp'] as num).toDouble();
        final qty = (f['qty'] as num).toInt();
        return AssistantInsight(
          id: 'cmd_add_product',
          title: 'تأكيد إضافة صنف جديد',
          summary:
              'إضافة "$prod" — تكلفة ${cost.toStringAsFixed(2)} ج.م، بيع ${sell.toStringAsFixed(2)} ج.م، كمية $qty.',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.addProduct,
            title: 'إضافة صنف جديد',
            description: '$prod',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.updateProductPriceOrStock:
        final isPrice = (f['mode'] ?? 'price') == 'price';
        final prod = f['productName'];
        final val = (f['value'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_update_product',
          title: isPrice ? 'تأكيد تعديل سعر الصنف' : 'تأكيد تعديل رصيد الصنف',
          summary: isPrice
              ? 'تعديل سعر بيع "$prod" إلى ${val.toStringAsFixed(2)} ج.م.'
              : 'تعديل رصيد "$prod" بمقدار ${val.toInt()} قطعة.',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.updateProductPriceOrStock,
            title: isPrice ? 'تعديل سعر صنف' : 'تعديل رصيد صنف',
            description: '$prod',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.recordExpense:
        final cat = f['category'];
        final amt = (f['amountEgp'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_record_expense',
          title: 'تأكيد تسجيل مصروف',
          summary: 'تسجيل مصروف "$cat" بمبلغ ${amt.toStringAsFixed(2)} ج.م.',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.recordExpense,
            title: 'تسجيل مصروف',
            description: '$cat',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.paySupplier:
        final sup = f['supplierName'];
        final amt = (f['amountEgp'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_pay_supplier',
          title: 'تأكيد سداد مورد',
          summary: 'تسجيل سداد ${amt.toStringAsFixed(2)} ج.م للمورد "$sup".',
          details: const ['يتطلب التنفيذ صلاحية مدير (Admin).'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.paySupplier,
            title: 'سداد مورد',
            description: '$sup',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.addCustomer:
        final cust = f['customerName'];
        final phone = f['phone'];
        return AssistantInsight(
          id: 'cmd_add_customer',
          title: 'تأكيد إضافة عميل جديد',
          summary: 'إضافة العميل "$cust" برقم هاتف "$phone".',
          details: const ['يتطلب التنفيذ صلاحية مدير أو كاشير مصرح له.'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.addCustomer,
            title: 'إضافة عميل',
            description: '$cust',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      case AssistantCommandKind.collectInstallment:
        final cust = f['customerName'];
        final amt = (f['amountEgp'] as num).toDouble();
        return AssistantInsight(
          id: 'cmd_collect_installment',
          title: 'تأكيد تحصيل قسط عميل',
          summary: 'تحصيل قسط بقيمة ${amt.toStringAsFixed(2)} ج.م من العميل "$cust".',
          details: const ['سيتم تحديث المتبقي في عقد التقسيط وتسجيل الدفعة.'],
          pendingCommand: AssistantPendingCommand(
            kind: AssistantCommandKind.collectInstallment,
            title: 'تحصيل قسط',
            description: '$cust',
            payload: Map<String, dynamic>.from(f),
          ),
        );
      default:
        return const AssistantInsight(
          id: 'cmd_unknown',
          title: 'أمر غير معروف',
          summary: 'تعذر تجهيز الأمر للتنفيذ.',
        );
    }
  }

  /// Batch 2.1c: WhatsApp Installment Reminder for a customer.
  Future<AssistantInsight> getInstallmentReminderInsight(
    String rawQuery,
  ) async {
    String storeName = 'المحل';
    try {
      final nameMeta = await (_db.select(_db.appMeta)
            ..where((m) => m.key.equals(ReceiptSettingsService.keyStoreName)))
          .getSingleOrNull();
      if (nameMeta != null && nameMeta.value.trim().isNotEmpty) {
        storeName = nameMeta.value.trim();
      }
    } catch (_) {}

    final targetName = rawQuery
        .replaceFirst(
          RegExp(r'^.*?(?:تذكير\s+قسط\s+(?:لـ\s*|ل|الي|إلى\s+)?|رساله\s+قسط\s+(?:لـ\s*|ل)?)'),
          '',
        )
        .trim();

    String resolvedName = targetName.isNotEmpty ? targetName : 'العميل الكريم';
    String amountLine = '';

    if (targetName.isNotEmpty) {
      final customers = await (_db.select(_db.customers)
            ..where((c) => c.deletedAt.isNull()))
          .get();
      final norm = normalizeArabic(targetName);
      Customer? matched;
      for (final c in customers) {
        if (normalizeArabic(c.name) == norm ||
            normalizeArabic(c.name).contains(norm)) {
          matched = c;
          break;
        }
      }
      if (matched != null) {
        resolvedName = matched.name;
        final plans = await (_db.select(_db.customerInstallments)
              ..where((i) =>
                  i.customerId.equals(matched!.id) &
                  i.deletedAt.isNull() &
                  (i.status.equals('overdue') | i.status.equals('active'))))
            .get();
        if (plans.isNotEmpty) {
          final p = plans.first;
          amountLine =
              '\nقيمة القسط الشهري: ${Money(p.monthlyAmountPiasters).toDisplay()} ج.م | المتبقي: ${Money(p.remainingPiasters).toDisplay()} ج.م.';
        }
      }
    }

    final msg = 'تذكير قسط للعميل $resolvedName\n---\n'
        'السلام عليكم $resolvedName،\n'
        'تحية طيبة من $storeName. نود تذكيركم بموعد سداد القسط المستحق.$amountLine\n'
        'يسعدنا تواصلكم أو تشريفكم بالفرع في أقرب وقت. شكراً لتعاونكم.';

    return AssistantInsight(
      id: 'installment_reminder',
      title: 'رسالة تذكير قسط جاهزة للواتساب',
      summary: 'رسالة تذكير مهذبة للعميل "$resolvedName" — اضغط نسخ للإرسال:',
      details: [msg],
    );
  }

  /// Batch 2.2: End-of-Day Report ("تقرير قفلة اليوم") with WhatsApp copy support.
  Future<AssistantInsight> getEndOfDayReportInsight() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(todayStart) &
              s.date.isSmallerThanValue(todayEnd) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final totalSales = salesRows.fold<int>(0, (s, r) => s + r.total);
    final cashSales = salesRows
        .where((s) => s.paymentMethod.toLowerCase() == 'cash')
        .fold<int>(0, (s, r) => s + r.total);

    final netProfit = await _computeNetProfitForRange(todayStart, todayEnd);

    final returnsRows = await (_db.select(_db.returns)
          ..where((r) =>
              r.date.isBiggerOrEqualValue(todayStart) &
              r.date.isSmallerThanValue(todayEnd) &
              r.deletedAt.isNull()))
        .get();
    final totalReturns = returnsRows.fold<int>(0, (s, r) => s + r.refundAmount);
    final cashReturns = returnsRows
        .where((r) => r.paymentMethod.toLowerCase() == 'cash')
        .fold<int>(0, (s, r) => s + r.refundAmount);

    final expensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.expenseDate.isBiggerOrEqualValue(todayStart) &
              e.expenseDate.isSmallerThanValue(todayEnd) &
              e.deletedAt.isNull()))
        .get();
    final totalExpenses = expensesRows.fold<int>(0, (s, e) => s + e.amount);

    final openShift = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();
    final drawerExpected =
        (openShift?.openingBalance ?? 0) + cashSales - cashReturns - totalExpenses;

    // Low stock
    final products = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final prodMap = {for (final p in products) p.id: p};
    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull()))
        .get();
    final lowNames = <String>[];
    for (final v in variants) {
      final p = prodMap[v.productId];
      if (p != null && v.quantity <= p.minStock && !lowNames.contains(p.name)) {
        lowNames.add('${p.name} (${v.quantity})');
      }
      if (lowNames.length >= 3) break;
    }

    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return AssistantInsight(
      id: 'eod_report',
      title: 'تقرير قفلة اليوم ($dateStr)',
      summary:
          'مبيعات اليوم: ${Money(totalSales).toDisplay()} ج.م | صافي الربح: ${Money(netProfit).toDisplay()} ج.م',
      details: [
        'عدد الفواتير: ${salesRows.length} فاتورة | إجمالي المبيعات: ${Money(totalSales).toDisplay()} ج.م',
        'صافي الربح: ${Money(netProfit).toDisplay()} ج.م',
        'المرتجعات: ${Money(totalReturns).toDisplay()} ج.م (${returnsRows.length} مرتجع)',
        'المصروفات: ${Money(totalExpenses).toDisplay()} ج.م',
        'المتبقي المتوقع بالدرج: ${Money(drawerExpected).toDisplay()} ج.م',
        lowNames.isEmpty
            ? 'النواقص: لا توجد نواقص حرجة اليوم.'
            : 'أهم النواقص: ${lowNames.join('، ')}',
      ],
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.shifts,
      requiredFeatureKey: FeatureKeys.shifts,
    );
  }

  /// Batch 2.3: Barcode / SKU lookup inside chat with quick price/stock follow-ups.
  Future<AssistantInsight?> searchByBarcodeOrSkuInsight(String rawQuery) async {
    final code = Money.normalizeDigits(rawQuery).trim();
    if (code.length < 3 || code.contains(' ')) return null;
    final lowerCode = code.toLowerCase();

    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull()))
        .get();
    ProductVariant? matched;
    for (final v in variants) {
      if (v.sku.trim().toLowerCase() == lowerCode || v.id.toLowerCase() == lowerCode) {
        matched = v;
        break;
      }
    }
    if (matched == null) return null;

    final prod = await (_db.select(_db.products)
          ..where((p) => p.id.equals(matched!.productId)))
        .getSingleOrNull();
    final prodName = prod?.name ?? matched.sku;

    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentSales = await (_db.select(_db.saleItems)
          ..where((si) =>
              si.variantId.equals(matched!.id) &
              si.createdAt.isBiggerOrEqualValue(since)))
        .get();
    final sold30d = recentSales.fold<int>(0, (sum, r) => sum + r.qty);

    return AssistantInsight(
      id: 'barcode_lookup',
      title: 'بطاقة الصنف بالباركود (${matched.sku})',
      summary:
          '$prodName — البيع: ${Money(matched.sellPrice).toDisplay()} ج.م | الرصيد: ${matched.quantity}',
      details: [
        'التكلفة: ${Money(matched.costPrice).toDisplay()} ج.م | هامش القطعة: ${Money(matched.sellPrice - matched.costPrice).toDisplay()} ج.م',
        'الرصيد الحالي: ${matched.quantity} قطعة | مبيعات آخر 30 يوم: $sold30d قطعة',
      ],
      followUpPrompts: const [
        'عدل السعر',
        'زود الرصيد',
      ],
    );
  }

  /// Batch 3.1: Fast count of critical alerts (low-stock items + overdue installments).
  Future<int> getCriticalAlertCount() async {
    try {
      final now = DateTime.now();
      final products = await (_db.select(_db.products)
            ..where((p) => p.deletedAt.isNull()))
          .get();
      final minStockByProd = {for (final p in products) p.id: p.minStock};
      final variants = await (_db.select(_db.productVariants)
            ..where((v) => v.deletedAt.isNull()))
          .get();
      int lowCount = 0;
      for (final v in variants) {
        final minS = minStockByProd[v.productId] ?? 5;
        if (v.quantity <= minS) {
          lowCount++;
        }
      }

      final installments = await (_db.select(_db.customerInstallments)
            ..where((i) =>
                i.deletedAt.isNull() &
                (i.status.equals('overdue') | i.status.equals('active'))))
          .get();
      int overdueCount = 0;
      for (final inst in installments) {
        if (inst.status == 'overdue' || inst.endDate.isBefore(now)) {
          overdueCount++;
        }
      }

      return lowCount + overdueCount;
    } catch (_) {
      return 0;
    }
  }

  /// Batch 3.2a: Top-selling sizes & colors for a product (or overall).
  Future<AssistantInsight> getTopVariantsByProductInsight(
    String rawQuery,
  ) async {
    final cleanedTarget = rawQuery
        .replaceFirst(
          RegExp(r'^.*(?:بيتباع\s+في|اكتر\s+مقاس\s+ولون\s*(?:في)?|مقاسات\s+والوان\s*(?:في)?)\s*'),
          '',
        )
        .trim();
    final normTarget = normalizeArabic(cleanedTarget);
    final since = DateTime.now().subtract(const Duration(days: 90));

    final items = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since)))
        .get();

    final filtered = normTarget.isEmpty
        ? items
        : items
            .where((si) => normalizeArabic(si.productName).contains(normTarget))
            .toList();

    if (filtered.isEmpty) {
      return AssistantInsight(
        id: 'top_variants_empty',
        title: 'تحليل المقاسات والألوان الأكثر طلباً',
        summary: normTarget.isEmpty
            ? 'لا توجد بيانات مبيعات كافية خلال آخر 90 يوماً.'
            : 'لم أجد مبيعات مطابقة للصنف "$cleanedTarget".',
      );
    }

    final qtyByCombo = <String, int>{};
    int totalQty = 0;
    for (final si in filtered) {
      final c = si.color.trim().isEmpty || si.color.trim() == '-'
          ? 'لون قياسي'
          : si.color.trim();
      final s = si.size.trim().isEmpty || si.size.trim() == '-'
          ? 'مقاس قياسي'
          : 'مقاس ${si.size.trim()}';
      final key = '$c - $s';
      qtyByCombo[key] = (qtyByCombo[key] ?? 0) + si.qty;
      totalQty += si.qty;
    }

    final sorted = qtyByCombo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final topPct = totalQty > 0 ? (top.value / totalQty * 100).round() : 0;

    return AssistantInsight(
      id: 'top_variants_analysis',
      title: normTarget.isEmpty
          ? 'أكثر المقاسات والألوان مبيعاً'
          : 'أكثر المقاسات والألوان طلباً في "$cleanedTarget"',
      summary: 'الأكثر طلباً: ${top.key} (${top.value} قطعة — $topPct% من المبيعات)',
      details: [
        for (final e in sorted.take(5))
          '${e.key}: ${e.value} قطعة (${totalQty > 0 ? (e.value / totalQty * 100).round() : 0}%)',
      ],
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  /// Batch 3.2b: Compare supplier purchase prices for a given product.
  Future<AssistantInsight> getCheapestSupplierForProductInsight(
    String rawQuery,
  ) async {
    final targetName = rawQuery
        .replaceFirst(
          RegExp(r'^.*(?:جبت\s+منه|ارخص\s+مورد\s*(?:لـ|ل)?|مورد\s+ارخص\s*(?:لـ|ل)?)\s*'),
          '',
        )
        .trim();
    final normTarget = normalizeArabic(targetName);
    if (normTarget.isEmpty) {
      return const AssistantInsight(
        id: 'cheapest_supplier_prompt',
        title: 'مقارنة أسعار الموردين',
        summary: 'اذكر اسم الصنف بعد السؤال، مثال: "ارخص مورد جبت منه تيشيرت".',
      );
    }

    final products = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final matchedProdIds = products
        .where((p) => normalizeArabic(p.name).contains(normTarget))
        .map((p) => p.id)
        .toSet();
    if (matchedProdIds.isEmpty) {
      return AssistantInsight(
        id: 'cheapest_supplier_not_found',
        title: 'مقارنة أسعار الموردين',
        summary: 'لم يتم العثور على صنف باسم "$targetName".',
      );
    }

    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.productId.isIn(matchedProdIds) & v.deletedAt.isNull()))
        .get();
    final variantIds = variants.map((v) => v.id).toSet();

    final pItems = await (_db.select(_db.purchaseItems)
          ..where((pi) => pi.variantId.isIn(variantIds)))
        .get();
    if (pItems.isEmpty) {
      return AssistantInsight(
        id: 'cheapest_supplier_no_purchases',
        title: 'مقارنة أسعار الموردين ($targetName)',
        summary: 'لا توجد فواتير مشتريات مسجلة لهذا الصنف حتى الآن.',
      );
    }

    final purchaseIds = pItems.map((pi) => pi.purchaseId).toSet();
    final purchases = await (_db.select(_db.purchases)
          ..where((p) => p.id.isIn(purchaseIds) & p.deletedAt.isNull()))
        .get();
    final purchaseById = {for (final p in purchases) p.id: p};

    final suppliers = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull()))
        .get();
    final supplierById = {for (final s in suppliers) s.id: s.name};

    final bestCostBySupplier = <String, int>{};
    for (final pi in pItems) {
      final pur = purchaseById[pi.purchaseId];
      if (pur == null) continue;
      final supName = supplierById[pur.supplierId] ?? pur.supplierId;
      final prev = bestCostBySupplier[supName];
      if (prev == null || pi.costPrice < prev) {
        bestCostBySupplier[supName] = pi.costPrice;
      }
    }

    if (bestCostBySupplier.isEmpty) {
      return AssistantInsight(
        id: 'cheapest_supplier_no_purchases',
        title: 'مقارنة أسعار الموردين ($targetName)',
        summary: 'لا توجد فواتير مشتريات نشطة لهذا الصنف.',
      );
    }

    final ranked = bestCostBySupplier.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final cheapest = ranked.first;

    return AssistantInsight(
      id: 'cheapest_supplier_analysis',
      title: 'مقارنة أسعار الموردين ($targetName)',
      summary:
          'أرخص مورد: ${cheapest.key} بسعر ${Money(cheapest.value).toDisplay()} ج.م للقطعة',
      details: [
        for (int i = 0; i < ranked.length; i++)
          '${i + 1}. ${ranked[i].key}: ${Money(ranked[i].value).toDisplay()} ج.م',
      ],
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.purchases,
      requiredFeatureKey: FeatureKeys.purchases,
    );
  }

  /// Batch 3.2c: Peak days and hours analysis from Sales table.
  Future<AssistantInsight> getPeakHoursAndDaysInsight() async {
    final since = DateTime.now().subtract(const Duration(days: 60));
    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(since) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    if (salesRows.isEmpty) {
      return const AssistantInsight(
        id: 'peak_hours_empty',
        title: 'تحليل ساعات وأيام الذروة',
        summary: 'لا توجد فواتير مبيعات كافية في آخر 60 يوماً لتحديد أوقات الذروة.',
      );
    }

    const weekdayNames = {
      DateTime.saturday: 'السبت',
      DateTime.sunday: 'الأحد',
      DateTime.monday: 'الإثنين',
      DateTime.tuesday: 'الثلاثاء',
      DateTime.wednesday: 'الأربعاء',
      DateTime.thursday: 'الخميس',
      DateTime.friday: 'الجمعة',
    };

    final countByDay = <int, int>{};
    final countByHour = <int, int>{};
    for (final s in salesRows) {
      countByDay[s.date.weekday] = (countByDay[s.date.weekday] ?? 0) + 1;
      countByHour[s.date.hour] = (countByHour[s.date.hour] ?? 0) + 1;
    }

    final topDays = countByDay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topHours = countByHour.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String fmtHour(int h) {
      final period = h >= 12 ? 'م' : 'ص';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12 $period';
    }

    final bestDay = weekdayNames[topDays.first.key] ?? '';
    final bestHour = fmtHour(topHours.first.key);

    return AssistantInsight(
      id: 'peak_hours_analysis',
      title: 'تحليل ساعات وأيام الذروة (آخر 60 يوم)',
      summary:
          'أكثر يوم زحمة: $bestDay (${topDays.first.value} فاتورة) | ساعة الذروة: $bestHour (${topHours.first.value} فاتورة)',
      details: [
        'أعلى الأيام نشاطاً: ${topDays.take(3).map((e) => '${weekdayNames[e.key]} (${e.value})').join('، ')}',
        'أعلى الساعات نشاطاً: ${topHours.take(3).map((e) => '${fmtHour(e.key)} (${e.value})').join('، ')}',
        'نصيحة: ركّز تواجد الكاشيرات ونشر العروض قبل ساعة الذروة بساعة.',
      ],
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.reports,
      requiredFeatureKey: FeatureKeys.reports,
    );
  }

  /// Batch 3.2d: Today's AuditLogs & cancelled invoices detector.
  Future<AssistantInsight> getTodayAuditsAndCancellationsInsight() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final audits = await (_db.select(_db.auditLogs)
          ..where((a) =>
              a.createdAt.isBiggerOrEqualValue(todayStart) &
              a.createdAt.isSmallerThanValue(todayEnd))
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
        .get();

    final cancelledSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(todayStart) &
              s.date.isSmallerThanValue(todayEnd) &
              s.status.equals('cancelled')))
        .get();

    final returnsToday = await (_db.select(_db.returns)
          ..where((r) =>
              r.date.isBiggerOrEqualValue(todayStart) &
              r.date.isSmallerThanValue(todayEnd) &
              r.deletedAt.isNull()))
        .get();

    final hasAlerts = cancelledSales.isNotEmpty || audits.isNotEmpty;
    final details = <String>[
      'تعديلات سجل الرقابة اليوم: ${audits.length} عملية.',
      'الفواتير الملغاة اليوم: ${cancelledSales.length} فاتورة.',
      'المرتجعات المسجلة اليوم: ${returnsToday.length} مرتجع.',
      for (final a in audits.take(5))
        '• ${a.action} (${a.entity}) بواسطة ${a.userId}${a.newValue != null ? ' -> ${a.newValue}' : ''}',
    ];

    return AssistantInsight(
      id: 'today_audits_cancellations',
      title: 'كاشف التعديلات والملغيات اليومية',
      summary: hasAlerts
          ? 'تم رصد ${audits.length} تعديل و${cancelledSales.length} فاتورة ملغاة اليوم.'
          : 'لا توجد تعديلات أو فواتير ملغاة مسجلة اليوم.',
      details: details,
      isAlert: cancelledSales.isNotEmpty,
    );
  }

  /// Multi-turn conversation entry point supporting [AssistantActionDraft].
  Future<AssistantTurnResult> askWithDraft(
    String query, {
    AssistantActionDraft? activeDraft,
  }) async {
    final q = normalizeArabic(query);
    if (activeDraft != null) {
      if (q == 'الغاء' || q == 'cancel' || q == 'الغي') {
        return const AssistantTurnResult(
          insights: [
            AssistantInsight(
              id: 'draft_cancelled',
              title: 'تم إلغاء المسودة',
              summary: 'تم إلغاء العملية الجارية دون إجراء أي تغيير.',
            ),
          ],
          activeDraft: null,
        );
      }
      final nextDraft = advanceDraft(activeDraft, query);
      if (!nextDraft.isComplete) {
        return AssistantTurnResult(
          insights: [_buildDraftPromptInsight(nextDraft)],
          activeDraft: nextDraft,
        );
      }
      return AssistantTurnResult(
        insights: [_buildPendingCommandInsight(nextDraft)],
        activeDraft: null,
      );
    }

    final erpDraft = parseErpDraft(query);
    if (erpDraft != null) {
      if (!erpDraft.isComplete) {
        return AssistantTurnResult(
          insights: [_buildDraftPromptInsight(erpDraft)],
          activeDraft: erpDraft,
        );
      }
      return AssistantTurnResult(
        insights: [_buildPendingCommandInsight(erpDraft)],
        activeDraft: null,
      );
    }

    final insights = await ask(query);
    return AssistantTurnResult(insights: insights, activeDraft: null);
  }

  /// 1. Marketing & Finance Clarifications (Discount vs Bundle vs Gift, Funnel, Profit vs Cash)
  Future<List<AssistantInsight>> getMarketingClarificationInsights(
    String rawQuery,
  ) async {
    final q = normalizeArabic(rawQuery);
    final insights = <AssistantInsight>[];

    final askPromo = q.contains('خصم') ||
        q.contains('باقه') ||
        q.contains('هديه') ||
        q.contains('عروض');
    final askFunnel = q.contains('جذب') ||
        q.contains('رفع الفاتوره') ||
        q.contains('استرجاع') ||
        q.contains('تكرار');
    final askProfitVsCash = q.contains('ربح') ||
        q.contains('دفتري') ||
        q.contains('سيوله') ||
        q.contains('الدرج');
    final askAll = !askPromo && !askFunnel && !askProfitVsCash;

    if (askPromo || askAll) {
      insights.add(
        const AssistantInsight(
          id: 'encyclopedia_promo_diff',
          title: 'موسوعة التجارة: الخصم مقابل الباقة مقابل الهدية',
          summary:
              'الخصم يقلل الهامش، الباقة تصرف الراكد، والهدية تحافظ على هيبة السعر.',
          details: [
            'الخصم المباشر (%): يجذب السعر فقط ويحرق هامش الربح؛ استخدمه فقط لتصريف بضاعة راكدة أو موسم منتهٍ.',
            'الباقة (Bundle): اجمع صنفاً سريع الدوران مع صنف بطيء بسعر مجمّع؛ ترفع قيمة الفاتورة وتصرف المخزون دون تدمير سعر القطعة.',
            'الهدية (Gift): تكلفك "سعر التكلفة" فقط وليس سعر البيع، وتحافظ على القيمة المعلنة لصنفك الأساسي أمام العميل.',
          ],
        ),
      );
    }

    if (askFunnel || askAll) {
      insights.add(
        const AssistantInsight(
          id: 'encyclopedia_funnel_diff',
          title: 'موسوعة التجارة: جذب العميل مقابل رفع الفاتورة مقابل الاسترجاع',
          summary:
              'كل مرحلة لها أداة مختلفة: الجذب بالواجهة، الرفع بالبدائل، والاسترجاع بالمتابعة.',
          details: [
            'جذب عميل جديد (Acquisition): يعتمد على صنف واجهة بسعر مغرٍ يدفع العميل لدخول المحل (هدفه عدد الفواتير).',
            'رفع الفاتورة (Upsell / Cross-sell): اقتراح مكملات أو مقاس/فئة أعلى أثناء البيع لزيادة متوسط الفاتورة (AOV).',
            'الاسترجاع والاحتفاظ (Retention): تسجيل العميل ونقاط الولاء وخدمة ما بعد البيع؛ تكلفة بيعه مرة ثانية أقل 5 مرات من جذب عميل جديد.',
          ],
        ),
      );
    }

    if (askProfitVsCash || askAll) {
      final variants = await (_db.select(_db.productVariants)
            ..where((v) => v.deletedAt.isNull() & v.quantity.isBiggerThanValue(0)))
          .get();
      int stockCostPiasters = 0;
      for (final v in variants) {
        stockCostPiasters += v.quantity * v.costPrice;
      }
      final installments = await (_db.select(_db.customerInstallments)
            ..where((i) =>
                i.deletedAt.isNull() &
                (i.status.equals('active') | i.status.equals('overdue'))))
          .get();
      int receivablesPiasters = 0;
      for (final i in installments) {
        receivablesPiasters += i.remainingPiasters;
      }

      insights.add(
        AssistantInsight(
          id: 'encyclopedia_profit_vs_cash',
          title: 'موسوعة التجارة: صافي الربح الدفتري مقابل السيولة في الدرج',
          summary:
              'الربح الدفتري يقيس نجاح البيع، بينما السيولة تقيس الكاش المتاح الآن.',
          details: [
            'صافي الربح الدفتري = مبيعات الفترة - تكلفة البضاعة المباعة - المصروفات (حتى لو كان البيع آجلاً أو تقسيطاً).',
            'السيولة في الدرج تنقص عندما تحوّل الكاش إلى بضاعة جديدة أو أقساط عند العملاء أو سداد موردين.',
            'وضع محلك الآن: لديك مخزون بالتكلفة بقيمة ${Money(stockCostPiasters).toDisplay()} ج.م ومستحقات تقسيط ${Money(receivablesPiasters).toDisplay()} ج.م.',
          ],
          actionLabel: 'فتح الشاشة الآن',
          actionRoute: AssistantActionRoute.reports,
          requiredFeatureKey: FeatureKeys.reports,
        ),
      );
    }

    return insights;
  }

  /// 2. Visual Merchandising tailored to the store activity and top-margin items.
  Future<AssistantInsight> getVisualMerchandisingInsight() async {
    final activityMeta = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals(ReceiptSettingsService.keyStoreActivity)))
        .getSingleOrNull();
    final mobileMeta = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals('feature.${FeatureKeys.mobileImeiUsed}')))
        .getSingleOrNull();
    final dineInMeta = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals('feature.dineIn')))
        .getSingleOrNull();

    final activityText = normalizeArabic(activityMeta?.value ?? '');
    String sector = 'عام';
    if (mobileMeta?.value == 'true' ||
        activityText.contains('موبايل') ||
        activityText.contains('الكترون') ||
        activityText.contains('هواتف')) {
      sector = 'موبايلات وإلكترونيات';
    } else if (dineInMeta?.value == 'true' ||
        activityText.contains('مطعم') ||
        activityText.contains('كافيه')) {
      sector = 'مطاعم وكافيهات';
    } else if (activityText.contains('ملابس') ||
        activityText.contains('ازياء') ||
        activityText.contains('احذيه')) {
      sector = 'ملابس وأزياء';
    } else if (activityText.contains('سوبر') ||
        activityText.contains('بقاله') ||
        activityText.contains('غذائ')) {
      sector = 'سوبر ماركت ومواد غذائية';
    }

    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull() & v.quantity.isBiggerThanValue(0)))
        .get();
    final products = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final productNames = {for (final p in products) p.id: p.name};

    final sortedByProfit = [...variants]
      ..sort((a, b) => (b.sellPrice - b.costPrice).compareTo(a.sellPrice - a.costPrice));
    final topProfitNames = <String>[];
    for (final v in sortedByProfit) {
      final name = productNames[v.productId] ?? v.sku;
      if (!topProfitNames.contains(name)) {
        topProfitNames.add('$name (ربح ${Money(v.sellPrice - v.costPrice).toDisplay()} ج.م)');
      }
      if (topProfitNames.length >= 2) break;
    }

    final String windowTip;
    final String depthTip;
    final String checkoutTip;
    switch (sector) {
      case 'ملابس وأزياء':
        windowTip = 'الواجهة: اعرض طقماً كاملاً متناسق الألوان (بنطلون + تيشيرت + حذاء) لإلهام العميل وبيع أكثر من قطعة.';
        depthTip = 'العمق: ضع الأساسيات (الجينز السادة والبيزيك والمقاسات الكبيرة) في آخر المحل ليمر العميل بكل المعروضات.';
        checkoutTip = 'الكاشير: ضع الشرابات، الأحزمة، والبرفانات الصغيرة لرفع قيمة الفاتورة في اللحظة الأخيرة.';
        break;
      case 'موبايلات وإلكترونيات':
        windowTip = 'الواجهة: أبرز أحدث الأجهزة وعروض الاستبدال/التقسيط بأسعار واضحة لجذب المارة.';
        depthTip = 'العمق: ضع أجهزة الفئة الاقتصادية والطلبات المتكررة في العمق مع طاولة تجربة مضاءة جيداً.';
        checkoutTip = 'الكاشير: ضع الاسكرينات، الجرابات، الكابلات الأصلية، والشواحن لأنها صاحبة أعلى هامش ربح سريع.';
        break;
      case 'مطاعم وكافيهات':
        windowTip = 'الواجهة: أبرز وجبات الكومبو وأسرع العروض اليومية لجذب الزبون المستعجل.';
        depthTip = 'العمق: نظم منطقة التحضير أو الاستلام بحيث يرى الزبون الأصناف المميزة أثناء الانتظار.';
        checkoutTip = 'الكاشير: اعرض الحلويات الصغيرة، المشروبات المعبأة، والإضافات السريعة لزيادة متوسط الفاتورة.';
        break;
      case 'سوبر ماركت ومواد غذائية':
        windowTip = 'الواجهة: اعرض العروض الأسبوعية والسلع الموسمية في مدخل الممر الأول.';
        depthTip = 'العمق: ضع السلع الأساسية اليومية (الألبان، الخبز، المخبوزات) في آخر المحل لإجبار العميل على المرور بباقي الأرفف.';
        checkoutTip = 'الكاشير: ضع الشوكولاتة، العلكة، البطاريات، والمناديل الجيبية عند نقطة الحساب.';
        break;
      default:
        windowTip = 'الواجهة: اعرض 3 منتجات جذابة بصرياً وبأسعار واضحة تمثل هوية المحل وتجذب دخول المارة.';
        depthTip = 'العمق: ضع السلع الأساسية التي يطلبها العميل بالاسم في آخر المحل لزيادة فرص مشاهدته لبقية الأصناف.';
        checkoutTip = 'الكاشير: ضع الرفايع والمكملات منخفضة السعر وسريعة القرار لرفع متوسط الفاتورة.';
    }

    final eyeLevelTip = topProfitNames.isEmpty
        ? 'مستوى العين (120-160 سم): خصص هذا الرف لأعلى الأصناف هامش ربح وليس فقط الأرخص.'
        : 'مستوى العين (للأعلى ربحاً في محلك): اعرض ${topProfitNames.join(' و ')} في مستوى النظر مباشرة.';

    return AssistantInsight(
      id: 'visual_merchandising',
      title: 'هندسة ترتيب المحل وعرض البضاعة ($sector)',
      summary: 'توزيع ذكي لـ 4 مناطق يرفع المبيعات دون إنفاق جنيه واحد على الإعلانات:',
      details: [
        windowTip,
        eyeLevelTip,
        depthTip,
        checkoutTip,
      ],
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  /// 3. Inflation & Replacement Cost Calculator using top-selling store product.
  Future<AssistantInsight> getInflationCalculatorInsight(
    String rawQuery,
  ) async {
    final normalized = Money.normalizeDigits(rawQuery);
    double inflationRate = 15.0;
    final pctMatch = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(normalized) ??
        RegExp(r'(?:بنسبه|تضخم|غلاء|زياده)\s+(\d+(?:\.\d+)?)').firstMatch(normalized);
    if (pctMatch != null) {
      final parsed = double.tryParse(pctMatch.group(1)!);
      if (parsed != null && parsed > 0 && parsed <= 500) {
        inflationRate = parsed;
      }
    }
    final factor = 1.0 + (inflationRate / 100.0);

    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since)))
        .get();

    String? topProductName;
    int currentCostPiasters = 0;
    int currentSellPiasters = 0;

    if (recentItems.isNotEmpty) {
      final qtyByVariant = <String, int>{};
      final latestItemByVariant = <String, SaleItem>{};
      for (final item in recentItems) {
        qtyByVariant[item.variantId] =
            (qtyByVariant[item.variantId] ?? 0) + item.qty;
        latestItemByVariant[item.variantId] = item;
      }
      final topEntry = qtyByVariant.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final sample = latestItemByVariant[topEntry.key]!;
      topProductName = sample.productName;
      currentCostPiasters = sample.costSnapshot;
      currentSellPiasters = sample.priceSnapshot;
    } else {
      final variants = await (_db.select(_db.productVariants)
            ..where((v) => v.deletedAt.isNull() & v.sellPrice.isBiggerThanValue(0)))
          .get();
      if (variants.isNotEmpty) {
        final v = variants.first;
        final prod = await (_db.select(_db.products)
              ..where((p) => p.id.equals(v.productId)))
            .getSingleOrNull();
        topProductName = prod?.name ?? v.sku;
        currentCostPiasters = v.costPrice;
        currentSellPiasters = v.sellPrice;
      }
    }

    final details = <String>[
      'قاعدة تكلفة الاستبدال: لا تسعّر على فاتورة الشراء القديمة؛ سعّر على تكلفة إعادة شراء القطعة اليوم حتى لا يتآكل رأس مالك.',
    ];

    if (topProductName != null && currentSellPiasters > 0) {
      final newCostPiasters = (currentCostPiasters * factor).round();
      final protectedSellPiasters = (currentSellPiasters * factor).round();
      final marginLostIfNotRaised = newCostPiasters - currentCostPiasters;
      details.addAll([
        'مثال عملي على أعلى صنف في محلك ($topProductName):',
        'التكلفة الحالية: ${Money(currentCostPiasters).toDisplay()} ج.م -> تكلفة الاستبدال بعد +${inflationRate.toStringAsFixed(0)}%: ${Money(newCostPiasters).toDisplay()} ج.م.',
        'السعر الحالي: ${Money(currentSellPiasters).toDisplay()} ج.م -> السعر المحمي المقترح: ${Money(protectedSellPiasters).toDisplay()} ج.م (لحماية ${Money(marginLostIfNotRaised).toDisplay()} ج.م من تآكل رأس المال في كل قطعة).',
      ]);
    } else {
      details.add(
        'مثال توضيحي: صنف تكلفته 100 ج.م ويُباع بـ 150 ج.م، عند تضخم ${inflationRate.toStringAsFixed(0)}% تصبح تكلفة استبداله ${(100 * factor).toStringAsFixed(0)} ج.م وسعره المحمي ${(150 * factor).toStringAsFixed(0)} ج.م.',
      );
    }

    return AssistantInsight(
      id: 'inflation_calculator',
      title: 'حاسبة التضخم وقاعدة تكلفة الاستبدال (${inflationRate.toStringAsFixed(0)}%)',
      summary:
          'لحماية رأس المال في التضخم، يجب أن يغطي سعر البيع تكلفة الاستبدال الجديدة وليس القديمة.',
      details: details,
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.products,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  /// 4. Cash Expansion & 50/30/20 Inventory Allocation Advisor.
  Future<AssistantInsight> getCashExpansionAdvisorInsight(
    String rawQuery,
  ) async {
    final normalized = Money.normalizeDigits(rawQuery);
    int? budgetPiasters;
    final numMatch = RegExp(r'(\d{3,9})').firstMatch(normalized);
    if (numMatch != null) {
      final parsedEgp = int.tryParse(numMatch.group(1)!);
      if (parsedEgp != null && parsedEgp > 0) {
        budgetPiasters = parsedEgp * 100;
      }
    }

    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since)))
        .get();
    final soldVariantIds = <String>{};
    final qtyByProductName = <String, int>{};
    for (final item in recentItems) {
      soldVariantIds.add(item.variantId);
      qtyByProductName[item.productName] =
          (qtyByProductName[item.productName] ?? 0) + item.qty;
    }

    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull() & v.quantity.isBiggerThanValue(0)))
        .get();
    int totalStockCost = 0;
    int stagnantStockCost = 0;
    for (final v in variants) {
      final val = v.quantity * v.costPrice;
      totalStockCost += val;
      if (!soldVariantIds.contains(v.id)) {
        stagnantStockCost += val;
      }
    }

    final stagnantPct = totalStockCost > 0
        ? (stagnantStockCost / totalStockCost) * 100.0
        : 0.0;
    final highStagnant = stagnantPct >= 25.0;

    final fastMovers = qtyByProductName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final fastMoverNames = fastMovers.take(3).map((e) => '${e.key} (${e.value} قطعة)').toList();

    String fmtShare(int pct) {
      if (budgetPiasters == null) return '$pct%';
      final share = (budgetPiasters * pct / 100).round();
      return '$pct% (${Money(share).toDisplay()} ج.م)';
    }

    final details = <String>[
      highStagnant
          ? 'تحذير مهم: نسبة المخزون الراكد لديك ${stagnantPct.toStringAsFixed(1)}% (${Money(stagnantStockCost).toDisplay()} ج.م من أصل ${Money(totalStockCost).toDisplay()} ج.م). لا تضخ كل السيولة قبل تصريف الراكد بباقات أو عروض!'
          : 'فحص المخزون: نسبة الراكد ${stagnantPct.toStringAsFixed(1)}% (في النطاق الآمن؛ إجمالي المخزون بالتكلفة ${Money(totalStockCost).toDisplay()} ج.م).',
      fastMoverNames.isEmpty
          ? '${fmtShare(50)} على أسرع الأصناف دوراناً في المحل لضمان عودة الكاش سريعاً.'
          : '${fmtShare(50)} على أسرع الأصناف دوراناً في محلك: ${fastMoverNames.join('، ')}.',
      '${fmtShare(30)} لاختبار بضاعة وموديلات جديدة بكميات تجريبية صغيرة.',
      '${fmtShare(20)} احتياطي تشغيل وسيولة طوارئ للمصروفات وتقلبات السوق.',
    ];

    return AssistantInsight(
      id: 'cash_expansion_50_30_20',
      title: 'مستشار ضخ السيولة وتوسيع البضاعة (50 / 30 / 20)',
      summary: highStagnant
          ? 'تنبيه: مخزونك الراكد مرتفع (${stagnantPct.toStringAsFixed(1)}%) — وزّع السيولة بحذر!'
          : 'خطة توزيع السيولة المتوازنة لحماية التدفق النقدي وتسريع الدوران:',
      details: details,
      isAlert: highStagnant,
      actionLabel: 'فتح الشاشة الآن',
      actionRoute: AssistantActionRoute.purchases,
      requiredFeatureKey: FeatureKeys.purchases,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POST & AD GENERATOR  (WhatsApp / Facebook / Instagram templates)
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates ready-to-copy social-media posts using slow-moving / high-margin
  /// products from the actual database.  Also accepts an optional [platform]
  /// hint ('whatsapp', 'facebook', 'instagram') already extracted from the query.
  Future<AssistantInsight> getPromoPostGeneratorInsight(String rawQuery) async {
    // Detect requested platform from the query
    final q = normalizeArabic(rawQuery);
    final isInsta = q.contains('انستا') || q.contains('instagram') || q.contains('انستاجرام');
    final isFb = q.contains('فيس') || q.contains('facebook') || q.contains('فيسبوك');
    // Default to WhatsApp if nothing specified
    final platform = isInsta ? 'instagram' : (isFb ? 'facebook' : 'whatsapp');

    // Pull store name & phone from appMeta
    String storeName = 'المحل';
    String storePhone = '';
    try {
      final nameMeta = await (_db.select(_db.appMeta)
            ..where((m) => m.key.equals(ReceiptSettingsService.keyStoreName)))
          .getSingleOrNull();
      if (nameMeta != null && nameMeta.value.trim().isNotEmpty) {
        storeName = nameMeta.value.trim();
      }
      final phoneMeta = await (_db.select(_db.appMeta)
            ..where((m) => m.key.equals(ReceiptSettingsService.keyStorePhone)))
          .getSingleOrNull();
      if (phoneMeta != null && phoneMeta.value.trim().isNotEmpty) {
        storePhone = phoneMeta.value.trim();
      }
    } catch (_) {}

    // Find stagnant products with the best margins (slow-movers, high profit)
    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentItems = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.saleItems.saleId)),
    ])
          ..where(
            _db.sales.date.isBiggerOrEqualValue(since) &
                _db.sales.deletedAt.isNull() &
                _db.sales.status.isNotValue('cancelled'),
          ))
        .get();

    final soldVariantIds = recentItems
        .map((r) => r.readTable(_db.saleItems).variantId)
        .toSet();

    final allVariants = await (_db.select(_db.productVariants)
          ..where(
            (v) => v.deletedAt.isNull() & v.quantity.isBiggerThanValue(0),
          ))
        .get();

    final allProducts = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final productNames = {for (final p in allProducts) p.id: p.name};

    // Pick stagnant variants with best margin %, or fallback to best-margin active stock
    final stagnant = allVariants
        .where((v) => !soldVariantIds.contains(v.id) && v.costPrice > 0 && v.sellPrice > 0)
        .toList()
      ..sort((a, b) {
        final mA = (a.sellPrice - a.costPrice) / a.sellPrice;
        final mB = (b.sellPrice - b.costPrice) / b.sellPrice;
        return mB.compareTo(mA);
      });

    final usingFallback = stagnant.isEmpty;
    final candidates = usingFallback
        ? (allVariants.where((v) => v.costPrice > 0 && v.sellPrice > 0).toList()
          ..sort((a, b) {
            final mA = (a.sellPrice - a.costPrice) / a.sellPrice;
            final mB = (b.sellPrice - b.costPrice) / b.sellPrice;
            return mB.compareTo(mA);
          }))
        : stagnant;

    final picks = candidates.take(3).toList();

    if (picks.isEmpty) {
      return const AssistantInsight(
        id: 'promo_post_no_data',
        title: 'مولّد البوستات الإعلانية',
        summary: 'لم أجد أصنافاً برصيد متاح وسعر وتكلفة مسجلين لعمل إعلان عليها الآن.',
        details: [
          'تأكد من إدخال المنتجات والتكاليف والكميات في شاشة المنتجات.',
          'بعد إضافة المنتجات، سيقترح المساعد عليك أفضل الأصناف للترويج فوراً.',
        ],
        followUpPrompts: ['ازاي اضيف منتج جديد؟', 'وضع المحل دلوقتي؟'],
      );
    }

    final isBundleStyle = q.contains('باقه') || q.contains('2+1') || q.contains('قطعتين');
    final isNewArrivalStyle = q.contains('جديد') || q.contains('كولكشن') || q.contains('وصل');

    final String platformLabel;
    final String cta; // call to action line
    switch (platform) {
      case 'facebook':
        platformLabel = 'فيسبوك';
        cta = 'تواصل معنا عبر الرسائل أو اتصل بنا مباشرةً';
        break;
      case 'instagram':
        platformLabel = 'انستاجرام';
        cta = 'راسلنا في الـ DM أو تواصل معنا مباشرةً';
        break;
      default:
        platformLabel = 'واتساب';
        cta = 'راسلنا مباشرةً على واتساب';
    }

    final posts = picks.map((v) {
      final priceBefore = Money(v.sellPrice).toDisplay();
      final discountedPiasters = (v.sellPrice * 0.85).round();
      final priceAfter = Money(discountedPiasters).toDisplay();
      final margin = v.sellPrice > 0
          ? ((v.sellPrice - v.costPrice) / v.sellPrice * 100).round()
          : 0;

      final resolvedName = productNames[v.productId] ?? v.sku;
      final productTitle = resolvedName.trim().isNotEmpty ? resolvedName : 'صنف مميز';
      final colorPart = v.color.trim().isNotEmpty && v.color.trim() != '-'
          ? ' - لون ${v.color.trim()}'
          : '';
      final sizePart = v.size.trim().isNotEmpty && v.size.trim() != '-'
          ? ' - مقاس ${v.size.trim()}'
          : '';

      final String postBody;
      if (isBundleStyle) {
        final twoPrice = Money((v.sellPrice * 1.8).round()).toDisplay();
        postBody = '''
عرض التوفير من $storeName
━━━━━━━━━━━━━━━
$productTitle$colorPart$sizePart
سعر القطعة: $priceBefore ج.م
عرض القطعتين معاً: $twoPrice ج.م فقط (وفر ${(v.sellPrice * 2 - (v.sellPrice * 1.8).round()) ~/ 100} ج.م!)
━━━━━━━━━━━━━━━
$cta${storePhone.isNotEmpty ? ' على: $storePhone' : ''}
العرض ساري حتى نفاد الكمية!'''
            .trim();
      } else if (isNewArrivalStyle) {
        postBody = '''
وصل حديثاً في $storeName
━━━━━━━━━━━━━━━
$productTitle$colorPart$sizePart
جودة ممتازة ومتوفر الآن بكميات محدودة
السعر: $priceBefore ج.م
━━━━━━━━━━━━━━━
$cta${storePhone.isNotEmpty ? ' على: $storePhone' : ''}
احجز قطعتك الآن قبل نفاد المقاسات!'''
            .trim();
      } else {
        postBody = '''
عرض خاص من $storeName
━━━━━━━━━━━━━━━
$productTitle$colorPart$sizePart
السعر الأصلي: $priceBefore ج.م
السعر بعد الخصم: $priceAfter ج.م (وفر ${(v.sellPrice - discountedPiasters) ~/ 100} ج.م!)
━━━━━━━━━━━━━━━
$cta${storePhone.isNotEmpty ? ' على: $storePhone' : ''}
العرض لفترة محدودة - الكمية محدودة!'''
            .trim();
      }

      return 'بوست $platformLabel | هامش الربح الأصلي: $margin%\n---\n$postBody';
    }).toList();

    return AssistantInsight(
      id: 'promo_post_generator_$platform',
      title: 'بوستات إعلانية جاهزة للنسخ ($platformLabel)',
      summary: usingFallback
          ? 'جاهز ${picks.length} بوست لأعلى الأصناف ربحية في محلك — انسخ واستخدم مباشرةً!'
          : 'جاهز ${picks.length} بوست من أصناف راكدة بأعلى هامش ربح في محلك — انسخ واستخدم مباشرةً!',
      details: [
        ...posts,
        'تلميح: جرب "بوست باقة فيسبوك" أو "بوست كولكشن جديد انستا" لتغيير الأسلوب والمنصة.',
      ],
      followUpPrompts: const [
        'اكتب بوست باقة فيسبوك',
        'اكتب بوست كولكشن جديد',
        'استرجع العملاء الغائبين',
      ],
    );
  }

  /// Generates WhatsApp re-engagement messages for customers who haven't bought recently.
  Future<AssistantInsight> getCustomerReEngagementInsight() async {
    String storeName = 'المحل';
    String storePhone = '';
    try {
      final nameMeta = await (_db.select(_db.appMeta)
            ..where((m) => m.key.equals(ReceiptSettingsService.keyStoreName)))
          .getSingleOrNull();
      if (nameMeta != null && nameMeta.value.trim().isNotEmpty) {
        storeName = nameMeta.value.trim();
      }
      final phoneMeta = await (_db.select(_db.appMeta)
            ..where((m) => m.key.equals(ReceiptSettingsService.keyStorePhone)))
          .getSingleOrNull();
      if (phoneMeta != null && phoneMeta.value.trim().isNotEmpty) {
        storePhone = phoneMeta.value.trim();
      }
    } catch (_) {}

    // Customers who bought > 60 days ago and not since
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    final recentSales = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.date.isBiggerOrEqualValue(cutoff) &
                s.deletedAt.isNull() &
                s.status.isNotValue('cancelled'),
          ))
        .get();

    final allSales = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.deletedAt.isNull() &
                s.status.isNotValue('cancelled') &
                s.customerId.isNotNull(),
          ))
        .get();

    final customers = await (_db.select(_db.customers)
          ..where((c) => c.deletedAt.isNull()))
        .get();
    final customerNames = {for (final c in customers) c.id: c.name};

    final recentCustomerIds =
        recentSales.map((s) => s.customerId).whereType<String>().toSet();
    final dormant = allSales
        .where(
          (s) =>
              s.customerId != null &&
              !recentCustomerIds.contains(s.customerId) &&
              (customerNames[s.customerId]?.trim().isNotEmpty ?? false),
        )
        .map((s) => customerNames[s.customerId!]!)
        .toSet()
        .take(5)
        .toList();

    if (dormant.isEmpty) {
      return const AssistantInsight(
        id: 'customer_re_engagement_no_data',
        title: 'استرداد العملاء الغائبين',
        summary: 'لم أجد عملاء غائبين (+60 يوم) في سجل المبيعات.',
        details: [
          'تأكد من تسجيل أسماء العملاء عند البيع للاستفادة من هذه الميزة.',
        ],
      );
    }

    final phoneNote = storePhone.isNotEmpty ? 'على: $storePhone' : '';
    final messages = dormant.map((name) {
      return 'رسالة واتساب لـ $name:\n---\n'
          'السلام عليكم $name،\n'
          'إزيك؟ بنتوقع زيارتك في $storeName!\n'
          'عندنا وصلت بضاعة جديدة وعروض حلوة مستنياك.\n'
          '${storePhone.isNotEmpty ? "تواصل معنا $phoneNote" : "زورنا عندنا"}';
    }).toList();

    return AssistantInsight(
      id: 'customer_re_engagement',
      title: 'استرداد العملاء الغائبين (+60 يوم)',
      summary:
          'وجدت ${dormant.length} عميل لم يشتر منذ أكثر من شهرين — إليك رسائل واتساب جاهزة:',
      details: [
        ...messages,
        'تلميح: اضغط على الرسالة لنسخها ثم أرسلها مباشرةً.',
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SMART SUGGESTIONS (when no intent matched)
  // ─────────────────────────────────────────────────────────────────────────

  // ignore: unused_element
  List<String> _buildDidYouMeanSuggestions(String q) {
    final suggestions = <String>[];

    // Offer context-sensitive suggestions based on partial keywords
    if (q.contains('بيع') || q.contains('مبيع')) {
      suggestions.add('وضع المحل دلوقتي؟');
      suggestions.add('المبيعات قليلة ليه؟');
      suggestions.add('أعلى الأصناف مبيعاً');
    }
    if (q.contains('فلوس') || q.contains('كاش') || q.contains('نقد') || q.contains('مال')) {
      suggestions.add('ربح النهارده كام؟');
      suggestions.add('توزيع السيولة 50/30/20');
    }
    if (q.contains('بضاع') || q.contains('صنف') || q.contains('منتج')) {
      suggestions.add('الأصناف الراكدة');
      suggestions.add('الأصناف قاربت تخلص');
      suggestions.add('أعمل إعلان على الراكد');
    }
    if (q.contains('اعلان') || q.contains('تسويق') || q.contains('ترويج') ||
        q.contains('عرض') || q.contains('خصم')) {
      suggestions.add('اكتب بوست واتساب');
      suggestions.add('اكتب بوست فيسبوك');
      suggestions.add('اعمل عروض على إيه؟');
    }
    if (q.contains('عميل') || q.contains('زبون')) {
      suggestions.add('استرجع العملاء الغائبين');
      suggestions.add('من العملاء المتعثرين في الأقساط؟');
    }
    if (q.contains('مصار') || q.contains('خسار') || q.contains('تكلف')) {
      suggestions.add('تحليل هامش الربح والخسائر');
      suggestions.add('مصاريف الشهر كام؟');
    }

    if (suggestions.isEmpty) {
      suggestions.addAll([
        'وضع المحل دلوقتي؟',
        'ربح النهارده كام؟',
        'اكتب بوست واتساب',
        'الأصناف الراكدة',
        'تضخم الأسعار — ماذا أفعل؟',
        'ازاي أضيف كاشير؟',
      ]);
    }

    return suggestions.take(6).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEEP FINANCIAL, TEAM, PRICING & SEASONAL ADVISORS (100% Offline)
  // ─────────────────────────────────────────────────────────────────────────

  /// Detects margin leaks: excessive invoice/line discounts and items sold at
  /// very thin (<10%) or negative margin over the last 30 days.
  Future<AssistantInsight> getMarginLeakInsight() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(since) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    if (salesRows.isEmpty) {
      return const AssistantInsight(
        id: 'margin_leak_no_data',
        title: 'كاشف تسرب الأرباح والخصومات',
        summary: 'لا توجد مبيعات في آخر 30 يوماً لتحليل تسرب الأرباح.',
        details: ['ابدأ بتسجيل الفواتير ليقوم المساعد بمراقبة الخصومات والهوامش تلقائياً.'],
      );
    }

    final saleIds = salesRows.map((s) => s.id).toList();
    final items = await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.isIn(saleIds)))
        .get();

    final invoiceDiscounts = salesRows.fold<int>(0, (sum, s) => sum + s.discountAmount);
    final lineDiscounts = items.fold<int>(0, (sum, i) => sum + i.lineDiscount);
    final totalDiscounts = invoiceDiscounts + lineDiscounts;
    final grossSubtotal = salesRows.fold<int>(0, (sum, s) => sum + s.subtotal);
    final discountRatio = grossSubtotal > 0 ? (totalDiscounts / grossSubtotal) * 100 : 0.0;

    final leakyItems = <String>[];
    int lossCount = 0;
    for (final item in items) {
      if (item.priceSnapshot <= 0) continue;
      final effectiveUnit = item.qty > 0
          ? (item.lineTotal / item.qty).round()
          : item.priceSnapshot;
      if (effectiveUnit <= item.costSnapshot) {
        lossCount++;
        leakyItems.add(
          '${item.productName}: بيع بسعر ${Money(effectiveUnit).toDisplay()} ج.م (التكلفة ${Money(item.costSnapshot).toDisplay()} ج.م)',
        );
      } else {
        final marginPct = ((effectiveUnit - item.costSnapshot) / effectiveUnit) * 100;
        if (marginPct < 10 && leakyItems.length < 5) {
          leakyItems.add(
            '${item.productName}: هامش ضعيف ${marginPct.toStringAsFixed(1)}% (بيع ${Money(effectiveUnit).toDisplay()} / تكلفة ${Money(item.costSnapshot).toDisplay()})',
          );
        }
      }
    }

    final hasAlert = discountRatio >= 8.0 || lossCount > 0;
    final details = <String>[
      'إجمالي الخصومات الممنوحة (30 يوم): ${Money(totalDiscounts).toDisplay()} ج.م (${discountRatio.toStringAsFixed(1)}% من إجمالي المبيعات).',
      if (lossCount > 0) 'تنبيه حرج: يوجد $lossCount حركة بيع بسعر التكلفة أو أقل!',
      ...leakyItems.take(5),
      hasAlert
          ? 'التوصية: فعّل قيود الخصم اليدوي للكاشير وراجع تسعير الأصناف منخفضة الهامش.'
          : 'أداء التسعير ممتاز: نسبة الخصومات منضبطة ولا يوجد تسرب حاد في الهوامش.',
    ];

    return AssistantInsight(
      id: 'margin_leak_detector',
      title: 'كاشف تسرب الأرباح والخصومات (آخر 30 يوم)',
      summary: hasAlert
          ? 'تحذير: تسرب ربح محتمل — خصومات ${Money(totalDiscounts).toDisplay()} ج.م${lossCount > 0 ? " و$lossCount بيع بخسارة" : ""}'
          : 'الهوامش محمية: إجمالي الخصومات ${Money(totalDiscounts).toDisplay()} ج.م (${discountRatio.toStringAsFixed(1)}%)',
      details: details,
      isAlert: hasAlert,
      actionLabel: 'فتح التقارير التحليلية',
      actionRoute: AssistantActionRoute.reports,
      requiredFeatureKey: FeatureKeys.reports,
      followUpPrompts: const [
        'لو عملت خصم 15% أحتاج أبيع كام؟',
        'قارن أداء الكاشيرات',
        'امنع الخصم اليدوي للكاشير',
      ],
    );
  }

  /// Calculates Monthly & Daily Break-Even sales target from actual operating
  /// expenses and real average gross margin %.
  Future<AssistantInsight> getBreakEvenInsight() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final todayStart = DateTime(now.year, now.month, now.day);

    final monthExpensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.kind.equals('operating') &
              e.expenseDate.isBiggerOrEqualValue(monthStart) &
              e.expenseDate.isSmallerOrEqualValue(monthEnd) &
              e.deletedAt.isNull()))
        .get();
    final monthlyExpenses =
        monthExpensesRows.fold<int>(0, (sum, e) => sum + e.amount);

    final since30 = now.subtract(const Duration(days: 30));
    final recentSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(since30) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    int rev30 = 0;
    int cost30 = 0;
    if (recentSales.isNotEmpty) {
      final ids = recentSales.map((s) => s.id).toList();
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleId.isIn(ids)))
          .get();
      rev30 = recentSales.fold<int>(0, (s, r) => s + r.total);
      cost30 = items.fold<int>(0, (s, i) => s + (i.costSnapshot * i.qty));
    }

    final double marginRatio = rev30 > 0 && rev30 > cost30
        ? (rev30 - cost30) / rev30
        : 0.30; // safe 30% fallback if no history
    final marginPct = (marginRatio * 100).toStringAsFixed(1);

    final monthlyBreakEven =
        marginRatio > 0 ? (monthlyExpenses / marginRatio).round() : 0;
    final dailyBreakEven = (monthlyBreakEven / 30).round();

    final todaySalesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(todayStart) &
              s.date.isSmallerOrEqualValue(monthEnd) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();
    final todayRev = todaySalesRows.fold<int>(0, (s, r) => s + r.total);
    final reachedDaily = todayRev >= dailyBreakEven;
    final remaining = dailyBreakEven > todayRev ? dailyBreakEven - todayRev : 0;

    return AssistantInsight(
      id: 'break_even_calculator',
      title: 'حاسبة نقطة التعادل (Break-Even Point)',
      summary: monthlyExpenses == 0
          ? 'لم تسجل مصاريف تشغيل هذا الشهر بعد (متوسط هامش الربح الحالي $marginPct%).'
          : reachedDaily
              ? 'ممتاز: مبيعات اليوم (${Money(todayRev).toDisplay()} ج.م) تجاوزت تعادل اليوم (${Money(dailyBreakEven).toDisplay()} ج.م)!'
              : 'مطلوب ${Money(remaining).toDisplay()} ج.م إضافية اليوم للوصول لنقطة التعادل اليومية.',
      details: [
        'مصاريف التشغيل المسجلة هذا الشهر: ${Money(monthlyExpenses).toDisplay()} ج.م.',
        'متوسط هامش الربح الفعلي بالمحل: $marginPct%${rev30 == 0 ? " (تقديري لعدم وجود مبيعات سابقة)" : ""}.',
        'هدف المبيعات الشهري لتغطية المصاريف (التعادل): ${Money(monthlyBreakEven).toDisplay()} ج.م.',
        'هدف المبيعات اليومي (التعادل): ${Money(dailyBreakEven).toDisplay()} ج.م — مبيعات اليوم حتى الآن: ${Money(todayRev).toDisplay()} ج.م.',
      ],
      isAlert: monthlyExpenses > 0 && !reachedDaily,
      actionLabel: 'إدارة المصروفات',
      actionRoute: AssistantActionRoute.expenses,
      requiredFeatureKey: FeatureKeys.expenses,
      followUpPrompts: const [
        'وضع المحل دلوقتي؟',
        'كاشف تسرب الأرباح',
        'مصاريف الشهر كام؟',
      ],
    );
  }

  /// Evaluates cashier/staff performance over the last 30 days.
  Future<AssistantInsight> getCashierPerformanceInsight() async {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final salesRows = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(since) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    if (salesRows.isEmpty) {
      return const AssistantInsight(
        id: 'cashier_performance_no_data',
        title: 'تقييم أداء الكاشيرات',
        summary: 'لا توجد فواتير مسجلة في آخر 30 يوماً لتقييم أداء الكاشيرات.',
      );
    }

    final users = await _db.select(_db.users).get();
    final userNames = {for (final u in users) u.id: u.displayName};

    final stats = <String, ({int count, int total, int subtotal, int discount})>{};
    for (final s in salesRows) {
      final cur = stats[s.cashierId] ?? (count: 0, total: 0, subtotal: 0, discount: 0);
      stats[s.cashierId] = (
        count: cur.count + 1,
        total: cur.total + s.total,
        subtotal: cur.subtotal + s.subtotal,
        discount: cur.discount + s.discountAmount,
      );
    }

    final ranked = stats.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    final lines = ranked.map((e) {
      final name = userNames[e.key] ?? e.key;
      final avgBasket = e.value.count > 0 ? (e.value.total / e.value.count).round() : 0;
      final discPct = e.value.subtotal > 0
          ? (e.value.discount / e.value.subtotal) * 100
          : 0.0;
      return '$name: ${Money(e.value.total).toDisplay()} ج.م (${e.value.count} فاتورة | متوسط ${Money(avgBasket).toDisplay()} ج.م | خصومات ${discPct.toStringAsFixed(1)}%)';
    }).toList();

    final topName = userNames[ranked.first.key] ?? ranked.first.key;

    return AssistantInsight(
      id: 'cashier_performance',
      title: 'تقييم أداء الكاشيرات والفريق (آخر 30 يوم)',
      summary: 'الأعلى مبيعاً: $topName بإجمالي ${Money(ranked.first.value.total).toDisplay()} ج.م.',
      details: lines,
      actionLabel: 'إدارة الموظفين والصلاحيات',
      actionRoute: AssistantActionRoute.employees,
      requiredFeatureKey: FeatureKeys.employees,
      followUpPrompts: const [
        'كاشف تسرب الأرباح',
        'امنع الخصم اليدوي للكاشير',
      ],
    );
  }

  /// Simulates "What-If" pricing/discount scenarios using real DB average margin.
  Future<AssistantInsight> getWhatIfPricingInsight(String rawQuery) async {
    final q = normalizeArabic(rawQuery);
    final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(q);
    final pct = numMatch != null
        ? (double.tryParse(numMatch.group(1)!) ?? 10.0).clamp(1.0, 90.0)
        : 10.0;
    final isPriceIncrease = q.contains('زود') || q.contains('رفع') || q.contains('زياده السعر');

    final since30 = DateTime.now().subtract(const Duration(days: 30));
    final recentSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.date.isBiggerOrEqualValue(since30) &
              s.deletedAt.isNull() &
              s.status.isNotValue('cancelled')))
        .get();

    double marginPct = 30.0;
    if (recentSales.isNotEmpty) {
      final ids = recentSales.map((s) => s.id).toList();
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleId.isIn(ids)))
          .get();
      final rev = recentSales.fold<int>(0, (s, r) => s + r.total);
      final cost = items.fold<int>(0, (s, i) => s + (i.costSnapshot * i.qty));
      if (rev > 0 && rev > cost) {
        marginPct = ((rev - cost) / rev) * 100.0;
      }
    }

    if (isPriceIncrease) {
      final allowedDropPct = (pct / (marginPct + pct)) * 100.0;
      return AssistantInsight(
        id: 'what_if_price_increase',
        title: 'محاكاة "ماذا لو؟" — زيادة السعر بنسبة ${pct.toStringAsFixed(0)}%',
        summary:
            'بمتوسط هامش ربحك الحالي (${marginPct.toStringAsFixed(1)}%)، زيادة السعر ${pct.toStringAsFixed(0)}% تحمي ربحك حتى لو انخفضت الكمية بنسبة ${allowedDropPct.toStringAsFixed(1)}%.',
        details: [
          'الربح لكل قطعة يرتفع فوراً، فلا تتردد في تعديل أسعار الأصناف سريعة الدوران لمواكبة التضخم.',
          'نصيحة: ارفع السعر تدريجياً أو قدّم قيمة مضافة (تغليف/ضمان) مع الزيادة.',
        ],
        followUpPrompts: const [
          'حاسبة التضخم 20%',
          'لو عملت خصم 15% أحتاج أبيع كام؟',
        ],
      );
    }

    if (pct >= marginPct) {
      return AssistantInsight(
        id: 'what_if_discount_loss',
        title: 'محاكاة "ماذا لو؟" — خصم ${pct.toStringAsFixed(0)}%',
        summary:
            'تحذير حرج: خصم ${pct.toStringAsFixed(0)}% أكبر من أو يساوي هامش ربحك (${marginPct.toStringAsFixed(1)}%) — ستبيع بخسارة صافية!',
        details: [
          'بدلاً من خصم عام ${pct.toStringAsFixed(0)}%، استخدم "باقة التوفير" (اشتري 2 بسعر مخفض) أو "هدية منخفضة التكلفة".',
          'الحد الأقصى للخصم الآمن دون خسارة هو أقل من ${(marginPct - 5).clamp(1, 80).toStringAsFixed(0)}%.',
        ],
        isAlert: true,
        followUpPrompts: const [
          'الخصم أم الباقة والهدية؟',
          'اكتب بوست باقة فيسبوك',
        ],
      );
    }

    final requiredBoostPct = (pct / (marginPct - pct)) * 100.0;
    return AssistantInsight(
      id: 'what_if_discount_safe',
      title: 'محاكاة "ماذا لو؟" — خصم ${pct.toStringAsFixed(0)}%',
      summary:
          'بهامش ربحك الحالي (${marginPct.toStringAsFixed(1)}%)، خصم ${pct.toStringAsFixed(0)}% يتطلب زيادة عدد المبيعات بنسبة ${requiredBoostPct.toStringAsFixed(1)}% لتحقيق نفس الربح!',
      details: [
        'مثال عملي: لو كنت تبيع 100 قطعة شهرياً، تحتاج لبيع ${(100 + requiredBoostPct).round()} قطعة بالخصم لتجني نفس صافي الربح.',
        'لذلك: لا تطبق الخصم على كل المحل — طبقه فقط على الأصناف الراكدة أو في باقات لرفع قيمة الفاتورة.',
      ],
      followUpPrompts: const [
        'أعمل عروض على إيه؟',
        'اكتب بوست واتساب',
        'الخصم أم الباقة والهدية؟',
      ],
    );
  }

  /// Provides practical seasonal & growth playbooks offline.
  AssistantInsight getSeasonalMarketingPlanInsight(String rawQuery) {
    final q = normalizeArabic(rawQuery);
    String title = 'خطة تسويق عملية لزيادة المبيعات هذا الأسبوع';
    List<String> steps = const [
      '1. قاعدة الـ 48 ساعة للراكد: اختر أبطأ 3 أصناف واكتب لها بوست واتساب/فيسبوك بعرض باقة (اشتري قطعتين بخصم).',
      '2. قاعدة الكاشير (Upsell): درّب الكاشير على عرض صنف مكمل صغير (شراب/إكسسوار/جراب) قبل إغلاق كل فاتورة لرفع المتوسط 15-20%.',
      '3. استرداد العملاء القدامى: أرسل رسالة واتساب شخصية لآخر 10 عملاء لم يزوروا المحل منذ شهرين.',
      '4. عرض الواجهة: ضع أحدث موديل ملفت في الواجهة، وأعلى صنف ربحاً في مستوى العين مباشرة.',
    ];

    if (q.contains('عيد') || q.contains('رمضان') || q.contains('موسم')) {
      title = 'خطة المواسم والأعياد لزيادة الدوران والربحية';
      steps = const [
        '1. قبل الموسم بأسبوعين: جهّز مخزونك من الأسرع دوراناً (50% من السيولة) وتأكد من عدم نفاد المقاسات الأساسية.',
        '2. عروض العائلة والهدايا: اجمع 3 منتجات في "بوكس/باقة جاهزة" بسعر واحد مغرٍ بدل خصم النسبة المئوية.',
        '3. رسائل تذكير مبكرة: راسل عملاءك الدائمين على واتساب قبل الزحمة بـ 5 أيام بميزة "الحجز المسبق أو الأولوية".',
        '4. في ذروة الموسم: قلّل الخصومات اليدوية تماماً وركز على السرعة وتوافر المقاسات.',
      ];
    } else if (q.contains('نهايه الشهر') || q.contains('مرتبات') || q.contains('اخر الشهر')) {
      title = 'تكتيك نهاية الشهر وأيام القبض (Payday Campaign)';
      steps = const [
        '1. أيام 25 إلى 5 في الشهر هي أعلى أيام السيولة — أطلق حملة البوستات ورسائل الواتساب في يوم 27 صباحاً.',
        '2. ركّز في الإعلانات على الأصناف متوسطة وعالية السعر أو نظام التقسيط إن كان مفعلاً.',
        '3. قدّم ميزة "توصيل مجاني" أو "هدية فورية" للفاتورة فوق حد معين لرفع قيمة السلة.',
      ];
    }

    return AssistantInsight(
      id: 'seasonal_marketing_plan',
      title: title,
      summary: 'خطوات عملية مجربة يمكنك تطبيقها اليوم في محلك بدون تكلفة إعلانات مدفوعة:',
      details: steps,
      followUpPrompts: const [
        'اكتب بوست واتساب',
        'استرجع العملاء الغائبين',
        'ترتيب المحل وعرض البضاعة',
      ],
    );
  }

  /// Automatic Daily Smart Briefing shown when the assistant opens.
  Future<List<AssistantInsight>> getDailyBriefing() async {
    return [
      await getTodayProfitInsight(),
      await getStockoutVelocityInsight(),
      await getOverdueInstallmentsInsight(),
      await getSuppliersDuesInsight(),
      await getMonthlyBudgetComparisonInsight(),
    ];
  }

  Future<List<AssistantInsight>> ask(String query) async {
    final q = normalizeArabic(query);
    if (q.isEmpty) {
      return getDailyBriefing();
    }

    // 1. Direct settings execution command
    final cmdInsight = parseCommand(query);
    if (cmdInsight != null) {
      return [cmdInsight];
    }

    // 1b. Direct complete ERP action command
    final erpDraft = parseErpDraft(query);
    if (erpDraft != null) {
      return [
        erpDraft.isComplete
            ? _buildPendingCommandInsight(erpDraft)
            : _buildDraftPromptInsight(erpDraft),
      ];
    }

    // 2. Interactive How-To Guide
    final howTo = matchHowToGuide(query);
    if (howTo != null) {
      return [howTo];
    }

    final results = <AssistantInsight>[];

    // 3. Direct barcode / SKU or product lookup
    final barcodeMatch = await searchByBarcodeOrSkuInsight(query);
    if (barcodeMatch != null) {
      results.add(barcodeMatch);
    } else {
      final productMatch = await searchProductByNameInsight(query);
      if (productMatch != null) {
        results.add(productMatch);
      }
    }

    // Batch 2: End-of-Day Report & WhatsApp Installment Reminder
    if (q.contains('تقرير قفله اليوم') ||
        q.contains('قفله اليوم') ||
        q.contains('ملخص قفله')) {
      results.add(await getEndOfDayReportInsight());
    }
    if (q.contains('تذكير قسط') || q.contains('رساله قسط')) {
      results.add(await getInstallmentReminderInsight(query));
    }

    // Batch 3: Variants, Cheapest Supplier, Peak Hours, Today Audits
    if (q.contains('مقاس ولون') ||
        q.contains('اكتر مقاس') ||
        q.contains('مقاسات والوان')) {
      results.add(await getTopVariantsByProductInsight(query));
    }
    if (q.contains('ارخص مورد') || q.contains('جبت منه')) {
      results.add(await getCheapestSupplierForProductInsight(query));
    }
    if (q.contains('ساعه زحمه') ||
        q.contains('ساعات الذروه') ||
        q.contains('ايام الذروه') ||
        q.contains('اكتر يوم') ||
        q.contains('زحمه')) {
      results.add(await getPeakHoursAndDaysInsight());
    }
    if (q.contains('اتعدل النهارده') ||
        q.contains('تعديلات النهارده') ||
        q.contains('ملغيات') ||
        q.contains('الفواتير الملغاه')) {
      results.add(await getTodayAuditsAndCancellationsInsight());
    }

    // 4. Post & Ad Generator intents
    final isPostRequest = q.contains('بوست') ||
        q.contains('منشور') ||
        q.contains('اعلان') ||
        q.contains('اعمل اعلان') ||
        q.contains('اكتب اعلان') ||
        q.contains('واتساب') ||
        q.contains('فيسبوك') ||
        q.contains('انستا') ||
        q.contains('انستاجرام') ||
        q.contains('نص اعلاني') ||
        q.contains('محتوي تسويقي') ||
        q.contains('رسايل') ||
        q.contains('ارسل للعملاء') ||
        q.contains('اكتب نص') ||
        q.contains('اعلن عن');
    if (isPostRequest) {
      results.add(await getPromoPostGeneratorInsight(query));
    }

    // Customer re-engagement intents
    final isReEngagement = q.contains('استرجع العملاء') ||
        q.contains('العملاء الغايبين') ||
        q.contains('العملاء مش شاريين') ||
        q.contains('عملاء قديمين') ||
        q.contains('زبائن مش جايين') ||
        q.contains('استعاده العملاء') ||
        q.contains('رسايل واتساب للعملاء') ||
        q.contains('تواصل مع العملاء');
    if (isReEngagement) {
      results.add(await getCustomerReEngagementInsight());
    }

    // 4b. Margin Leak, Break-Even, Cashier Performance, What-If & Seasonal Plan
    if (q.contains('تسرب') ||
        q.contains('تحليل هامش') ||
        q.contains('خصومات مبالغ') ||
        q.contains('الخصومات اللي اتعملت') ||
        q.contains('بخسر في ايه')) {
      results.add(await getMarginLeakInsight());
    }
    if (q.contains('نقطه التعادل') ||
        q.contains('التعادل') ||
        q.contains('اغطي مصاريفي') ||
        q.contains('تغطيه المصاريف') ||
        q.contains('ابيع بكام')) {
      results.add(await getBreakEvenInsight());
    }
    if (q.contains('اداء الكاشير') ||
        q.contains('تقييم الكاشير') ||
        q.contains('قارن الكاشير') ||
        q.contains('احسن كاشير') ||
        q.contains('اداء الموظفين') ||
        q.contains('شغل الكاشيرات')) {
      results.add(await getCashierPerformanceInsight());
    }
    if (q.contains('ماذا لو') ||
        q.contains('لو عملت خصم') ||
        q.contains('لو زودت السعر') ||
        q.contains('لو رفعت السعر') ||
        q.contains('لو نزلت السعر') ||
        q.contains('احتاج ابيع كام')) {
      results.add(await getWhatIfPricingInsight(query));
    }
    if (q.contains('خطه تسويق') ||
        q.contains('ازاي ازود المبيعات') ||
        q.contains('ازود مبيعاتي') ||
        q.contains('ازود البيع') ||
        q.contains('موسم') ||
        q.contains('عيد') ||
        q.contains('رمضان') ||
        q.contains('نهايه الشهر') ||
        q.contains('مرتبات')) {
      results.add(getSeasonalMarketingPlanInsight(query));
    }

    // 5. Commerce, Marketing & Inflation Encyclopedia intents
    if (q.contains('الفرق') ||
        q.contains('باقه') ||
        q.contains('هديه') ||
        q.contains('جذب عميل') ||
        q.contains('رفع الفاتوره') ||
        q.contains('دفتري') ||
        q.contains('الربح والسيوله') ||
        q.contains('فرق بين الخصم') ||
        q.contains('فرق بين الباقه') ||
        q.contains('الفرق التسويقي') ||
        q.contains('استراتيجيه') ||
        q.contains('خطه تسويقيه')) {
      results.addAll(await getMarketingClarificationInsights(query));
    }
    if (q.contains('ترتيب المحل') ||
        q.contains('عرض البضاعه') ||
        q.contains('هندسه') ||
        q.contains('مستوي العين') ||
        q.contains('الواجهه') ||
        q.contains('ارتب المحل') ||
        q.contains('شباك العرض') ||
        q.contains('ترتيب الرفوف') ||
        q.contains('عرض البضايع') ||
        q.contains('تجميل المحل')) {
      results.add(await getVisualMerchandisingInsight());
    }
    if (q.contains('تضخم') ||
        q.contains('غلاء') ||
        q.contains('تكلفه الاستبدال') ||
        q.contains('رفع الاسعار') ||
        q.contains('الاسعار زادت') ||
        q.contains('كل حاجه غليت') ||
        q.contains('المورد رفع') ||
        q.contains('مش قادر اسعر') ||
        q.contains('كيف اسعر') ||
        q.contains('تسعير') ||
        q.contains('سعر البيع') ||
        q.contains('تكلفه الشراء')) {
      results.add(await getInflationCalculatorInsight(query));
    }
    if (q.contains('سيوله') ||
        q.contains('توسيع البضاعه') ||
        q.contains('بضاعه جديده') ||
        q.contains('50/30/20') ||
        q.contains('اشتري بضاعه') ||
        q.contains('معايا فلوس') ||
        q.contains('عندي كاش') ||
        q.contains('ناوي اشتري') ||
        q.contains('في فرصه') ||
        q.contains('ضخ فلوس') ||
        q.contains('استثمار') ||
        q.contains('توسعه')) {
      results.add(await getCashExpansionAdvisorInsight(query));
    }

    // 6. Deepened Business Advisor intents (expanded synonyms)
    if (q.contains('وضع المحل') ||
        q.contains('نبض المحل') ||
        q.contains('حاله المحل') ||
        q.contains('ملخص دلوقتي') ||
        q.contains('احسسني') ||
        q.contains('اخبرني عن') ||
        q.contains('عامل ايه') ||
        q.contains('شكل الدنيا عامله ايه')) {
      results.add(await getStorePulseInsight());
    }
    if (q.contains('المبيعات قليله') ||
        q.contains('قليله ليه') ||
        q.contains('انخفضت') ||
        q.contains('مقارنه الفترات') ||
        q.contains('تشخيص') ||
        q.contains('البيع واطي') ||
        q.contains('البيع مش كويس') ||
        q.contains('الناس مش شايله') ||
        q.contains('ليه البيع وقف') ||
        q.contains('مبيعاتي نازله') ||
        q.contains('انا مش بكسب')) {
      results.add(await getSalesDiagnosisInsight());
    }
    if (q.contains('عروض') ||
        q.contains('تخفيضات') ||
        q.contains('تصريف') ||
        q.contains('اوكازيون') ||
        q.contains('اعمل خصم') ||
        q.contains('انزل سعر') ||
        q.contains('اسيح البضاعه') ||
        q.contains('خصومات') ||
        q.contains('مواسم')) {
      results.add(await getPromotionsAdvisorInsight());
    }

    if (q.contains('ربح') ||
        q.contains('مكسب') ||
        q.contains('كسبت') ||
        q.contains('ارباح') ||
        q.contains('النهارده') ||
        q.contains('اليوم') ||
        q.contains('امبارح') ||
        q.contains('امس') ||
        q.contains('صافي الربح') ||
        q.contains('المكسب الصافي') ||
        q.contains('كسبنا قد ايه')) {
      results.add(await getTodayProfitInsight());
    }
    if (q.contains('اعلي') ||
        q.contains('اكثر') ||
        q.contains('مبيعا') ||
        q.contains('اصناف') ||
        q.contains('افضل منتج') ||
        q.contains('اكتر بضاعه') ||
        q.contains('بيتباع كتير') ||
        q.contains('الاكثر طلبا')) {
      results.add(await getTopProfitableProductsInsight());
    }
    if (q.contains('راكد') ||
        q.contains('مركون') ||
        q.contains('مبيعتش') ||
        q.contains('مبتتباعش') ||
        q.contains('بطي') ||
        q.contains('مش بيتباع') ||
        q.contains('قاعد في المخزن') ||
        q.contains('محدش اشتراه') ||
        q.contains('صنف واقف')) {
      results.add(await getStagnantProductsInsight());
    }
    if (q.contains('نفاد') ||
        q.contains('نواقص') ||
        q.contains('ناقص') ||
        q.contains('خلص') ||
        q.contains('هيخلص') ||
        q.contains('مخزون') ||
        q.contains('الكميه قليله') ||
        q.contains('اوشك علي النفاد') ||
        q.contains('عاوز اشتري')) {
      results.add(await getStockoutVelocityInsight());
    }
    if (q.contains('مصاريف') ||
        q.contains('مصروف') ||
        q.contains('صرفنا') ||
        q.contains('ميزانيه') ||
        q.contains('المصروفات') ||
        q.contains('الايجار') ||
        q.contains('الكهربا') ||
        q.contains('الرواتب') ||
        q.contains('صرف قد ايه')) {
      results.add(await getMonthlyBudgetComparisonInsight());
    }
    if (q.contains('قسط') ||
        q.contains('اقساط') ||
        q.contains('متاخر') ||
        q.contains('متعثر') ||
        q.contains('الديون') ||
        q.contains('العملاء المديونين') ||
        q.contains('مين محلوش')) {
      results.add(await getOverdueInstallmentsInsight());
    }
    if (q.contains('مورد') ||
        q.contains('علينا') ||
        q.contains('عليا') ||
        q.contains('مديون') ||
        q.contains('مستحقات') ||
        q.contains('فلوس لمين') ||
        q.contains('الموردين') ||
        q.contains('ندفع لمين') ||
        q.contains('فواتير المشتريات')) {
      results.add(await getSuppliersDuesInsight());
    }

    if (results.isEmpty) {
      final suggestions = _buildDidYouMeanSuggestions(q);
      return [
        AssistantInsight(
          id: 'no_direct_match',
          title: 'لم أفهم سؤالك بالكامل — هل تقصد؟',
          summary: 'جرب إحدى هذه الأسئلة أو اكتب بكلام مختلف:',
          details: suggestions,
        ),
        await getTodayProfitInsight(),
        await getStockoutVelocityInsight(),
      ];
    }
    return results;
  }
}
