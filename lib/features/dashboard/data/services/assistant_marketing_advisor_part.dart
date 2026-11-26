part of 'offline_smart_assistant_service.dart';

extension AssistantMarketingAdvisorPart on OfflineSmartAssistantService {
  /// 1. Marketing & Finance Clarifications (Discount vs Bundle vs Gift, Funnel, Profit vs Cash)
  Future<List<AssistantInsight>> getMarketingClarificationInsights(
    String rawQuery,
  ) async {
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
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
  /// Detects the active store business sector from `receipt.store_activity`
  /// and `FeatureGate` metadata flags.
  /// Returns one of: `'clothing'`, `'mobiles'`, `'fnb'`, `'grocery'`, `'home'`, or `'all'`.
  Future<String> detectStoreSector() async {
    final rows = await _db.select(_db.appMeta).get();
    final meta = {for (final r in rows) r.key: r.value};

    final activityText =
        OfflineSmartAssistantService.normalizeArabic(meta[ReceiptSettingsService.keyStoreActivity] ?? '');
    final mobileImei = meta['feature.${FeatureKeys.mobileImeiUsed}'] == 'true';
    final mobileRepair = meta['feature.${FeatureKeys.mobileRepair}'] == 'true';
    final mobileWallets = meta['feature.${FeatureKeys.mobileWallets}'] == 'true';
    final dineIn = meta['feature.dineIn'] == 'true';
    final expiryDates = meta['feature.expiryDates'] == 'true';
    final fabricRolls = meta['feature.fabricRolls'] == 'true';

    if (mobileImei ||
        mobileRepair ||
        mobileWallets ||
        activityText.contains('موبايل') ||
        activityText.contains('الكترون') ||
        activityText.contains('هواتف')) {
      return 'mobiles';
    }
    if (dineIn ||
        activityText.contains('مطعم') ||
        activityText.contains('كافيه') ||
        activityText.contains('ماكولات') ||
        activityText.contains('مشروبات')) {
      return 'fnb';
    }
    if (expiryDates ||
        activityText.contains('سوبر') ||
        activityText.contains('بقاله') ||
        activityText.contains('غذائ')) {
      return 'grocery';
    }
    if (activityText.contains('ادوات منزليه') ||
        activityText.contains('عرايس') ||
        activityText.contains('مطبخ') ||
        activityText.contains('زجاج') ||
        activityText.contains('منزلي')) {
      return 'home';
    }
    if (fabricRolls ||
        activityText.contains('ملابس') ||
        activityText.contains('ازياء') ||
        activityText.contains('احذيه') ||
        activityText.contains('مفروشات') ||
        activityText.contains('قماش')) {
      return 'clothing';
    }
    return 'all';
  }

  Future<AssistantInsight> getVisualMerchandisingInsight() async {
    final sectorCode = await detectStoreSector();
    final String sector;
    switch (sectorCode) {
      case 'mobiles':
        sector = 'موبايلات وإلكترونيات';
        break;
      case 'fnb':
        sector = 'مطاعم وكافيهات';
        break;
      case 'clothing':
        sector = 'ملابس وأزياء';
        break;
      case 'grocery':
        sector = 'سوبر ماركت ومواد غذائية';
        break;
      case 'home':
        sector = 'أدوات منزلية';
        break;
      default:
        sector = 'عام';
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
      case 'أدوات منزلية':
        windowTip = 'الواجهة: اعرض باقات جهاز العروسة وأطقم المطبخ الكاملة بأسعار واضحة وإضاءة دافئة.';
        depthTip = 'العمق: نظّم الزجاجيات والبورسلين القابل للكسر في أرفف آمنة بعيدة عن الممرات الضيقة.';
        checkoutTip = 'الكاشير: ضع رفايع المطبخ العملية والمغلفات الواقية سهلة الإضافة للفاتورة.';
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
    final q = OfflineSmartAssistantService.normalizeArabic(rawQuery);
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
}
