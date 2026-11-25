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
}

class AssistantPendingCommand {
  final AssistantCommandKind kind;
  final String title;
  final String description;
  final bool? boolValue;
  final String? stringValue;
  final bool touchesFeatureGate;

  const AssistantPendingCommand({
    required this.kind,
    required this.title,
    required this.description,
    this.boolValue,
    this.stringValue,
    this.touchesFeatureGate = false,
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

    if (q.contains('خصم') || q.contains('منع الخصم') || q.contains('تعديل السعر')) {
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

    if (q.contains('سعر') || q.contains('صنف') || q.contains('منتج')) {
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

    return null;
  }

  /// Executes an approved [AssistantPendingCommand] strictly for `admin` role.
  Future<String> executeCommand(
    AssistantPendingCommand cmd, {
    required String userId,
    required String userRole,
    required FeatureGate gate,
  }) async {
    if (userRole.toLowerCase() != 'admin') {
      throw Exception('غير مصرح: تنفيذ تعديلات الإعدادات متاح لحساب المدير (admin) فقط');
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
    }
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

    // 2. Interactive How-To Guide
    final howTo = matchHowToGuide(query);
    if (howTo != null) {
      return [howTo];
    }

    final results = <AssistantInsight>[];

    // 3. Direct product lookup
    final productMatch = await searchProductByNameInsight(query);
    if (productMatch != null) {
      results.add(productMatch);
    }

    // 4. Deepened Business Advisor intents
    if (q.contains('وضع المحل') ||
        q.contains('نبض المحل') ||
        q.contains('حاله المحل') ||
        q.contains('ملخص دلوقتي')) {
      results.add(await getStorePulseInsight());
    }
    if (q.contains('المبيعات قليله') ||
        q.contains('قليله ليه') ||
        q.contains('انخفضت') ||
        q.contains('مقارنه الفترات') ||
        q.contains('تشخيص')) {
      results.add(await getSalesDiagnosisInsight());
    }
    if (q.contains('عروض') ||
        q.contains('تخفيضات') ||
        q.contains('تصريف') ||
        q.contains('اوكازيون')) {
      results.add(await getPromotionsAdvisorInsight());
    }

    if (q.contains('ربح') ||
        q.contains('مكسب') ||
        q.contains('كسبت') ||
        q.contains('ارباح') ||
        q.contains('النهارده') ||
        q.contains('اليوم') ||
        q.contains('امبارح') ||
        q.contains('امس')) {
      results.add(await getTodayProfitInsight());
    }
    if (q.contains('اعلي') ||
        q.contains('اكثر') ||
        q.contains('مبيعا') ||
        q.contains('اصناف')) {
      results.add(await getTopProfitableProductsInsight());
    }
    if (q.contains('راكد') ||
        q.contains('مركون') ||
        q.contains('مبيعتش') ||
        q.contains('مبتتباعش') ||
        q.contains('بطي')) {
      results.add(await getStagnantProductsInsight());
    }
    if (q.contains('نفاد') ||
        q.contains('نواقص') ||
        q.contains('ناقص') ||
        q.contains('خلص') ||
        q.contains('هيخلص') ||
        q.contains('مخزون')) {
      results.add(await getStockoutVelocityInsight());
    }
    if (q.contains('مصاريف') ||
        q.contains('مصروف') ||
        q.contains('صرفنا') ||
        q.contains('ميزانيه')) {
      results.add(await getMonthlyBudgetComparisonInsight());
    }
    if (q.contains('قسط') ||
        q.contains('اقساط') ||
        q.contains('متاخر') ||
        q.contains('متعثر')) {
      results.add(await getOverdueInstallmentsInsight());
    }
    if (q.contains('مورد') ||
        q.contains('علينا') ||
        q.contains('عليا') ||
        q.contains('مديون') ||
        q.contains('مستحقات') ||
        q.contains('فلوس لمين')) {
      results.add(await getSuppliersDuesInsight());
    }

    if (results.isEmpty) {
      return [
        const AssistantInsight(
          id: 'no_direct_match',
          title: 'ملخص تنفيذي سريع',
          summary:
              'لم أجد مطابقة مباشرة، إليك أحدث المؤشرات اليومية:',
          details: [
            'جرب: "وضع المحل دلوقتي؟"، "المبيعات قليلة ليه؟"، "أعمل عروض على إيه؟"، أو "ازاي أضيف كاشير؟".',
          ],
        ),
        await getTodayProfitInsight(),
        await getStockoutVelocityInsight(),
      ];
    }
    return results;
  }
}
