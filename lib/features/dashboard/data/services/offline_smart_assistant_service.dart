import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';

enum AssistantActionRoute {
  reports,
  products,
  purchases,
  installments,
  expenses,
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

  const AssistantInsight({
    required this.id,
    required this.title,
    required this.summary,
    this.details = const [],
    this.isAlert = false,
    this.actionLabel,
    this.actionRoute,
    this.requiredFeatureKey,
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

    final results = <AssistantInsight>[];

    // Check direct product lookup first if query mentions a product name
    final productMatch = await searchProductByNameInsight(query);
    if (productMatch != null) {
      results.add(productMatch);
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
        AssistantInsight(
          id: 'no_direct_match',
          title: 'ملخص تنفيذي سريع',
          summary:
              'لم أجد صنفاً مطابقاً بالضبط، إليك أحدث المؤشرات اليومية:',
          details: const [
            'جرب السؤال: "كسبت كام النهارده" أو "علينا كام للموردين" أو اكتب اسم صنف.',
          ],
        ),
        await getTodayProfitInsight(),
        await getStockoutVelocityInsight(),
      ];
    }
    return results;
  }
}
