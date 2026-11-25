import '../../../../core/utils/money.dart';

/// Supported high-level intents scored by [AssistantIntentScorer].
enum AssistantNluIntent {
  addProduct,
  recordPurchase,
  recordExpense,
  paySupplier,
  addCustomer,
  collectInstallment,
  updatePrice,
  updateStock,
  calculateZakat,
  overdueInstallments,
  promoPost,
  salesDiagnosis,
  todayProfit,
  yesterdayFollowup,
  whatIfPricing,
  objectionReplies,
  goalPlanner,
  storeHealthScore,
  smartReorderList,
  businessmanConsultation,
  suppliersDues,
  stagnantStock,
  stockoutVelocity,
}

/// Conversation context memory across turns inside [OfflineSmartAssistantService].
class AssistantContextMemory {
  String? lastProductName;
  String? lastSupplierName;
  String? lastCustomerName;
  double? lastCostEgp;
  double? lastSellEgp;
  int? lastQty;
  String? lastPaymentType;
  AssistantNluIntent? lastIntent;
  Map<String, dynamic> lastFields = const {};

  void updateFromDraft({
    required AssistantNluIntent intent,
    required Map<String, dynamic> fields,
  }) {
    lastIntent = intent;
    lastFields = Map<String, dynamic>.from(fields);

    final prod = fields['productName'] as String?;
    if (prod != null && prod.trim().isNotEmpty) {
      lastProductName = prod.trim();
    }
    final sup = fields['supplierName'] as String?;
    if (sup != null && sup.trim().isNotEmpty) {
      lastSupplierName = sup.trim();
    }
    final cust = fields['customerName'] as String?;
    if (cust != null && cust.trim().isNotEmpty) {
      lastCustomerName = cust.trim();
    }
    final cost = fields['costEgp'] as num?;
    if (cost != null && cost > 0) {
      lastCostEgp = cost.toDouble();
    }
    final sell = fields['sellEgp'] as num?;
    if (sell != null && sell > 0) {
      lastSellEgp = sell.toDouble();
    }
    final qty = fields['qty'] as int?;
    if (qty != null && qty != 0) {
      lastQty = qty;
    }
    final pay = fields['paymentType'] as String?;
    if (pay != null && pay.isNotEmpty) {
      lastPaymentType = pay;
    }
  }

  void updateAnalyticalIntent(AssistantNluIntent intent) {
    lastIntent = intent;
  }

  void clear() {
    lastProductName = null;
    lastSupplierName = null;
    lastCustomerName = null;
    lastCostEgp = null;
    lastSellEgp = null;
    lastQty = null;
    lastPaymentType = null;
    lastIntent = null;
    lastFields = const {};
  }
}

/// Normalizes common Egyptian merchant typos, spoken numbers, and quantity units.
class AssistantArabicNormalizer {
  static String normalizeBasic(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll('ـ', '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Fixes common merchant typos & enclitics ("منتح" -> "منتج", "شوفلي" -> "شوف لي").
  static String normalizeMerchantColloquial(String input) {
    var s = Money.normalizeDigits(input).trim();
    s = s.replaceAll('ـ', '');

    const typoReplacements = <(String, String)>[
      (r'(?<=^|\s)منتح(?=\s|$)', 'منتج'),
      (r'(?<=^|\s)كربا(?=\s|$)', 'كهربا'),
      (r'(?<=^|\s)الواتس(?=\s|$)', 'الواتساب'),
      (r'(?<=^|\s)واتس(?=\s|$)', 'واتساب'),
      (r'(?<=^|\s)الدهب(?=\s|$)', 'الذهب'),
      (r'(?<=^|\s)دهب(?=\s|$)', 'ذهب'),
      (r'(?<=^|\s)شوفلي(?=\s|$)', 'شوف لي'),
      (r'(?<=^|\s)ابعتلي(?=\s|$)', 'ابعت لي'),
      (r'(?<=^|\s)احسبلي(?=\s|$)', 'احسب لي'),
      (r'(?<=^|\s)زودلي(?=\s|$)', 'زود لي'),
      (r'(?<=^|\s)هاتلي(?=\s|$)', 'هات لي'),
      (r'(?<=^|\s)اعملي(?=\s|$)', 'اعمل لي'),
      (r'(?<=^|\s)اديت\s+لـ?', 'اديت ل'),
      (r'(?<=^|\s)بيقولي(?=\s|$)', 'بيقول لي'),
      (r'(?<=^|\s)لاقيته(?=\s|$)', 'لقيته'),
      (r'(?<=^|\s)في\s+المي[ةه](?=\s|$|[؟?])', '%'),
      (r'(?<=^|\s)ف\s+المي[ةه](?=\s|$|[؟?])', '%'),
      (r'(?<=^|\s)بالمي[ةه](?=\s|$|[؟?])', '%'),
    ];
    for (final (pat, rep) in typoReplacements) {
      s = s.replaceAll(RegExp(pat), rep);
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _unitsMap = <String, int>{
    'واحد': 1,
    'واحدة': 1,
    'واحده': 1,
    'اتنين': 2,
    'اثنين': 2,
    'تلاتة': 3,
    'تلاته': 3,
    'ثلاثة': 3,
    'ثلاثه': 3,
    'اربعة': 4,
    'اربعه': 4,
    'أربعة': 4,
    'خمسة': 5,
    'خمسه': 5,
    'ستة': 6,
    'سته': 6,
    'سبعة': 7,
    'سبعه': 7,
    'تمانية': 8,
    'تمانيه': 8,
    'ثمانية': 8,
    'تسعة': 9,
    'تسعه': 9,
    'عشرة': 10,
    'عشره': 10,
    'حداشر': 11,
    'احد عشر': 11,
    'اتناشر': 12,
    'اثنا عشر': 12,
    'تلتاشر': 13,
    'اربعتاشر': 14,
    'خمستاشر': 15,
    'ستاشر': 16,
    'سبعتاشر': 17,
    'تمنتاشر': 18,
    'تسعتاشر': 19,
  };

  static const _tensMap = <String, int>{
    'عشرين': 20,
    'تلاتين': 30,
    'ثلاثين': 30,
    'اربعين': 40,
    'أربعين': 40,
    'خمسين': 50,
    'ستين': 60,
    'سبعين': 70,
    'تمانين': 80,
    'ثمانين': 80,
    'تسعين': 90,
  };

  static const _hundredsMap = <String, int>{
    'مية': 100,
    'ميه': 100,
    'مائة': 100,
    'ميتين': 200,
    'مائتين': 200,
    'تلتمية': 300,
    'تلتميه': 300,
    'ثلاثمائة': 300,
    'ربعمية': 400,
    'ربعميه': 400,
    'اربعمائة': 400,
    'خمسمية': 500,
    'خمسميه': 500,
    'خمسمائة': 500,
    'ستمية': 600,
    'ستميه': 600,
    'ستمائة': 600,
    'سبعمية': 700,
    'سبعميه': 700,
    'سبعمائة': 700,
    'تمنمية': 800,
    'تمنميه': 800,
    'ثمانمائة': 800,
    'تسعمية': 900,
    'تسعميه': 900,
    'تسعمائة': 900,
  };

  /// Replaces spoken Egyptian/Arabic numbers and quantity units with digits,
  /// e.g. "ميتين" -> "200", "الف ونص" -> "1500", "3 آلاف" -> "3000", "دستة" -> "12".
  static String replaceSpokenNumbers(String input) {
    var s = normalizeMerchantColloquial(input);

    // 1. Compound thousands: "الف ونص" -> 1500, "الفين ونص" -> 2500, "3 آلاف" / "٤ تلاف" -> 3000 / 4000
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)[أا]لف\s+ونص(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}1500',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)[أا]لفين\s+ونص(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}2500',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:تلاف|[آا]لاف|الاف)'),
      (m) => '${int.parse(m.group(1)!) * 1000}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)[أا]لفين(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}2000',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)[أا]لف(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}1000',
    );

    // 2. Quantity units: "نص دستة" -> 6, "دستتين" -> 24, "دستة" -> 12, "حتتين" -> 2, "قطعتين" -> 2
    s = s.replaceAll(RegExp(r'نص\s+دست[ةه]'), '6');
    s = s.replaceAll(RegExp(r'دستتين'), '24');
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s+دست[ةه]'),
      (m) => '${int.parse(m.group(1)!) * 12}',
    );
    s = s.replaceAll(RegExp(r'(?<=^|\s)دست[ةه](?=\s|$)'), '12');
    s = s.replaceAll(RegExp(r'(?<=^|\s)حتتين(?=\s|$)'), '2 حتت');
    s = s.replaceAll(RegExp(r'(?<=^|\s)قطعتين(?=\s|$)'), '2 قطعة');
    s = s.replaceAll(RegExp(r'(?<=^|\s)علبتين(?=\s|$)'), '2 علبة');

    // 3. Compound hundreds + tens/units: "ميتين وخمسين" -> 250, "ميه وعشرين" -> 120
    final hundredsPattern = _hundredsMap.keys.join('|');
    final tensPattern = _tensMap.keys.join('|');
    final unitsPattern = _unitsMap.keys.join('|');

    s = s.replaceAllMapped(
      RegExp('($hundredsPattern)\\s+و($tensPattern)(?=\\s|\$|%)'),
      (m) => '${(_hundredsMap[m.group(1)!] ?? 0) + (_tensMap[m.group(2)!] ?? 0)}',
    );
    s = s.replaceAllMapped(
      RegExp('($hundredsPattern)\\s+و($unitsPattern)(?=\\s|\$|%)'),
      (m) => '${(_hundredsMap[m.group(1)!] ?? 0) + (_unitsMap[m.group(2)!] ?? 0)}',
    );
    s = s.replaceAllMapped(
      RegExp('($unitsPattern)\\s+و($tensPattern)(?=\\s|\$|%)'),
      (m) => '${(_unitsMap[m.group(1)!] ?? 0) + (_tensMap[m.group(2)!] ?? 0)}',
    );

    // 4. Standalone hundreds, tens, units
    for (final entry in _hundredsMap.entries) {
      s = s.replaceAll(RegExp('(?<=^|\\s)${entry.key}(?=\\s|\$|%)'), '${entry.value}');
    }
    for (final entry in _tensMap.entries) {
      s = s.replaceAll(RegExp('(?<=^|\\s)${entry.key}(?=\\s|\$|%)'), '${entry.value}');
    }
    for (final entry in _unitsMap.entries) {
      // Avoid turning "واحد" into "1" inside "الواحد بـ 300"
      if (entry.key == 'واحد') {
        s = s.replaceAll(
          RegExp(r'(?<!ال)(?<=^|\s)واحد(?=\s|$)'),
          '1',
        );
      } else {
        s = s.replaceAll(
          RegExp('(?<=^|\\s)${entry.key}(?=\\s|\$|%)'),
          '${entry.value}',
        );
      }
    }

    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class ScoredIntentResult {
  final AssistantNluIntent intent;
  final double score;
  final Map<String, dynamic> slots;
  final List<AssistantNluIntent> secondaryIntents;

  const ScoredIntentResult({
    required this.intent,
    required this.score,
    this.slots = const {},
    this.secondaryIntents = const [],
  });
}

/// Scores natural Egyptian/Arabic queries across ERP actions and analytical intents.
class AssistantIntentScorer {
  static ScoredIntentResult? score(
    String rawQuery, {
    required AssistantContextMemory context,
  }) {
    final numericText = AssistantArabicNormalizer.replaceSpokenNumbers(rawQuery);
    final q = AssistantArabicNormalizer.normalizeBasic(numericText);
    if (q.isEmpty) return null;

    // Preserve How-To guides and analytical queries from being hijacked by action intents
    if (q.startsWith('ازاي') ||
        q.startsWith('كيف') ||
        q.startsWith('خطوات') ||
        q.startsWith('طريقه') ||
        q.contains('ارخص مورد') ||
        q.contains('اكتر مقاس') ||
        q.contains('اكتر يوم') ||
        q.contains('ساعات الذروه') ||
        q.contains('ايه اللي اتعدل') ||
        q.contains('عندي سيوله') ||
        q.contains('معايا فلوس')) {
      return null;
    }

    // 1. Follow-up on previous context ("طيب وامبارح؟" / "وامبارح؟")
    if (RegExp(r'^(?:طيب\s+)?و?امبارح[؟?]?$').hasMatch(q) ||
        q == 'امس' ||
        q == 'وامس') {
      return ScoredIntentResult(
        intent: AssistantNluIntent.yesterdayFollowup,
        score: 10.0,
        slots: {'previousIntent': context.lastIntent},
      );
    }

    // 2. Contextual edit on last product ("لا خليه 500" / "خليه 500" / "هات نفس الصنف بس خلي السعر 400")
    if ((q.contains('نفس الصنف') && q.contains('سعر')) ||
        RegExp(r'^(?:لا\s+)?خلي[ه]?\s+(?:السعر\s+)?\d+').hasMatch(q)) {
      final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(q);
      if (numMatch != null && context.lastProductName != null) {
        return ScoredIntentResult(
          intent: AssistantNluIntent.updatePrice,
          score: 12.0,
          slots: {
            'mode': 'price',
            'productName': context.lastProductName,
            'value': double.parse(numMatch.group(1)!),
          },
        );
      }
    }

    // 3. Contextual purchase from same supplier ("وكمان واحد من نفس المورد بـ 250")
    if (q.contains('نفس المورد') ||
        (q.startsWith('وكمان ') && context.lastSupplierName != null)) {
      final costMatch = RegExp(r'(?:ب|بسعر|سعر)\s*(\d+(?:\.\d+)?)').firstMatch(q);
      final qtyMatch = RegExp(r'(?:^|\s)(\d+)(?=\s|$)').firstMatch(
        q.replaceFirst(RegExp(r'(?:ب|بسعر|سعر)\s*\d+(?:\.\d+)?'), ''),
      );
      return ScoredIntentResult(
        intent: AssistantNluIntent.recordPurchase,
        score: 12.0,
        slots: {
          if (context.lastProductName != null)
            'productName': context.lastProductName,
          if (context.lastSupplierName != null)
            'supplierName': context.lastSupplierName,
          if (costMatch != null) 'costEgp': double.parse(costMatch.group(1)!),
          'qty': qtyMatch != null ? int.parse(qtyMatch.group(1)!) : 1,
          'paymentType': context.lastPaymentType ?? 'cash',
        },
      );
    }

    final scores = <AssistantNluIntent, double>{};
    void addScore(AssistantNluIntent intent, double pts) {
      scores[intent] = (scores[intent] ?? 0) + pts;
    }

    // --- Action Intent Signals ---
    // Add Product
    final hasPurchaseVerb = RegExp(
      r'(?:^|\s)(?:اشتريت|اشتري|بشتري|شريت|جبت|شراء|مشتريات)(?=\s|$)',
    ).hasMatch(q);
    if (!hasPurchaseVerb &&
        (RegExp(r'(?:ضيف|اضيف|تضيف|ضف|نزل|انزل|سجل)\s+(?:لي\s+)?(?:صنف|منتج|بضاعه|موديل)').hasMatch(q) ||
            q.contains('بضاعه جديده') ||
            q.contains('صنف جديد') ||
            q.contains('منتج جديد'))) {
      addScore(AssistantNluIntent.addProduct, 7.0);
    }
    if (q.contains('بيشتري ب') || q.contains('بيتباع ب') || q.contains('تكلفه')) {
      addScore(AssistantNluIntent.addProduct, 4.0);
    }

    // Record Purchase
    if (hasPurchaseVerb) {
      addScore(AssistantNluIntent.recordPurchase, 7.5);
    }
    if (q.contains('من المورد') || q.contains('من الحاج') || q.contains('شكك') || q.contains('الواحد ب')) {
      addScore(AssistantNluIntent.recordPurchase, 4.0);
    }

    // Pay Supplier
    if (RegExp(r'(?:اديت|دفعت|ادفع|سددت|سداد)\s+(?:للمورد|لمورد|للحاج|لـ?\s*المورد|لـ?\s*مورد|مورد|الحاج|ل)').hasMatch(q) ||
        (q.contains('دفعه') && !q.contains('قسط'))) {
      addScore(AssistantNluIntent.paySupplier, 8.5);
    }

    // Collect Installment
    if (q.contains('دفع قسط') ||
        q.contains('تحصيل قسط') ||
        q.contains('من قسطه') ||
        (q.contains('قسط') && (q.contains('دفع') || q.contains('احصل')))) {
      addScore(AssistantNluIntent.collectInstallment, 9.0);
    }

    // Record Expense
    if (q.contains('مصروف') ||
        q.contains('طلع من الدرج') ||
        q.contains('صرفت') ||
        (q.startsWith('دفعت ') &&
            !q.contains('مورد') &&
            !q.contains('الحاج') &&
            !q.contains('قسط'))) {
      addScore(AssistantNluIntent.recordExpense, 8.0);
    }
    if (q.contains('كهربا') ||
        q.contains('ايجار') ||
        q.contains('مياه') ||
        q.contains('نت') ||
        q.contains('مرتب')) {
      addScore(AssistantNluIntent.recordExpense, 3.0);
    }

    // Add Customer
    if (RegExp(r'(?:ضيف|اضيف|اضافه)\s+(?:عميل|زبون)|(?:عميل|زبون)\s+جديد').hasMatch(q)) {
      addScore(AssistantNluIntent.addCustomer, 9.0);
    }

    // Update Price
    if (RegExp(r'(?:خلي|عدل|غير)\s+(?:لي\s+)?سعر').hasMatch(q)) {
      addScore(AssistantNluIntent.updatePrice, 9.0);
    }

    // Update Stock (including damage / breakage in stocktake)
    if (RegExp(r'(?:^|\s)(?:زود|نقص)\s+(?:لي\s+)?(?:رصيد|كميه)?').hasMatch(q) &&
        (q.contains('حتت') || q.contains('قطع') || q.contains('رصيد') || q.contains('كميه'))) {
      addScore(AssistantNluIntent.updateStock, 8.5);
    }
    if (RegExp(r'(?:^|\s)(?:اتكسر|باظ|ضاع|تالف)(?=\s|$)').hasMatch(q)) {
      addScore(AssistantNluIntent.updateStock, 9.0);
    }

    // Zakat
    if (q.contains('زكاه') || q.contains('الزكاه')) {
      addScore(AssistantNluIntent.calculateZakat, 9.5);
    }

    // --- Analytical / Advisory Intent Signals ---
    if (q.contains('متاخر في الفلوس') ||
        q.contains('اقساط متاخره') ||
        q.contains('الاقساط المتاخره') ||
        (q.contains('متاخر') && q.contains('اقساط')) ||
        q.contains('مين عليه فلوس') ||
        q.contains('متاخرين')) {
      addScore(AssistantNluIntent.overdueInstallments, 9.0);
    }

    if (q.contains('بوست') || q.contains('منشور') || q.contains('اشد بيه الزباين')) {
      addScore(AssistantNluIntent.promoPost, 9.0);
    }

    if (q.contains('نايمه ليه') ||
        q.contains('المبيعات قليله') ||
        q.contains('ليه البيع') ||
        q.contains('مبيعاتي نازله')) {
      addScore(AssistantNluIntent.salesDiagnosis, 8.5);
    }

    if (q.contains('بعت بكام') ||
        q.contains('ربح النهارده') ||
        q.contains('ربح اليوم') ||
        q.contains('صافي ربح اليوم') ||
        q.contains('كسبت كام') ||
        q.contains('مبيعات النهارده')) {
      addScore(AssistantNluIntent.todayProfit, 8.5);
    }

    if ((q.contains('خصم') && (q.contains('%') || q.contains('هخسر') || q.contains('هكسب'))) ||
        q.contains('ماذا لو')) {
      addScore(AssistantNluIntent.whatIfPricing, 9.5);
    }

    if (q.contains('ارخص') && (q.contains('بره') || q.contains('الزبون') || q.contains('ارد عليه')) ||
        q.contains('بيقول غالي') ||
        q.contains('السعر غالي') ||
        q.contains('بيقولي لاقيته') ||
        q.contains('لقيته بره')) {
      addScore(AssistantNluIntent.objectionReplies, 9.5);
    }

    if (scores.isEmpty) return null;

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = sorted.first;
    if (best.value < 6.0) return null;

    final secondary = sorted
        .skip(1)
        .where((e) => e.value >= 6.0 && e.value >= best.value - 2.0)
        .map((e) => e.key)
        .toList();

    final slots = AssistantSlotExtractor.extract(
      intent: best.key,
      numericText: numericText,
      context: context,
    );

    return ScoredIntentResult(
      intent: best.key,
      score: best.value,
      slots: slots,
      secondaryIntents: secondary,
    );
  }
}

/// Extracts structured slots from normalized & digit-converted merchant sentences.
class AssistantSlotExtractor {
  static Map<String, dynamic> extract({
    required AssistantNluIntent intent,
    required String numericText,
    required AssistantContextMemory context,
  }) {
    final norm = AssistantArabicNormalizer.normalizeBasic(numericText);
    switch (intent) {
      case AssistantNluIntent.addProduct:
        return _extractAddProduct(numericText, norm);
      case AssistantNluIntent.recordPurchase:
        return _extractPurchase(numericText, norm, context);
      case AssistantNluIntent.recordExpense:
        return _extractExpense(numericText);
      case AssistantNluIntent.paySupplier:
        return _extractPaySupplier(numericText);
      case AssistantNluIntent.collectInstallment:
        return _extractCollectInstallment(numericText);
      case AssistantNluIntent.addCustomer:
        return _extractAddCustomer(numericText);
      case AssistantNluIntent.updatePrice:
        return _extractUpdatePrice(numericText, context);
      case AssistantNluIntent.updateStock:
        return _extractUpdateStock(numericText, norm);
      case AssistantNluIntent.calculateZakat:
        return _extractZakat(numericText, norm);
      default:
        return const {};
    }
  }

  static String _stripLeadingPrefixes(String text) {
    var s = text.trim();
    final prefixRegex = RegExp(
      r'^(?:عايز|عاوز|محتاج|ممكن|لو\s+سمحت|ياريت|يا\s+ريت|حابب|[أا]ريد|[أا]بغ[يى]|[أا]نا|[إا]حنا|دلوقتي|بسرع[ةه]|ع\s+السريع|[إا]ني|[إا]ن)(?=\s|$)\s*',
    );
    while (true) {
      final next = s.replaceFirst(prefixRegex, '').trim();
      if (next == s) break;
      s = next;
    }
    return s;
  }

  static Map<String, dynamic> _extractAddProduct(String text, String norm) {
    var body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:ضيف|[أا]ضيف|تضيف|نضيف|هضيف|ضف|نزل|انزل|تنزل|سجل|[أا]سجل)?\s*(?:لي\s+)?(?:صنف|منتج|بضاع[ةه]|موديل)\s*(?:جديد[ةه]?)?\s*(?:ع\s+السيستم|على\s+السيستم)?\s*',
          ),
          '',
        )
        .trim();

    final costMatch = RegExp(
      r'(?:تكلف[ةه]|بيشتري\s+بـ?|بشتريه\s+بـ?|شراء\s+بـ?)\s*(\d+(?:\.\d+)?)',
    ).firstMatch(body);
    final sellMatch = RegExp(
      r'(?:بيتباع\s+بـ?|بيع\s+بـ?|بيع|سعر\s+البيع|سعر)\s*(\d+(?:\.\d+)?)',
    ).firstMatch(body);
    final qtyMatch = RegExp(
      r'(?:وعندي\s+منه|عندي\s+منه|كمي[ةه]|عدد)\s*(\d+)',
    ).firstMatch(body);

    final cutIndices = [
      if (costMatch != null) costMatch.start,
      if (sellMatch != null) sellMatch.start,
      if (qtyMatch != null) qtyMatch.start,
    ];
    String prodName = body;
    if (cutIndices.isNotEmpty) {
      cutIndices.sort();
      prodName = body.substring(0, cutIndices.first).trim();
    }
    prodName = prodName
        .replaceFirst(RegExp(r'^(?:جديد[ةه]?|اسمه)\s*'), '')
        .replaceFirst(RegExp(r'\s*(?:جديد[ةه]?|ع\s+السيستم)$'), '')
        .trim();

    return {
      if (prodName.isNotEmpty && prodName != 'جديد' && prodName != 'جديدة')
        'productName': prodName,
      if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
      if (sellMatch != null) 'sellEgp': double.tryParse(sellMatch.group(1)!),
      if (qtyMatch != null) 'qty': int.tryParse(qtyMatch.group(1)!),
    }..removeWhere((_, v) => v == null);
  }

  static Map<String, dynamic> _extractPurchase(
    String text,
    String norm,
    AssistantContextMemory context,
  ) {
    var body = text
        .replaceFirst(
          RegExp(
            r'^(?:عايز|عاوز|محتاج|[أا]نا)?\s*(?:اشتريت|[أا]شتري|جبت|شراء|سجل\s+مشتريات)\s*(?:لي\s+)?',
          ),
          '',
        )
        .trim();

    final isCredit =
        norm.contains('اجل') || norm.contains('شكك') || norm.contains('علي الحساب');

    // Leading quantity like "10 بناطيل جينز ..."
    int? leadingQty;
    final leadingQtyMatch = RegExp(r'^(\d+)\s+(?!جنيه|ج\.?م)').firstMatch(body);
    if (leadingQtyMatch != null) {
      leadingQty = int.tryParse(leadingQtyMatch.group(1)!);
      body = body.substring(leadingQtyMatch.end).trim();
    }

    final supMatch = RegExp(
      r'من\s+(?:المورد\s+|مورد\s+)?([^\d]+?)(?=\s+(?:الواحد\s+بـ?|بسعر|سعر|عدد|كمي[ةه]|نقدي|كاش|[آا]جل|شكك)|$)',
    ).firstMatch(body);
    final costMatch = RegExp(
      r'(?:الواحد\s+بـ?|بسعر|سعر|بـ)\s*(\d+(?:\.\d+)?)',
    ).firstMatch(body);
    final qtyMatch = RegExp(r'(?:عدد|كمي[ةه])\s*(\d+)').firstMatch(body);

    final cutIndices = [
      if (supMatch != null) supMatch.start,
      if (costMatch != null) costMatch.start,
      if (qtyMatch != null) qtyMatch.start,
    ];
    String prodName = body;
    if (cutIndices.isNotEmpty) {
      cutIndices.sort();
      prodName = body.substring(0, cutIndices.first).trim();
    }
    if (prodName == 'بضاعة' || prodName == 'بضاعه' || prodName == 'صنف' || prodName == 'واحد') {
      prodName = '';
    }

    final qty = qtyMatch != null ? int.tryParse(qtyMatch.group(1)!) : leadingQty;
    final supName = supMatch?.group(1)?.trim();

    return {
      if (prodName.isNotEmpty) 'productName': prodName,
      if (supName != null && supName.isNotEmpty) 'supplierName': supName,
      if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
      if (qty != null && qty > 0) 'qty': qty,
      'paymentType': isCredit ? 'credit' : 'cash',
    }..removeWhere((_, v) => v == null);
  }

  static Map<String, dynamic> _extractExpense(String text) {
    var body = text
        .replaceFirst(
          RegExp(
            r'^(?:عايز|عاوز|محتاج|[أا]نا)?\s*(?:سجل\s+مصروف|[أا]سجل\s+مصروف|[أا]ضف\s+مصروف|مصروف\s+جديد|دفعت|طلع\s+من\s+الدرج|صرفت)\s*',
          ),
          '',
        )
        .trim();
    body = body
        .replaceAll(RegExp(r'\s*(?:النهارده|النهاردة|اليوم|امبارح|جنيه|ج\.?م)\s*'), ' ')
        .trim();

    // Pattern A: "كهربا المحل 600"
    final trailingAmt = RegExp(r'(\d+(?:\.\d+)?)$').firstMatch(body);
    if (trailingAmt != null) {
      final cat = body.substring(0, trailingAmt.start).trim();
      return {
        if (cat.isNotEmpty) 'category': cat,
        'amountEgp': double.tryParse(trailingAmt.group(1)!),
      }..removeWhere((_, v) => v == null);
    }

    // Pattern B: "1500 ايجار"
    final leadingAmt = RegExp(r'^(\d+(?:\.\d+)?)\s+(.+)$').firstMatch(body);
    if (leadingAmt != null) {
      return {
        'amountEgp': double.tryParse(leadingAmt.group(1)!),
        'category': leadingAmt.group(2)!.trim(),
      }..removeWhere((_, v) => v == null);
    }

    return {
      if (body.isNotEmpty) 'category': body,
    };
  }

  static Map<String, dynamic> _extractPaySupplier(String text) {
    final body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:اديت|دفعت|[أا]دفع|سددت|سداد)\s+(?:للمورد|لمورد|لـ?\s*المورد|لـ?\s*مورد|مورد|لـ?(?=\s*الحاج|الحاج)|لـ?)?\s*',
          ),
          '',
        )
        .trim();
    final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
    String? supName;
    double? amount;
    if (amtMatch != null) {
      amount = double.tryParse(amtMatch.group(1)!);
      supName = body
          .substring(0, amtMatch.start)
          .trim()
          .replaceFirst(RegExp(r'\s+(?:دفع[ةه]|مبلغ|فلوس)$'), '')
          .trim();
    } else if (body.isNotEmpty) {
      supName = body;
    }
    if (supName != null && supName.startsWith('لحاج ')) {
      supName = 'الحاج ${supName.substring(5)}';
    }
    return {
      if (supName != null && supName.isNotEmpty) 'supplierName': supName,
      if (amount != null && amount > 0) 'amountEgp': amount,
    };
  }

  static Map<String, dynamic> _extractCollectInstallment(String text) {
    // e.g. "محمود العميل جه دفع 500 من قسطه" OR "العميل سارة علي دفع قسط 250"
    final m1 = RegExp(
      r'^(?:العميل\s+|الزبون\s+)?(.+?)\s+(?:العميل\s+|الزبون\s+)?(?:جه\s+)?(?:دفع|دفعت)\s+(?:قسط\s+)?(\d+(?:\.\d+)?)\s*(?:من\s+قسطه|قسط)?',
    ).firstMatch(text);
    if (m1 != null) {
      final name = m1.group(1)!.replaceAll(RegExp(r'\b(?:العميل|الزبون)\b'), '').trim();
      final amt = double.tryParse(m1.group(2)!);
      return {
        if (name.isNotEmpty) 'customerName': name,
        if (amt != null && amt > 0) 'amountEgp': amt,
      };
    }
    final m2 = RegExp(
      r'^(?:عايز|عاوز)?\s*(?:[أا]حصل|تحصيل)\s+قسط\s*(.*)$',
    ).firstMatch(text);
    if (m2 != null) {
      final rest = m2.group(1)!.trim();
      final amtMatch = RegExp(r'(\d+(?:\.\d+)?)$').firstMatch(rest);
      if (amtMatch != null) {
        final name = rest.substring(0, amtMatch.start).trim();
        return {
          if (name.isNotEmpty) 'customerName': name,
          'amountEgp': double.tryParse(amtMatch.group(1)!),
        };
      }
      return {if (rest.isNotEmpty) 'customerName': rest};
    }
    return const {};
  }

  static Map<String, dynamic> _extractAddCustomer(String text) {
    var body = text
        .replaceFirst(
          RegExp(
            r'^(?:عايز|عاوز)?\s*(?:ضيف|[أا]ضيف|[أا]ضف|[إا]ضاف[ةه])?\s*(?:عميل|زبون)\s*(?:جديد)?\s*',
          ),
          '',
        )
        .trim();
    if (body == 'جديد') body = '';
    final phoneMatch = RegExp(r'(\+?\d{8,15})$').firstMatch(body);
    if (phoneMatch != null) {
      final name = body.substring(0, phoneMatch.start).trim();
      return {
        if (name.isNotEmpty) 'customerName': name,
        'phone': phoneMatch.group(1)!.trim(),
      };
    }
    return {if (body.isNotEmpty) 'customerName': body};
  }

  static Map<String, dynamic> _extractUpdatePrice(
    String text,
    AssistantContextMemory context,
  ) {
    final body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:خلي|[أا]خلي|تخلي|عدل|[أا]عدل|تعدل|غير|[أا]غير|تغير|عدّل)\s+(?:لي\s+)?سعر\s+',
          ),
          '',
        )
        .trim();
    final numMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(body);
    double? val;
    String? prodName;
    if (numMatch != null) {
      val = double.tryParse(numMatch.group(1)!);
      prodName = body
          .substring(0, numMatch.start)
          .trim()
          .replaceFirst(RegExp(r'\s+(?:لـ?|إلى|الى|بـ?)$'), '')
          .trim();
    } else if (body.isNotEmpty) {
      prodName = body;
    }
    if ((prodName == null || prodName.isEmpty || prodName == 'نفس الصنف') &&
        context.lastProductName != null) {
      prodName = context.lastProductName;
    }
    return {
      'mode': 'price',
      if (prodName != null && prodName.isNotEmpty) 'productName': prodName,
      if (val != null && val > 0) 'value': val,
    };
  }

  static Map<String, dynamic> _extractUpdateStock(String text, String norm) {
    final isBreakage = norm.contains('اتكسر') ||
        norm.contains('باظ') ||
        norm.contains('ضاع') ||
        norm.contains('تالف') ||
        norm.contains('نقص');

    if (isBreakage && !norm.startsWith('نقص رصيد')) {
      final qtyMatch = RegExp(r'(\d+)\s*(?:حتت|قطع[ةه]?)?').firstMatch(text);
      final qty = qtyMatch != null ? int.tryParse(qtyMatch.group(1)!) : null;
      return {
        'mode': 'stock',
        if (qty != null && qty > 0) 'value': -qty,
      };
    }

    final body = text
        .replaceFirst(
          RegExp(r'^(?:زود|نقص)\s+(?:لي\s+)?(?:رصيد\s+|كمي[ةه]\s+)?'),
          '',
        )
        .trim();
    final numMatch = RegExp(r'(\d+)\s*(?:حتت|حت[ةه]|قطع[ةه])?$').firstMatch(body);
    int? val;
    String? prodName;
    if (numMatch != null) {
      val = int.tryParse(numMatch.group(1)!);
      if (val != null && isBreakage) val = -val;
      prodName = body.substring(0, numMatch.start).trim();
    } else if (body.isNotEmpty) {
      prodName = body;
    }
    return {
      'mode': 'stock',
      if (prodName != null && prodName.isNotEmpty) 'productName': prodName,
      if (val != null && val != 0) 'value': val,
    };
  }

  static Map<String, dynamic> _extractZakat(String text, String norm) {
    final isGregorian = norm.contains('ميلادي');
    final goldMatch = RegExp(
      r'(?:الذهب|ذهب|عيار\s*24|سعر)\s*(?:بـ?|ب|هو)?\s*(\d+(?:\.\d+)?)',
    ).firstMatch(text);
    double? goldPrice =
        goldMatch != null ? double.tryParse(goldMatch.group(1)!) : null;
    if (goldPrice == null) {
      final trailing = RegExp(r'(\d{3,6}(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?$').firstMatch(text);
      if (trailing != null) {
        goldPrice = double.tryParse(trailing.group(1)!);
      }
    }
    return {
      if (goldPrice != null && goldPrice > 0) 'goldPrice24': goldPrice,
      'isGregorianYear': isGregorian,
    };
  }
}

