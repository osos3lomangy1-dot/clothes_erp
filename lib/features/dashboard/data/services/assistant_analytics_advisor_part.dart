part of 'offline_smart_assistant_service.dart';

extension AssistantAnalyticsAdvisorPart on OfflineSmartAssistantService {
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
      actionLabel: 'فتح شاشة المخزون',
      actionRoute: AssistantActionRoute.inventory,
      requiredFeatureKey: FeatureKeys.inventory,
    );
  }

  static const String _keyDismissedLowStock =
      'assistant.dismissed_low_stock_variants';
  static const String _keyDismissedOverdueInstallments =
      'assistant.dismissed_overdue_installments';

  Future<Set<String>> _getDismissedIds(String key) async {
    try {
      final row = await (_db.select(_db.appMeta)
            ..where((m) => m.key.equals(key)))
          .getSingleOrNull();
      if (row == null || row.value.trim().isEmpty) return <String>{};
      final decoded = jsonDecode(row.value);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  Future<void> _saveDismissedIds(String key, Set<String> ids) async {
    try {
      if (ids.isEmpty) {
        await (_db.delete(_db.appMeta)..where((m) => m.key.equals(key))).go();
        return;
      }
      await _db.into(_db.appMeta).insertOnConflictUpdate(
            AppMetaCompanion.insert(
              key: key,
              value: jsonEncode(ids.toList()),
              updatedAt: DateTime.now(),
            ),
          );
    } catch (_) {}
  }

  /// Marks all currently low-stock variants as dismissed so discontinued items
  /// stop triggering the sidebar badge unless restocked above minStock first.
  Future<void> dismissStockoutAlerts() async {
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

    final dismissed = await _getDismissedIds(_keyDismissedLowStock);
    for (final r in stockRows) {
      final v = r.readTable(_db.productVariants);
      final p = r.readTable(_db.products);
      final sold = qtySold30d[v.id] ?? 0;
      final dailyRate = sold / 30.0;
      final daysLeft = dailyRate > 0 ? (v.quantity / dailyRate).floor() : 999;
      if (v.quantity <= p.minStock || (dailyRate > 0 && daysLeft <= 7)) {
        dismissed.add(v.id);
      }
    }
    await _saveDismissedIds(_keyDismissedLowStock, dismissed);
  }

  /// Marks all currently overdue installments as dismissed from the badge.
  Future<void> dismissOverdueInstallmentAlerts() async {
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
    final dismissed = await _getDismissedIds(_keyDismissedOverdueInstallments);
    for (final r in rows) {
      dismissed.add(r.id);
    }
    await _saveDismissedIds(_keyDismissedOverdueInstallments, dismissed);
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

    final dismissed = await _getDismissedIds(_keyDismissedLowStock);
    bool dismissedChanged = false;

    final alerts = <String>[];
    for (final r in stockRows) {
      final v = r.readTable(_db.productVariants);
      final p = r.readTable(_db.products);
      final sold = qtySold30d[v.id] ?? 0;
      final dailyRate = sold / 30.0;
      final daysLeft = dailyRate > 0 ? (v.quantity / dailyRate).floor() : 999;

      final isLow =
          v.quantity <= p.minStock || (dailyRate > 0 && daysLeft <= 7);
      if (!isLow) {
        if (dismissed.remove(v.id)) {
          dismissedChanged = true;
        }
        continue;
      }

      if (dismissed.contains(v.id)) continue;

      final msg = dailyRate > 0
          ? '${p.name}: متبقي ${v.quantity} (يكفي ~$daysLeft يوم)'
          : '${p.name}: متبقي ${v.quantity} (أقل من حد الطلب ${p.minStock})';
      alerts.add(msg);
    }

    if (dismissedChanged) {
      await _saveDismissedIds(_keyDismissedLowStock, dismissed);
    }

    return AssistantInsight(
      id: 'stockout_alerts',
      title: 'توقع نفاد المخزون ومعدل البيع اليومي',
      summary: alerts.isEmpty
          ? 'مستويات المخزون آمنة حالياً'
          : '${alerts.length} صنف بحاجة لإعادة طلب قريباً',
      details: alerts.take(8).toList(),
      isAlert: alerts.isNotEmpty,
      actionLabel: 'فتح شاشة المخزون',
      actionRoute: AssistantActionRoute.inventory,
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

    final dismissedInst =
        await _getDismissedIds(_keyDismissedOverdueInstallments);
    final activeRows =
        rows.where((r) => !dismissedInst.contains(r.id)).toList();

    final totalOverdue =
        activeRows.fold<int>(0, (s, r) => s + r.remainingPiasters);

    return AssistantInsight(
      id: 'overdue_installments',
      title: 'الأقساط المتأخرة',
      summary: activeRows.isEmpty
          ? 'لا توجد عقود تقسيط متأخرة'
          : '${activeRows.length} عقد متأخر بإجمالي ${Money(totalOverdue).toDisplay()} ج.م',
      details: [
        for (final r in activeRows.take(6))
          'عقد #${r.id.substring(0, r.id.length >= 6 ? 6 : r.id.length)} — متبقي ${Money(r.remainingPiasters).toDisplay()} ج.م',
      ],
      isAlert: activeRows.isNotEmpty,
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
    final normQuery = OfflineSmartAssistantService.normalizeArabic(rawQuery);
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
      final normProd = OfflineSmartAssistantService.normalizeArabic(p.name);
      final fullName = OfflineSmartAssistantService.normalizeArabic('${p.name} ${v.size} ${v.color} ${v.sku}');
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
      final norm = OfflineSmartAssistantService.normalizeArabic(targetName);
      Customer? matched;
      for (final c in customers) {
        if (OfflineSmartAssistantService.normalizeArabic(c.name) == norm ||
            OfflineSmartAssistantService.normalizeArabic(c.name).contains(norm)) {
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
      final dismissedVariants = await _getDismissedIds(_keyDismissedLowStock);
      bool dismissedChanged = false;
      int lowCount = 0;
      for (final v in variants) {
        final minS = minStockByProd[v.productId] ?? 5;
        if (v.quantity <= minS) {
          if (!dismissedVariants.contains(v.id)) {
            lowCount++;
          }
        } else if (dismissedVariants.remove(v.id)) {
          dismissedChanged = true;
        }
      }
      if (dismissedChanged) {
        await _saveDismissedIds(_keyDismissedLowStock, dismissedVariants);
      }

      final dismissedInst =
          await _getDismissedIds(_keyDismissedOverdueInstallments);
      final installments = await (_db.select(_db.customerInstallments)
            ..where((i) =>
                i.deletedAt.isNull() &
                i.remainingPiasters.isBiggerThanValue(0) &
                (i.status.equals('overdue') | i.status.equals('active'))))
          .get();
      int overdueCount = 0;
      for (final inst in installments) {
        if ((inst.status == 'overdue' || inst.endDate.isBefore(now)) &&
            !dismissedInst.contains(inst.id)) {
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
    final normTarget = OfflineSmartAssistantService.normalizeArabic(cleanedTarget);
    final since = DateTime.now().subtract(const Duration(days: 90));

    final items = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since)))
        .get();

    final filtered = normTarget.isEmpty
        ? items
        : items
            .where((si) => OfflineSmartAssistantService.normalizeArabic(si.productName).contains(normTarget))
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
    final normTarget = OfflineSmartAssistantService.normalizeArabic(targetName);
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
        .where((p) => OfflineSmartAssistantService.normalizeArabic(p.name).contains(normTarget))
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

  /// Detailed Zakat Calculator for Money & Trade Goods (100% Offline).
  Future<AssistantInsight> getZakatCalculatorInsight({
    required double goldGramPrice24Egp,
    int extraBankCashPiasters = 0,
    int extraDebtsOnBusinessPiasters = 0,
    bool isGregorianYear = false,
  }) async {
    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull() & v.quantity.isBiggerThanValue(0)))
        .get();
    int stockSellPiasters = 0;
    int stockCostPiasters = 0;
    for (final v in variants) {
      stockSellPiasters += v.quantity * v.sellPrice;
      stockCostPiasters += v.quantity * v.costPrice;
    }

    final wallets = await (_db.select(_db.cashWallets)
          ..where((w) => w.deletedAt.isNull() & w.isActive.equals(true)))
        .get();
    final walletsCashPiasters =
        wallets.fold<int>(0, (sum, w) => sum + w.currentBalance);

    final latestShift = await (_db.select(_db.shifts)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();
    int drawerCashPiasters = 0;
    if (latestShift != null) {
      if (latestShift.closedAt != null) {
        drawerCashPiasters = latestShift.countedBalance ??
            latestShift.expectedBalance ??
            latestShift.openingBalance;
      } else {
        final openAt = latestShift.openedAt;
        final cashSalesRows = await (_db.select(_db.sales)
              ..where((s) =>
                  s.date.isBiggerOrEqualValue(openAt) &
                  s.deletedAt.isNull() &
                  s.status.isNotValue('cancelled') &
                  s.paymentMethod.equals('cash')))
            .get();
        final cashReturnsRows = await (_db.select(_db.returns)
              ..where((r) =>
                  r.date.isBiggerOrEqualValue(openAt) &
                  r.deletedAt.isNull() &
                  r.paymentMethod.equals('cash')))
            .get();
        final cashExpensesRows = await (_db.select(_db.expenses)
              ..where((e) =>
                  e.expenseDate.isBiggerOrEqualValue(openAt) &
                  e.deletedAt.isNull()))
            .get();
        final salesSum = cashSalesRows.fold<int>(0, (s, r) => s + r.total);
        final retSum =
            cashReturnsRows.fold<int>(0, (s, r) => s + r.refundAmount);
        final expSum = cashExpensesRows.fold<int>(0, (s, e) => s + e.amount);
        drawerCashPiasters =
            latestShift.openingBalance + salesSum - retSum - expSum;
        if (drawerCashPiasters < 0) drawerCashPiasters = 0;
      }
    }

    final totalDbCashPiasters = walletsCashPiasters + drawerCashPiasters;

    final installments = await (_db.select(_db.customerInstallments)
          ..where((i) =>
              i.deletedAt.isNull() &
              (i.status.equals('active') | i.status.equals('overdue'))))
        .get();
    final receivablesPiasters =
        installments.fold<int>(0, (sum, i) => sum + i.remainingPiasters);

    final suppliers = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull() & s.balance.isBiggerThanValue(0)))
        .get();
    final supplierDebtPiasters =
        suppliers.fold<int>(0, (sum, s) => sum + s.balance);

    final nisabPiasters = (85 * goldGramPrice24Egp * 100).round();
    final totalAssetsPiasters = stockSellPiasters +
        totalDbCashPiasters +
        extraBankCashPiasters +
        receivablesPiasters;
    final totalDeductionsPiasters =
        supplierDebtPiasters + extraDebtsOnBusinessPiasters;
    final zakatPoolPiasters = totalAssetsPiasters - totalDeductionsPiasters;

    final reachedNisab =
        zakatPoolPiasters >= nisabPiasters && zakatPoolPiasters > 0;
    final rate = isGregorianYear ? 0.02577 : 0.025;
    final zakatDuePiasters =
        reachedNisab ? (zakatPoolPiasters * rate).round() : 0;

    return AssistantInsight(
      id: 'zakat_calculator',
      title:
          'حاسبة زكاة المال وعروض التجارة (${isGregorianYear ? '2.577% ميلادي' : '2.5% هجري'})',
      summary: reachedNisab
          ? 'الوعاء بلغ النصاب — الزكاة المستحقة: ${Money(zakatDuePiasters).toDisplay()} ج.م'
          : 'الوعاء لم يبلغ النصاب بعد — لا زكاة واجبة حالياً (0.00 ج.م)',
      details: [
        'قيمة البضاعة بسعر البيع: ${Money(stockSellPiasters).toDisplay()} ج.م (للاسترشاد بالتكلفة: ${Money(stockCostPiasters).toDisplay()} ج.م)',
        'النقدية المسجلة (المحافظ + الدرج): ${Money(totalDbCashPiasters).toDisplay()} ج.م${extraBankCashPiasters > 0 ? ' + كاش بنكي خارجي: ${Money(extraBankCashPiasters).toDisplay()} ج.م' : ''}',
        'مستحقات العملاء المرجوة (الأقساط): ${Money(receivablesPiasters).toDisplay()} ج.م',
        'يُخصم ديون الموردين: ${Money(supplierDebtPiasters).toDisplay()} ج.م${extraDebtsOnBusinessPiasters > 0 ? ' + التزامات إضافية: ${Money(extraDebtsOnBusinessPiasters).toDisplay()} ج.م' : ''}',
        'صافي وعاء الزكاة: ${Money(zakatPoolPiasters).toDisplay()} ج.م | النصاب (85 جم ذهب عيار 24): ${Money(nisabPiasters).toDisplay()} ج.م',
        'تنبيه فقهي ومحاسبي: تُحسب البضاعة المعدة للبيع أو خامات الوجبات، وتُستبعد الأصول الثابتة مثل أفران المطعم، عدة الصيانة، الرفوف، وأجهزة الكاشير، والديون غير المرجوة، ويشترط حولان الحول الهجري.',
      ],
      isAlert: reachedNisab,
    );
  }

  /// Businessman Consultation ("انصحني كـ بزنس مان" / "اعمل ايه في محلي"):
  /// Reads real DB metrics (stagnant ratio, avg margin, monthly expenses, supplier debt)
  /// and outputs a tailored executive action plan.
  Future<AssistantInsight> getBusinessmanConsultationInsight() async {
    final now = DateTime.now();
    final since30 = now.subtract(const Duration(days: 30));
    final monthStart = DateTime(now.year, now.month, 1);

    final recentItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since30)))
        .get();
    final soldVariantIds = <String>{};
    int revenue30 = 0;
    int cost30 = 0;
    for (final si in recentItems) {
      soldVariantIds.add(si.variantId);
      revenue30 += si.lineTotal;
      cost30 += si.costSnapshot * si.qty;
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
    final stagnantPct =
        totalStockCost > 0 ? (stagnantStockCost / totalStockCost) * 100.0 : 0.0;
    final avgMarginPct =
        revenue30 > 0 ? ((revenue30 - cost30) / revenue30) * 100.0 : 0.0;

    final monthExpensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.expenseDate.isBiggerOrEqualValue(monthStart) &
              e.deletedAt.isNull()))
        .get();
    final monthExpenses =
        monthExpensesRows.fold<int>(0, (sum, e) => sum + e.amount);

    final suppliers = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull()))
        .get();
    final supplierDebt =
        suppliers.fold<int>(0, (sum, s) => sum + (s.balance > 0 ? s.balance : 0));

    final actions = <String>[
      'نسبة المخزون الراكد: ${stagnantPct.toStringAsFixed(1)}% (${Money(stagnantStockCost).toDisplay()} ج.م) | متوسط الهامش (30 يوم): ${avgMarginPct.toStringAsFixed(1)}%.',
      'مصاريف هذا الشهر: ${Money(monthExpenses).toDisplay()} ج.م | ديون الموردين: ${Money(supplierDebt).toDisplay()} ج.م.',
    ];

    if (stagnantPct >= 25.0) {
      actions.add(
        'أولوية 1 (تسييل الراكد): المخزون الراكد مرتفع؛ أوقف شراء موديلات جديدة وصفِّ أقدم الأصناف بباقات مجمعة.',
      );
    } else {
      actions.add(
        'أولوية 1 (تسريع الدوران): نسبة الراكد تحت السيطرة؛ ركز 50% من المشتريات على أسرع الأصناف مبيعاً.',
      );
    }

    if (revenue30 > 0 && avgMarginPct < 22.0) {
      actions.add(
        'أولوية 2 (حماية الهامش): متوسط الهامش (${avgMarginPct.toStringAsFixed(1)}%) منخفض؛ راجع التسعير على تكلفة الاستبدال وامنع الخصومات العشوائية.',
      );
    } else {
      actions.add(
        'أولوية 2 (رفع الفاتورة): درّب الكاشير على اقتراح مكمل مع كل فاتورة لرفع متوسط البيع 20%.',
      );
    }

    if (supplierDebt > 0) {
      actions.add(
        'أولوية 3 (ضبط الالتزامات): جدول سداد ${Money(supplierDebt).toDisplay()} ج.م للموردين من عائد الأصناف السريعة واحتفظ بـ 20% كاش طوارئ.',
      );
    }

    final sector = await detectStoreSector();
    switch (sector) {
      case 'clothing':
        actions.add(
          'توصية القطاع (ملابس وأحذية ومفروشات): ركز الشراء على أكثر المقاسات والألوان مبيعاً، وصفِّ المقاسات المكسورة وبواقي الأمتار/الأثواب قبل نهاية الموسم بـ 3 أسابيع.',
        );
        break;
      case 'mobiles':
        actions.add(
          'توصية القطاع (موبايلات وإلكترونيات): لا تجمّد الكاش في أجهزة بطيئة مع تغير الأسعار السريع؛ عظّم الربح عبر باقات الإكسسوارات، الصيانة، وخدمة المحافظ مع توثيق IMEI للمستعمل.',
        );
        break;
      case 'fnb':
        actions.add(
          'توصية القطاع (مطاعم وكافيهات): اضبط تكلفة الخامات (Food Cost) بين 28% و 35%، قلل الهالك اليومي بالـ Recipe الثابت، وادفع المبيعات بعروض الكومبو وسرعة دوران الطاولات.',
        );
        break;
      case 'grocery':
        actions.add(
          'توصية القطاع (سوبر ماركت ومواد غذائية): طبّق قاعدة FEFO (الأقرب انتهاءً يخرج أولاً)، وراقب النواقص اليومية لرفع سرعة دوران الكاش حتى لو كان الهامش بسيطاً.',
        );
        break;
      case 'home':
        actions.add(
          'توصية القطاع (أدوات منزلية): صمّم باقات جهاز العروسة والمطبخ المتكاملة لرفع قيمة الفاتورة، واهتم بتغليف وحماية الزجاجيات وسياسة الضمان الواضحة.',
        );
        break;
      default:
        break;
    }

    return AssistantInsight(
      id: 'businessman_consultation',
      title: 'استشارة البزنس مان المخصصة لوضع محلك',
      summary: stagnantPct >= 25.0 || (revenue30 > 0 && avgMarginPct < 22.0)
          ? 'توصية تنفيذية عاجلة لحماية السيولة ورفع صافي الربح:'
          : 'أرقام محلك متوازنة — إليك خطة البزنس مان لمضاعفة النمو:',
      details: actions,
      isAlert: stagnantPct >= 25.0,
      followUpPrompts: const [
        'أعمل عروض على إيه؟',
        'توزيع السيولة 50/30/20',
        'كاشف تسرب الأرباح',
      ],
    );
  }

  /// 1. Goal Planner ("عايز اكسب [مبلغ]" / "هدف الربح [مبلغ]"):
  /// Extracts target monthly net profit (default 20,000 EGP), reads monthly
  /// operating expenses, actual average margin (30d), and average invoice (30d)
  /// to compute required monthly/daily revenue and daily invoice count.
  Future<AssistantInsight> getGoalPlannerInsight(String rawQuery) async {
    final norm = OfflineSmartAssistantService.normalizeArabic(rawQuery);
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(norm);
    final targetProfitEgp =
        match != null ? (double.tryParse(match.group(1)!) ?? 20000.0) : 20000.0;
    final targetProfitPiasters = (targetProfitEgp * 100).round();

    final now = DateTime.now();
    final since30 = now.subtract(const Duration(days: 30));
    final monthStart = DateTime(now.year, now.month, 1);

    final monthExpensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.expenseDate.isBiggerOrEqualValue(monthStart) &
              e.deletedAt.isNull()))
        .get();
    final monthExpensesPiasters =
        monthExpensesRows.fold<int>(0, (sum, e) => sum + e.amount);

    final recentSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(since30) &
              s.deletedAt.isNull() &
              s.status.equals('cancelled').not()))
        .get();

    final recentItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since30)))
        .get();

    int itemsRevenue30 = 0;
    int itemsCost30 = 0;
    for (final si in recentItems) {
      itemsRevenue30 += si.lineTotal;
      itemsCost30 += si.costSnapshot * si.qty;
    }

    final hasMarginData = itemsRevenue30 > 0 && itemsRevenue30 > itemsCost30;
    final marginRate = hasMarginData
        ? (itemsRevenue30 - itemsCost30) / itemsRevenue30
        : 0.25;

    final salesRevenue30 = recentSales.fold<int>(0, (sum, s) => sum + s.total);
    final hasInvoiceData = recentSales.isNotEmpty && salesRevenue30 > 0;
    final avgInvoicePiasters = hasInvoiceData
        ? (salesRevenue30 / recentSales.length).round()
        : 50000; // 500 EGP benchmark

    final requiredTotalGrossProfit =
        targetProfitPiasters + monthExpensesPiasters;
    final requiredMonthlySalesPiasters =
        (requiredTotalGrossProfit / marginRate).round();
    final requiredDailySalesPiasters =
        (requiredMonthlySalesPiasters / 30).round();
    final requiredDailyInvoices = avgInvoicePiasters > 0
        ? (requiredDailySalesPiasters / avgInvoicePiasters).ceil()
        : 0;

    final sector = await detectStoreSector();
    final String sectorTip;
    switch (sector) {
      case 'clothing':
        sectorTip = 'نصيحة القطاع: ركز على بيع الطقم الكامل لرفع متوسط الفاتورة وتقليل عدد الفواتير اليومية المطلوبة.';
        break;
      case 'mobiles':
        sectorTip = 'نصيحة القطاع: أضف باقات الإكسسوارات والصيانة مع كل جهاز لرفع متوسط الهامش الفعلي.';
        break;
      case 'fnb':
        sectorTip = 'نصيحة القطاع: حافظ على Food Cost أقل من 35% وفعّل عروض الكومبو لرفع قيمة الشيك.';
        break;
      case 'grocery':
        sectorTip = 'نصيحة القطاع: سرّع دوران السلع اليومية واعرض المكملات عالية الهامش عند الكاشير.';
        break;
      case 'home':
        sectorTip = 'نصيحة القطاع: روّج لباقات المطبخ وجهاز العروسة بدلاً من القطع الفردية.';
        break;
      default:
        sectorTip = 'نصيحة تنفيذية: رفع متوسط الفاتورة 15% بالبيع التكميلي يقلص عدد الفواتير اليومية المطلوبة.';
    }

    return AssistantInsight(
      id: 'goal_planner',
      title:
          'مخطط الأهداف: طريقك لصافي ربح ${Money(targetProfitPiasters).toDisplay()} ج.م شهرياً',
      summary:
          'تحتاج مبيعات شهرية ${Money(requiredMonthlySalesPiasters).toDisplay()} ج.م (${Money(requiredDailySalesPiasters).toDisplay()} ج.م/يوم بمعدل $requiredDailyInvoices فاتورة يومياً).',
      details: [
        'الهدف الصافي: ${Money(targetProfitPiasters).toDisplay()} ج.م + مصاريف الشهر المسجلة: ${Money(monthExpensesPiasters).toDisplay()} ج.م = إجمالي ربح مطلوب ${Money(requiredTotalGrossProfit).toDisplay()} ج.م.',
        'متوسط الهامش المعتمد: ${(marginRate * 100).toStringAsFixed(1)}%${hasMarginData ? ' (فعلي آخر 30 يوم)' : ' (تقديري لعدم وجود مبيعات)'} | متوسط الفاتورة: ${Money(avgInvoicePiasters).toDisplay()} ج.م${hasInvoiceData ? '' : ' (افتراضي)'}.',
        'المبيعات اليومية المطلوبة: ${Money(requiredDailySalesPiasters).toDisplay()} ج.م | الفواتير المطلوبة يومياً: $requiredDailyInvoices فاتورة.',
        sectorTip,
      ],
      followUpPrompts: const [
        'تقييم صحة المحل',
        'نقطة التعادل اليومية',
        'استشارة بزنس مان',
      ],
    );
  }

  /// 2. Store Health Score out of 100 ("تقييم صحة المحل" / "مؤشر صحة المحل"):
  /// Evaluates 4 quarters (25 pts each):
  /// A) Stock turnover & stagnant ratio
  /// B) Margin protection & discount discipline
  /// C) Expense coverage & profitability
  /// D) Installment collection & supplier debt ratio
  Future<AssistantInsight> getStoreHealthScoreInsight() async {
    final now = DateTime.now();
    final since30 = now.subtract(const Duration(days: 30));
    final monthStart = DateTime(now.year, now.month, 1);

    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull() & v.quantity.isBiggerThanValue(0)))
        .get();
    final recentItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since30)))
        .get();
    final recentSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(since30) &
              s.deletedAt.isNull() &
              s.status.equals('cancelled').not()))
        .get();
    final monthExpensesRows = await (_db.select(_db.expenses)
          ..where((e) =>
              e.expenseDate.isBiggerOrEqualValue(monthStart) &
              e.deletedAt.isNull()))
        .get();
    final installments = await (_db.select(_db.customerInstallments)
          ..where((i) =>
              i.deletedAt.isNull() &
              (i.status.equals('active') | i.status.equals('overdue'))))
        .get();
    final suppliers = await (_db.select(_db.suppliers)
          ..where((s) => s.deletedAt.isNull()))
        .get();

    // (A) Stock turnover & stagnant ratio (0..25)
    final soldVariantIds = {for (final si in recentItems) si.variantId};
    int totalStockCost = 0;
    int stagnantStockCost = 0;
    for (final v in variants) {
      final val = v.quantity * v.costPrice;
      totalStockCost += val;
      if (!soldVariantIds.contains(v.id)) {
        stagnantStockCost += val;
      }
    }
    final stagnantPct =
        totalStockCost > 0 ? (stagnantStockCost / totalStockCost) * 100.0 : 0.0;
    final int scoreTurnover = totalStockCost == 0
        ? 15
        : stagnantPct <= 10.0
            ? 25
            : (25.0 * (1.0 - ((stagnantPct - 10.0) / 50.0).clamp(0.0, 1.0)))
                .round();

    // (B) Margin protection & discount discipline (0..25)
    int itemsRev = 0;
    int itemsCost = 0;
    for (final si in recentItems) {
      itemsRev += si.lineTotal;
      itemsCost += si.costSnapshot * si.qty;
    }
    final avgMarginPct =
        itemsRev > 0 ? ((itemsRev - itemsCost) / itemsRev) * 100.0 : 0.0;
    final totalNetSales = recentSales.fold<int>(0, (s, r) => s + r.total);
    final totalDiscounts =
        recentSales.fold<int>(0, (s, r) => s + r.discountValue);
    final grossBeforeDiscount = totalNetSales + totalDiscounts;
    final discountPct = grossBeforeDiscount > 0
        ? (totalDiscounts / grossBeforeDiscount) * 100.0
        : 0.0;

    final int marginPts = itemsRev == 0
        ? 12
        : ((avgMarginPct / 25.0).clamp(0.0, 1.0) * 15.0).round();
    final int discountPts = discountPct <= 3.0
        ? 10
        : (10.0 * (1.0 - ((discountPct - 3.0) / 12.0).clamp(0.0, 1.0))).round();
    final int scoreMargin = (marginPts + discountPts).clamp(0, 25);

    // (C) Expense coverage & profitability (0..25)
    final monthExpenses =
        monthExpensesRows.fold<int>(0, (s, e) => s + e.amount);
    final grossProfit30 = itemsRev - itemsCost;
    final int scoreProfit;
    if (monthExpenses == 0 && grossProfit30 == 0) {
      scoreProfit = 12;
    } else if (monthExpenses == 0) {
      scoreProfit = grossProfit30 > 0 ? 25 : 8;
    } else {
      final coverage = grossProfit30 / monthExpenses;
      scoreProfit = ((coverage / 2.0).clamp(0.0, 1.0) * 25.0).round();
    }

    // (D) Installment collection & supplier debt (0..25)
    final overdueCount =
        installments.where((i) => i.status == 'overdue').length;
    final int instPts = overdueCount == 0
        ? 13
        : (13 - overdueCount * 3).clamp(2, 13);
    final supplierDebt =
        suppliers.fold<int>(0, (s, r) => s + (r.balance > 0 ? r.balance : 0));
    final debtRatio =
        totalStockCost > 0 ? supplierDebt / totalStockCost : (supplierDebt > 0 ? 1.0 : 0.0);
    final int debtPts = debtRatio <= 0.25
        ? 12
        : (12.0 * (1.0 - ((debtRatio - 0.25) / 0.75).clamp(0.0, 1.0))).round();
    final int scoreLiquidity = (instPts + debtPts).clamp(0, 25);

    final totalScore =
        (scoreTurnover + scoreMargin + scoreProfit + scoreLiquidity).clamp(0, 100);

    final sector = await detectStoreSector();
    final String sectorRec;
    switch (sector) {
      case 'clothing':
        sectorRec = 'توصية سريعة (ملابس): صفِّ المقاسات المكسورة وبواقي الموسم بباقات لرفع ربع دوران المخزون.';
        break;
      case 'mobiles':
        sectorRec = 'توصية سريعة (موبايلات): اربط كل جهاز بباقة إكسسوارات لرفع هامش الربح دون خصومات على الأجهزة.';
        break;
      case 'fnb':
        sectorRec = 'توصية سريعة (مطاعم وكافيهات): راجع تكلفة الخامات (Food Cost) والهالك لرفع ربع تغطية المصاريف.';
        break;
      case 'grocery':
        sectorRec = 'توصية سريعة (سوبر ماركت): راقب الأصناف قريبة الصلاحية (FEFO) واضبط النواقص اليومية.';
        break;
      case 'home':
        sectorRec = 'توصية سريعة (أدوات منزلية): اعرض أطقم كاملة (باقات) لرفع قيمة الفاتورة وتنشيط الراكد.';
        break;
      default:
        sectorRec = 'توصية سريعة: أوقف الخصومات العشوائية وركز المشتريات على أعلى 20% أصناف دوراناً.';
    }

    final recommendations = <String>[
      if (scoreTurnover < 20)
        '1. رفع دوران المخزون: نسبة الراكد ${stagnantPct.toStringAsFixed(1)}% — أطلق باقات دمج على أبطأ الأصناف.'
      else
        '1. استثمار المخزون: حافظ على نسبة الراكد منخفضة بتجديد المقاسات والأصناف السريعة.',
      if (scoreMargin < 20)
        '2. حماية الهامش: راجع التسعير وقيد الخصومات اليدوية (الخصومات الحالية ${discountPct.toStringAsFixed(1)}%).'
      else if (scoreLiquidity < 20)
        '2. تسريع التحصيل: تابع الأقساط المتأخرة ($overdueCount) وجدول سداد الموردين (${Money(supplierDebt).toDisplay()} ج.م).'
      else
        '2. مضاعفة الربحية: فعّل البيع التكميلي عند الكاشير لرفع متوسط الفاتورة.',
      '3. $sectorRec',
    ];

    return AssistantInsight(
      id: 'store_health_score',
      title: 'مؤشر صحة المحل: $totalScore / 100',
      summary: totalScore >= 80
          ? 'أداء ممتاز ومتوازن عبر المؤشرات الأربعة.'
          : totalScore >= 55
              ? 'أداء متوسط — توجد فرص واضحة لرفع السيولة والربحية.'
              : 'تنبيه: المؤشر منخفض ويحتاج تدخلاً سريعاً في المخزون والهامش.',
      details: [
        '(أ) دوران المخزون ونسبة الراكد: $scoreTurnover / 25 (راكد: ${stagnantPct.toStringAsFixed(1)}%)',
        '(ب) حماية الهامش وانضباط الخصومات: $scoreMargin / 25 (هامش: ${avgMarginPct.toStringAsFixed(1)}% | خصومات: ${discountPct.toStringAsFixed(1)}%)',
        '(ج) تغطية المصاريف والربحية: $scoreProfit / 25 (إجمالي ربح 30 يوم: ${Money(grossProfit30).toDisplay()} ج.م مقابل مصاريف: ${Money(monthExpenses).toDisplay()} ج.م)',
        '(د) تحصيل الأقساط وديون الموردين: $scoreLiquidity / 25 (أقساط متأخرة: $overdueCount | موردين: ${Money(supplierDebt).toDisplay()} ج.م)',
        ...recommendations,
      ],
      isAlert: totalScore < 55,
      followUpPrompts: const [
        'جهز طلبية الشراء',
        'استشارة بزنس مان',
        'عايز اكسب 30000',
      ],
    );
  }

  /// 3. Smart Reorder List ("جهز طلبية الشراء" / "اطلب بضاعة ايه"):
  /// Computes 30-day daily velocity for active variants, flags variants with
  /// < 14 days of remaining stock, recommends order qty for 30 days, and
  /// estimates total order cost.
  Future<AssistantInsight> getSmartReorderListInsight() async {
    final since30 = DateTime.now().subtract(const Duration(days: 30));
    final recentItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(since30)))
        .get();

    final soldQtyByVariant = <String, int>{};
    for (final si in recentItems) {
      soldQtyByVariant[si.variantId] =
          (soldQtyByVariant[si.variantId] ?? 0) + si.qty;
    }

    final variants = await (_db.select(_db.productVariants)
          ..where((v) => v.deletedAt.isNull()))
        .get();
    final products = await (_db.select(_db.products)
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final productNames = {for (final p in products) p.id: p.name};

    final urgentItems = <({
      String label,
      double daysLeft,
      int currentQty,
      int orderQty,
      int estCostPiasters,
    })>[];

    int totalOrderCostPiasters = 0;
    int totalOrderUnits = 0;

    for (final v in variants) {
      final sold30 = soldQtyByVariant[v.id] ?? 0;
      if (sold30 <= 0) continue;
      final dailyVelocity = sold30 / 30.0;
      final daysLeft = v.quantity / dailyVelocity;
      if (daysLeft < 14.0) {
        final target30Qty = (dailyVelocity * 30.0).ceil();
        final orderQty = (target30Qty - v.quantity).clamp(1, 100000);
        final estCost = orderQty * v.costPrice;
        totalOrderCostPiasters += estCost;
        totalOrderUnits += orderQty;

        final pName = productNames[v.productId] ?? v.sku;
        final attrParts = [
          if (v.size.trim().isNotEmpty) v.size.trim(),
          if (v.color.trim().isNotEmpty) v.color.trim(),
        ];
        final label = attrParts.isNotEmpty
            ? '$pName (${attrParts.join(' - ')})'
            : pName;

        urgentItems.add((
          label: label,
          daysLeft: daysLeft,
          currentQty: v.quantity,
          orderQty: orderQty,
          estCostPiasters: estCost,
        ));
      }
    }

    urgentItems.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

    if (urgentItems.isEmpty) {
      return const AssistantInsight(
        id: 'smart_reorder_list',
        title: 'كشف طلبية الشراء الذكية',
        summary: 'لا توجد أصناف نشطة ينفد رصيدها خلال أقل من 14 يوماً حالياً.',
        details: [
          'جميع الأصناف التي تحركت خلال آخر 30 يوماً لديها تغطية كافية لأسبوعين على الأقل.',
        ],
        followUpPrompts: ['تقييم صحة المحل', 'الأصناف الراكدة'],
      );
    }

    final lines = urgentItems.take(8).map((item) {
      final daysStr = item.daysLeft <= 0
          ? 'نفد الرصيد'
          : 'يكفي ${item.daysLeft.toStringAsFixed(1)} يوم';
      return '• ${item.label}: متاح ${item.currentQty} ($daysStr) -> اطلب ${item.orderQty} قطعة (تكلفة ~${Money(item.estCostPiasters).toDisplay()} ج.م)';
    }).toList();

    lines.add(
      'الإجمالي التقديري للطلبية (${urgentItems.length} صنف / $totalOrderUnits قطعة لتغطية 30 يوم): ${Money(totalOrderCostPiasters).toDisplay()} ج.م.',
    );

    return AssistantInsight(
      id: 'smart_reorder_list',
      title: 'كشف طلبية الشراء الذكية (${urgentItems.length} صنف عاجل)',
      summary:
          'إجمالي التكلفة التقديرية لتغطية 30 يوماً: ${Money(totalOrderCostPiasters).toDisplay()} ج.م ($totalOrderUnits قطعة).',
      details: lines,
      isAlert: true,
      followUpPrompts: const [
        'تقييم صحة المحل',
        'مستحقات الموردين',
      ],
    );
  }

  /// 4. Diplomatic Customer Objection Replies ("العميل بيقول غالي" /
  /// "تاخير ديليفري" / "استرجاع بعد المدة"):
  /// Generates 3 copy-ready diplomatic replies tailored to the store's sector.
  Future<AssistantInsight> getCustomerObjectionRepliesInsight(
    String rawQuery,
  ) async {
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
    final sector = await detectStoreSector();

    final String sectorValueProp;
    switch (sector) {
      case 'clothing':
        sectorValueProp = 'جودة الخامة والتقفيل وثبات الألوان مع ضمان الاستبدال المريح';
        break;
      case 'mobiles':
        sectorValueProp = 'الضمان الحقيقي، فحص الجهاز، وخدمة ما بعد البيع والدعم الفني';
        break;
      case 'fnb':
        sectorValueProp = 'جودة المكونات الطازجة والنظافة ومعايير التحضير الثابتة';
        break;
      case 'grocery':
        sectorValueProp = 'الصلاحية الطازجة والتخزين السليم وتوفير الطلبات اليومية بسرعة';
        break;
      case 'home':
        sectorValueProp = 'متانة الخامة والتغليف الآمن وضمان الاستبدال ضد أي عيوب صناعة';
        break;
      default:
        sectorValueProp = 'الجودة المضمونة، السعر العادل، وخدمة ما بعد البيع';
    }

    final String scenarioTitle;
    final List<String> replies;

    if (q.contains('تاخير') ||
        q.contains('اتأخر') ||
        q.contains('ديليفري') ||
        q.contains('شحن') ||
        q.contains('مندوب')) {
      scenarioTitle = 'تأخير الديليفري والشحن';
      replies = [
        'الرد 1 (احتواء فوري وشفافية)\n---\nأهلاً بحضرتك يا فندم، نعتذر جداً عن تأخير الطلب الخارج عن إرادتنا. تواصلنا حالياً مع مسؤول التوصيل وأصبح طلبك في أولوية التسليم ليصلك في أسرع وقت، ونقدّر تفهمك وصبرك معنا.',
        'الرد 2 (تعويض معنوي يحفظ الولاء)\n---\nحقك علينا يا فندم، رضائك أهم عندنا من أي شيء. تم متابعة الشحنة شخصياً وستصلك خلال الساعات القادمة، ويسعدنا نقدم لك خصماً أو ميزة خاصة على طلبك القادم تقديراً لتأخيرنا.',
        'الرد 3 (متابعة دقيقة برقم الطلب)\n---\nنأسف لتأخر المندوب يا فندم، نرجو مشاركة رقم الطلب أو الهاتف للتأكيد الفوري لموعد الوصول الدقيق ومتابعته لحظة بلحظة حتى الاستلام.',
      ];
    } else if (q.contains('استرجاع') ||
        q.contains('رجع') ||
        q.contains('تبديل') ||
        q.contains('بعد المده') ||
        q.contains('فاتت المده')) {
      scenarioTitle = 'طلب استرجاع بعد انتهاء المدة';
      replies = [
        'الرد 1 (توضيح السياسة بأسلوب لطيف)\n---\nتشرّفنا بخدمتك يا فندم، نسعد دائماً بمساعدتك. حسب سياسة المحل المعلنة في الفاتورة، مدة الاسترجاع المحددة قد انتهت، ولكن احتراماً لثقتك فينا يسعدنا نساعدك في الاستبدال بصنف آخر يناسب احتياجك إذا كانت الحالة مطابقة للشروط.',
        'الرد 2 (بديل مرن: رصيد شراء)\n---\nأهلاً بحضرتك، رغم مرور المدة المقررة للاسترجاع النقدي، نقدّر تعاملك معنا ويمكننا استثنائياً قبول استبدال المنتج أو حفظ قيمته كرصيد شراء لصالحك في أي وقت.',
        'الرد 3 (دعوة للفحص والحل الودي)\n---\nيسعدنا تشريفك لنا بالمحل لفحص القطعة مع الفاتورة، وبإذن الله نجد أفضل حل ودي يرضيك في إطار سياسة الاستبدال لدينا.',
      ];
    } else {
      scenarioTitle = 'الاعتراض على السعر ("غالي")';
      replies = [
        'الرد 1 (تأكيد القيمة مقابل السعر)\n---\nمعاك حق تقارن يا فندم، السعر فعلاً بيعكس $sectorValueProp، وده بيوفر عليك مصاريف وتكلفة تغيير أو صيانة قدام مقارنة بالبدائل الرخيصة.',
        'الرد 2 (اقتراح بديل اقتصادي أو باقة)\n---\nنورتنا يا فندم، هدفنا تلاقي الأنسب لميزانيتك. عندنا خيار تاني بسعر اقتصادي ممتاز، أو نقدر نعملك باقة متكاملة توفرلك في إجمالي الفاتورة وتاخد قيمة أكبر.',
        'الرد 3 (تسليط الضوء على الضمان وخدمة ما بعد البيع)\n---\nفاهم وجهة نظرك تماماً يا فندم، الفارق البسيط في السعر بيضمنلك منتج مضمون وخدمة ما بعد البيع لو احتجت أي مساعدة في أي وقت، ودي راحة بال بتستمر معاك.',
      ];
    }

    return AssistantInsight(
      id: 'customer_objection_replies',
      title: 'ردود دبلوماسية جاهزة للنسخ ($scenarioTitle)',
      summary: 'اختر الرد الأنسب لعميلك واضغط "نسخ" لإرساله فوراً:',
      details: replies,
      followUpPrompts: const [
        'العميل بيقول غالي',
        'تاخير ديليفري',
        'استرجاع بعد المدة',
      ],
    );
  }

  /// Multi-turn conversation entry point supporting [AssistantActionDraft].

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
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
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
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
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

  Future<AssistantInsight> _buildYesterdayFollowupInsight() async {
    final now = DateTime.now();
    final yesterdayStart = DateTime(now.year, now.month, now.day - 1);
    final todayStart = DateTime(now.year, now.month, now.day);

    final ySales = await (_db.select(_db.sales)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(yesterdayStart) &
              s.createdAt.isSmallerThanValue(todayStart) &
              s.deletedAt.isNull() &
              s.status.equals('cancelled').not()))
        .get();
    final yRev = ySales.fold<int>(0, (sum, r) => sum + r.total);
    final yItems = await (_db.select(_db.saleItems)
          ..where((si) =>
              si.createdAt.isBiggerOrEqualValue(yesterdayStart) &
              si.createdAt.isSmallerThanValue(todayStart)))
        .get();
    final yCost =
        yItems.fold<int>(0, (sum, si) => sum + si.costSnapshot * si.qty);
    final yProfit = yRev - yCost;

    final ctxLabel = contextMemory.lastIntent == AssistantNluIntent.salesDiagnosis
        ? 'متابعة تشخيص المبيعات (أمس)'
        : 'ملخص مبيعات وأرباح أمس';

    return AssistantInsight(
      id: 'yesterday_followup',
      title: ctxLabel,
      summary:
          'مبيعات أمس: ${Money(yRev).toDisplay()} ج.م (${ySales.length} فاتورة) | إجمالي ربح أمس: ${Money(yProfit).toDisplay()} ج.م.',
      details: [
        'إجمالي فواتير أمس: ${ySales.length} فاتورة.',
        'تكلفة البضاعة المباعة أمس: ${Money(yCost).toDisplay()} ج.م.',
        'صافي الربح التقديري أمس (قبل المصروفات): ${Money(yProfit).toDisplay()} ج.م.',
      ],
      followUpPrompts: const [
        'وضع المحل دلوقتي؟',
        'صافي ربح اليوم ومقارنته بأمس',
      ],
    );
  }

  Future<bool> _isFeatureEnabledInDb(
    String featureKey, {
    bool defaultValue = false,
  }) async {
    final row = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals('feature.$featureKey')))
        .getSingleOrNull();
    if (row == null) return defaultValue;
    return row.value.trim().toLowerCase() == 'true';
  }

  Future<bool> _sqliteTableExists(String tableName) async {
    final rows = await _db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable.withString(tableName)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Open Shift Drawer Summary (`shifts`).
  Future<AssistantInsight> getOpenShiftSummaryInsight() async {
    final openShift = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();

    if (openShift == null) {
      return const AssistantInsight(
        id: 'open_shift_summary',
        title: 'ملخص الدرج والوردية المفتوحة',
        summary: 'لا توجد وردية مفتوحة حالياً.',
        details: ['افتح وردية جديدة من شاشة الورديات أو الكاشير للبدء.'],
        actionLabel: 'فتح شاشة الورديات',
        actionRoute: AssistantActionRoute.shifts,
      );
    }

    final shiftSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.shiftId.equals(openShift.id) &
              s.deletedAt.isNull() &
              s.status.equals('cancelled').not()))
        .get();
    final cashSales = shiftSales
        .where((s) => s.paymentMethod == 'cash')
        .fold<int>(0, (sum, s) => sum + s.total);
    final totalSales = shiftSales.fold<int>(0, (sum, s) => sum + s.total);

    final movements = await (_db.select(_db.cashMovements)
          ..where((m) => m.shiftId.equals(openShift.id) & m.deletedAt.isNull()))
        .get();
    int cashIn = 0;
    int cashOut = 0;
    for (final m in movements) {
      if (m.direction == 'in') {
        cashIn += m.amountPiasters;
      } else {
        cashOut += m.amountPiasters;
      }
    }

    final expectedDrawer =
        openShift.openingBalance + cashSales + cashIn - cashOut;

    return AssistantInsight(
      id: 'open_shift_summary',
      title: 'ملخص الدرج والوردية المفتوحة',
      summary:
          'المتوقع في الدرج الآن: ${Money(expectedDrawer).toDisplay()} ج.م (${shiftSales.length} فاتورة).',
      details: [
        'الرصيد الافتتاحي: ${Money(openShift.openingBalance).toDisplay()} ج.م.',
        'مبيعات الكاش بالوردية: ${Money(cashSales).toDisplay()} ج.م (إجمالي المبيعات: ${Money(totalSales).toDisplay()} ج.م).',
        'حركات الدرج: وارد +${Money(cashIn).toDisplay()} ج.م | منصرف -${Money(cashOut).toDisplay()} ج.م.',
      ],
      actionLabel: 'فتح شاشة الورديات',
      actionRoute: AssistantActionRoute.shifts,
    );
  }

  /// Pre-Orders summary (`FeatureKeys.preOrders`).
  Future<AssistantInsight> getPreOrdersSummaryInsight() async {
    final enabled = await _isFeatureEnabledInDb(FeatureKeys.preOrders);
    if (!enabled) {
      return const AssistantInsight(
        id: 'pre_orders_disabled',
        title: 'الحجوزات المسبقة غير مفعلة',
        summary: 'ميزة الحجوزات المسبقة معطلة في إعدادات المزايا الحالية.',
      );
    }
    if (!await _sqliteTableExists('pre_orders')) {
      return const AssistantInsight(
        id: 'pre_orders_summary',
        title: 'ملخص الحجوزات المسبقة',
        summary: 'لا توجد حجوزات مسجلة حتى الآن.',
      );
    }

    final rows = await _db.customSelect(
      "SELECT order_number, customer_name, total_piasters, paid_piasters, status, expected_delivery_date FROM pre_orders WHERE deleted_at IS NULL AND status NOT IN ('delivered', 'cancelled') ORDER BY created_at DESC LIMIT 10",
    ).get();

    if (rows.isEmpty) {
      return const AssistantInsight(
        id: 'pre_orders_summary',
        title: 'ملخص الحجوزات المسبقة',
        summary: 'لا توجد حجوزات معلقة حالياً.',
      );
    }

    int totalRemaining = 0;
    final lines = <String>[];
    for (final r in rows) {
      final orderNo = r.read<String>('order_number');
      final cust = r.read<String>('customer_name');
      final total = r.read<int>('total_piasters');
      final paid = r.read<int>('paid_piasters');
      final status = r.read<String>('status');
      final rem = (total - paid).clamp(0, total);
      totalRemaining += rem;
      lines.add(
        '• #$orderNo ($cust): مدفوع ${Money(paid).toDisplay()} / إجمالي ${Money(total).toDisplay()} ج.م — متبقي ${Money(rem).toDisplay()} ج.م [$status]',
      );
    }

    return AssistantInsight(
      id: 'pre_orders_summary',
      title: 'الحجوزات المسبقة النشطة (${rows.length})',
      summary:
          'إجمالي المتبقي للتحصيل عند التسليم: ${Money(totalRemaining).toDisplay()} ج.م.',
      details: lines,
    );
  }

  /// Delivery pending orders & courier custody (`FeatureKeys.delivery`).
  Future<AssistantInsight> getDeliveryPendingSummaryInsight() async {
    final enabled = await _isFeatureEnabledInDb(FeatureKeys.delivery);
    if (!enabled) {
      return const AssistantInsight(
        id: 'delivery_disabled',
        title: 'وحدة الديليفري غير مفعلة',
        summary: 'ميزة الديليفري والتوصيل معطلة في إعدادات المزايا الحالية.',
      );
    }
    if (!await _sqliteTableExists('delivery_orders')) {
      return const AssistantInsight(
        id: 'delivery_summary',
        title: 'عهدة الطيارين والطلبات المعلقة',
        summary: 'لا توجد طلبات ديليفري مسجلة حتى الآن.',
      );
    }

    final rows = await _db.customSelect(
      "SELECT courier_name, order_total_piasters, delivery_fee_piasters, status FROM delivery_orders WHERE deleted_at IS NULL AND status NOT IN ('delivered', 'cancelled', 'returned')",
    ).get();

    if (rows.isEmpty) {
      return const AssistantInsight(
        id: 'delivery_summary',
        title: 'عهدة الطيارين والطلبات المعلقة',
        summary: 'لا توجد طلبات ديليفري معلقة الآن.',
      );
    }

    final byCourier = <String, ({int count, int amount})>{};
    int grandTotal = 0;
    for (final r in rows) {
      final courier = (r.readNullable<String>('courier_name') ?? '').trim();
      final key = courier.isEmpty ? 'غير معين لطيار' : courier;
      final amt = r.read<int>('order_total_piasters') +
          r.read<int>('delivery_fee_piasters');
      grandTotal += amt;
      final prev = byCourier[key] ?? (count: 0, amount: 0);
      byCourier[key] = (count: prev.count + 1, amount: prev.amount + amt);
    }

    final details = byCourier.entries
        .map(
          (e) =>
              '• ${e.key}: ${e.value.count} طلب — إجمالي عهدة ${Money(e.value.amount).toDisplay()} ج.م',
        )
        .toList();

    return AssistantInsight(
      id: 'delivery_summary',
      title: 'عهدة الطيارين والديليفري المعلق (${rows.length} طلب)',
      summary:
          'إجمالي المبالغ قيد التوصيل والتحصيل: ${Money(grandTotal).toDisplay()} ج.م.',
      details: details,
    );
  }

  /// Ready Repair Tickets (`FeatureKeys.mobileRepair`).
  Future<AssistantInsight> getRepairReadyInsight() async {
    final enabled = await _isFeatureEnabledInDb(FeatureKeys.mobileRepair);
    if (!enabled) {
      return const AssistantInsight(
        id: 'repair_disabled',
        title: 'وحدة الصيانة غير مفعلة',
        summary: 'ميزة الصيانة معطلة في إعدادات المزايا الحالية.',
      );
    }

    final readyTickets = await (_db.select(_db.repairTickets)
          ..where((t) => t.deletedAt.isNull() & t.status.equals('ready'))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();

    if (readyTickets.isEmpty) {
      return const AssistantInsight(
        id: 'repair_ready_summary',
        title: 'تذاكر الصيانة الجاهزة للتسليم',
        summary: 'لا توجد أجهزة جاهزة للتسليم حالياً.',
      );
    }

    int totalDue = 0;
    final lines = readyTickets.take(10).map((t) {
      final baseCost = t.finalCost > 0 ? t.finalCost : t.estimatedCost;
      final due = (baseCost - t.depositPaid).clamp(0, baseCost);
      totalDue += due;
      return '• تذكرة ${t.ticketNumber} (${t.deviceModel} - ${t.customerName}): متبقي ${Money(due).toDisplay()} ج.م';
    }).toList();

    return AssistantInsight(
      id: 'repair_ready_summary',
      title: 'تذاكر الصيانة الجاهزة للتسليم (${readyTickets.length})',
      summary:
          'إجمالي المتبقي تحصيله عند التسليم: ${Money(totalDue).toDisplay()} ج.م.',
      details: lines,
    );
  }

  /// Electronic Wallets Balances (`FeatureKeys.mobileWallets`).
  Future<AssistantInsight> getWalletsBalanceInsight() async {
    final enabled = await _isFeatureEnabledInDb(FeatureKeys.mobileWallets);
    if (!enabled) {
      return const AssistantInsight(
        id: 'wallets_disabled',
        title: 'وحدة المحافظ الإلكترونية غير مفعلة',
        summary: 'ميزة المحافظ الإلكترونية معطلة في إعدادات المزايا الحالية.',
      );
    }

    final wallets = await (_db.select(_db.cashWallets)
          ..where((w) => w.deletedAt.isNull() & w.isActive.equals(true)))
        .get();

    if (wallets.isEmpty) {
      return const AssistantInsight(
        id: 'wallets_balance_summary',
        title: 'أرصدة المحافظ الإلكترونية',
        summary: 'لا توجد محافظ نشطة مسجلة حالياً.',
      );
    }

    final totalBalance =
        wallets.fold<int>(0, (sum, w) => sum + w.currentBalance);
    final lines = wallets.map((w) {
      final remLimit = w.monthlyLimit > 0
          ? ' | متبقي بالحد الشهري: ${Money((w.monthlyLimit - w.monthlyUsed).clamp(0, w.monthlyLimit)).toDisplay()} ج.م'
          : '';
      return '• ${w.name} (${w.providerType}): ${Money(w.currentBalance).toDisplay()} ج.م$remLimit';
    }).toList();

    return AssistantInsight(
      id: 'wallets_balance_summary',
      title: 'أرصدة المحافظ الإلكترونية (${wallets.length} محفظة)',
      summary:
          'إجمالي السيولة بالمحافظ: ${Money(totalBalance).toDisplay()} ج.م.',
      details: lines,
    );
  }

  /// Partners Profit Shares (`FeatureKeys.partners`).
  Future<AssistantInsight> getPartnersProfitSharesInsight() async {
    final enabled = await _isFeatureEnabledInDb(FeatureKeys.partners);
    if (!enabled) {
      return const AssistantInsight(
        id: 'partners_disabled',
        title: 'وحدة الشركاء غير مفعلة',
        summary: 'ميزة الشركاء وتوزيع الأرباح معطلة في إعدادات المزايا الحالية.',
      );
    }

    final meta = await (_db.select(_db.appMeta)
          ..where((m) => m.key.equals('partners_registry')))
        .getSingleOrNull();
    if (meta == null || meta.value.trim().isEmpty) {
      return const AssistantInsight(
        id: 'partners_shares_summary',
        title: 'حصص وأرباح الشركاء',
        summary: 'لا يوجد شركاء مسجلون حالياً.',
        actionLabel: 'فتح شاشة الشركاء',
        actionRoute: AssistantActionRoute.partners,
      );
    }

    final decoded = jsonDecode(meta.value) as List<dynamic>;
    if (decoded.isEmpty) {
      return const AssistantInsight(
        id: 'partners_shares_summary',
        title: 'حصص وأرباح الشركاء',
        summary: 'لا يوجد شركاء مسجلون حالياً.',
        actionLabel: 'فتح شاشة الشركاء',
        actionRoute: AssistantActionRoute.partners,
      );
    }

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(monthStart) &
              s.deletedAt.isNull() &
              s.status.equals('cancelled').not()))
        .get();
    final monthItems = await (_db.select(_db.saleItems)
          ..where((si) => si.createdAt.isBiggerOrEqualValue(monthStart)))
        .get();
    final monthExp = await (_db.select(_db.expenses)
          ..where((e) =>
              e.expenseDate.isBiggerOrEqualValue(monthStart) &
              e.deletedAt.isNull()))
        .get();

    final rev = monthSales.fold<int>(0, (s, r) => s + r.total);
    final cost = monthItems.fold<int>(0, (s, r) => s + r.costSnapshot * r.qty);
    final exp = monthExp.fold<int>(0, (s, r) => s + r.amount);
    final netProfit = rev - cost - exp;

    final lines = <String>[];
    for (final raw in decoded) {
      final map = raw as Map<String, dynamic>;
      final name = map['name'] as String? ?? 'شريك';
      final pct = (map['percentage'] as num?)?.toDouble() ?? 0.0;
      final share = netProfit > 0 ? ((netProfit * pct) / 100.0).round() : 0;
      lines.add(
        '• $name (${pct.toStringAsFixed(1)}%): الحصة التقديرية هذا الشهر ${Money(share).toDisplay()} ج.م',
      );
    }

    return AssistantInsight(
      id: 'partners_shares_summary',
      title: 'حصص وأرباح الشركاء للشهر الحالي',
      summary:
          'صافي ربح الشهر التقديري القابل للتوزيع: ${Money(netProfit).toDisplay()} ج.م.',
      details: lines,
      actionLabel: 'فتح شاشة الشركاء',
      actionRoute: AssistantActionRoute.partners,
    );
  }

  /// Automatic Daily Smart Briefing shown when the assistant opens.
}
