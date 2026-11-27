import '../../../../core/utils/money.dart';
import 'assistant_chitchat_lexicon.dart';

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
  storePulse,
  topProfitProducts,
  endOfDayReport,
  topVariants,
  cheapestSupplier,
  searchByBarcodeOrSku,
  marginLeak,
  breakEven,
  cashierPerformance,
  budgetComparison,
  todayAudits,
  winBackCustomers,
  installmentReminderMessage,
  seasonPlan,
  inflationCalculator,
  liquidityStrategy,
  visualMerchandising,
  toggleBlindShiftClosing,
  toggleManagerPinProtection,
  toggleAllowManualDiscount,
  toggleAutoBackup,
  updateStoreName,
  updateStorePhone,
  backupNow,
  shiftSummary,
  preOrderQuery,
  preOrderCreate,
  deliveryQuery,
  repairQuery,
  walletQuery,
  walletTransfer,
  partnerShares,
  partnerWithdraw,
  undoLast,
  howToGuide,
  knowledge,
  confirm,
  cancel,
  chitchat,
  outOfScope,
  rejectOrFix,
  help,
  fuSameSupplier,
  fuOneMore,
  fuChangeValue,
  fuDetails,
  fuTone,
  fuCopy,
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
  String? userName;
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
    userName = null;
    lastIntent = null;
    lastFields = const {};
  }
}

/// Normalizes common Egyptian merchant typos, spoken numbers, and conversational particles.
class AssistantArabicNormalizer {
  static final _punctuationRegex = RegExp(r'[؟?!\.,،:;_\-"\(\)\[\]\{\}\\/+=*&^%$#@~`><|]');

  static String stripPunctuation(String text) {
    return text
        .replaceAll(_punctuationRegex, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizeBasic(String text) {
    var s = stripPunctuation(Money.normalizeDigits(text).trim().toLowerCase());
    s = s
        .replaceAll('ـ', '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  static final _prefixRegex = RegExp(
    r'^(?:'
    r'عايز|عاوز|عايزه|محتاج|محتاجين|ممكن\s+لو\s+سمحت|ممكن\s+تساعدني|ممكن|'
    r'لو\s+سمحت|يا\s+ريت|ياريت|حابب|نفسي|يا\s+باشا|يا\s+معلم|يا\s+هندسة|يا\s+هندسه|'
    r'يا\s+عم|يا\s+كبير|يا\s+ريس|يا\s+غالي|يا\s+مساعد|طيب|ينفع|هو\s+ينفع|تقدر|اوعى\s+تنسى|'
    r'ايوه|يلا|بقولك|قولي|انا\s+عايز|انا\s+عاوز|احنا\s+عايزين|عاوزين|تعالى|اسمع|'
    r'لو\s+فاضي|من\s+فضلك|بالله\s+عليك|اريد|ابغي|ابغى|انا|احنا|اني|ان'
    r')(?:\s+|$)',
  );

  static final _suffixRegex = RegExp(
    r'(?:\s+|^)(?:'
    r'دلوقتي|دلوقت|بسرعة|بسرعه|لو\s+سمحت|يا\s+باشا|يا\s+معلم|حالا|من\s+فضلك|'
    r'ضروري|النهاردة|النهارده|اليوم|يا\s+ريس|شكرا|بالله\s+عليك|ع\s+السريع|'
    r'يا\s+مساعد|يا\s+هندسة|يا\s+هندسه|يا\s+غالي|يا\s+كبير|يا\s+عم|معلش'
    r')$',
  );

  static String stripConversationalNoise(String text) {
    var s = text.trim();
    while (true) {
      final next = s.replaceFirst(_prefixRegex, '').trim();
      if (next == s) break;
      s = next;
    }
    while (true) {
      final next = s.replaceFirst(_suffixRegex, '').trim();
      if (next == s) break;
      s = next;
    }
    return s;
  }

  /// Computes Levenshtein edit distance between two normalized strings.
  static int levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final del = prev[j + 1] + 1;
        final ins = curr[j] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] =
            del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[b.length];
  }

  /// Fast check if two strings differ by at most 1 edit (substitution, insertion, deletion)
  /// with zero allocations and immediate early-exit.
  static bool isOneEditApart(String a, String b) {
    if (a == b) return false;
    final lenDiff = a.length - b.length;
    if (lenDiff > 1 || lenDiff < -1) return false;

    if (lenDiff == 0) {
      var diffs = 0;
      for (var i = 0; i < a.length; i++) {
        if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
          diffs++;
          if (diffs > 1) return false;
        }
      }
      return diffs == 1;
    }

    final s1 = lenDiff < 0 ? a : b;
    final s2 = lenDiff < 0 ? b : a;
    var i = 0, j = 0, diffs = 0;
    while (i < s1.length && j < s2.length) {
      if (s1.codeUnitAt(i) != s2.codeUnitAt(j)) {
        diffs++;
        if (diffs > 1) return false;
        j++;
      } else {
        i++;
        j++;
      }
    }
    return true;
  }

  static const _levenshteinVocab = <String, String>{
    'منتج': 'منتج',
    'مصروف': 'مصروف',
    'مصاريف': 'مصاريف',
    'مورد': 'مورد',
    'عميل': 'عميل',
    'زبون': 'زبون',
    'فاتوره': 'فاتورة',
    'رصيد': 'رصيد',
    'كميه': 'كمية',
    'تكلفه': 'تكلفة',
    'كهرباء': 'كهرباء',
    'ايجار': 'ايجار',
    'زكاه': 'زكاة',
    'الزكاه': 'الزكاة',
    'مبيعات': 'مبيعات',
    'مكسب': 'مكسب',
    'خساره': 'خسارة',
    'متاخر': 'متأخر',
    'بوست': 'بوست',
    'واتساب': 'واتساب',
    'بضاعه': 'بضاعة',
    'تفاوض': 'تفاوض',
    'شراكه': 'شراكة',
    'صيانه': 'صيانة',
    'موديل': 'موديل',
    'اقساط': 'اقساط',
    'تحصيل': 'تحصيل',
    'تحويل': 'تحويل',
    'شريك': 'شريك',
    'اوردر': 'اوردر',
    'عربون': 'عربون',
    'طيار': 'طيار',
    'محفظه': 'محفظة',
    'المحل': 'المحل',
    'مخزن': 'مخزن',
  };

  static const _safeNonTypoWords = <String>{
    'معروف',
    'مبيعاتي',
    'مصاريفي',
    'ارباحي',
    'فلوسي',
    'ساره',
    'تصفيه',
    'شراء',
    'موردين',
    'عملاء',
    'زباين',
    'تحويل',
    'شريك',
    'اوردر',
    'عربون',
    'طيار',
    'محفظه',
    'كهربا',
    'شريت',
    'اتفاوض',
    'نتفاوض',
    'يتفاوض',
    'وميه',
    'وميتين',
    'وتلاتميه',
    'وتلتميه',
    'واربعميه',
    'وخمسميه',
    'وستميه',
    'وسبعميه',
    'وتمنميه',
    'وتسعميه',
    'وعشرين',
    'وتلاتين',
    'واربعين',
    'وخمسين',
    'وستين',
    'وسبعين',
    'وتمانين',
    'وتسعين',
  };

  /// Corrects 1-character typos for core ERP & commerce tokens (length >= 4)
  /// using fast single-edit distance with zero heap allocation.
  static String correctTyposWithLevenshtein(String input) {
    final words = input.split(RegExp(r'\s+'));
    if (words.isEmpty) return input;

    final corrected = <String>[];
    for (final w in words) {
      final normW = normalizeBasic(w);
      if (normW.length < 4 ||
          RegExp(r'\d').hasMatch(normW) ||
          _levenshteinVocab.containsKey(normW) ||
          _safeNonTypoWords.contains(normW)) {
        corrected.add(w);
        continue;
      }

      String? bestMatch;
      for (final entry in _levenshteinVocab.entries) {
        if ((normW.length - entry.key.length).abs() > 1) continue;
        if (isOneEditApart(normW, entry.key)) {
          bestMatch = entry.value;
          break;
        }
      }
      corrected.add(bestMatch ?? w);
    }
    return corrected.join(' ');
  }

  /// Fixes common merchant typos, voice elongations & dialect variations.
  static String normalizeMerchantColloquial(String input) {
    var s = Money.normalizeDigits(input).trim();
    s = s.replaceAll('ـ', '');
    s = s.replaceAllMapped(
      RegExp(r'([\u0621-\u064A])\1{2,}'),
      (m) => m.group(1)!,
    );
    s = s.replaceAll('مييتين', 'ميتين');

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
      (r'(?<=^|\s)اعفر(?=\s|$)', 'اعرف'),
      (r'(?<=^|\s)النهار[ةده](?=\s|$)', 'النهارده'),
      (r'(?<=^|\s)المأخرين(?=\s|$)', 'المتاخرين'),
      (r'(?<=^|\s)محاكاه(?=\s|$)', 'محاكاه'),
      (r'(?<=^|\s)زاك[ةه](?=\s|$)', 'زكاه'),
      (r'(?<=^|\s)الزك[ةه](?=\s|$)', 'الزكاه'),
      (r'(?<=^|\s)كزا[ةه](?=\s|$)', 'زكاه'),
      (r'(?<=^|\s)النجيه(?=\s|$)', 'الجنيه'),
      (r'(?<=^|\s)فاترة(?=\s|$)', 'فاتورة'),
      (r'(?<=^|\s)تعملني(?=\s|$)', 'تعلمني'),
      (r'(?<=^|\s)صوة(?=\s|$)', 'صورة'),
      (r'(?<=^|\s)تلفون(?=\s|$)', 'تليفون'),
      (r'(?<=^|\s)افزع(?=\s|$)', 'الفرع'),
      (r'(?<=^|\s)افرع(?=\s|$)', 'الفرع'),
      (r'(?<=^|\s)خيله(?=\s|$)', 'خليه'),
      (r'(?<=^|\s)نفز(?=\s|$)', 'نفذ'),
      (r'(?<=^|\s)حامية(?=\s|$)', 'حماية'),
      (r'(?<=^|\s)البك\s+اب(?=\s|$)', 'الباك اب'),
      (r'(?<=^|\s)لاتلقائي(?=\s|$)', 'التلقائي'),
      (r'(?<=^|\s)الخمص(?=\s|$)', 'الخصم'),
      (r'(?<=^|\s)فعلل(?=\s|$)', 'فعل'),
      (r'(?<=^|\s)الددرج(?=\s|$)', 'الدرج'),
      (r'(?<=^|\s)الملح(?=\s|$)', 'المحل'),
      (r'(?<=^|\s)اللمحل(?=\s|$)', 'المحل'),
      (r'(?<=^|\s)المبوايلات(?=\s|$)', 'الموبايلات'),
      (r'(?<=^|\s)(?:LE|le)(?=\s|$)', 'جنيه'),
    ];
    for (final (pat, rep) in typoReplacements) {
      s = s.replaceAll(RegExp(pat), rep);
    }
    s = correctTyposWithLevenshtein(s);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const _hundredsMap = <String, int>{
    'اربعمية': 400,
    'اربعماية': 400,
    'ربعمية': 400,
    'خمسمية': 500,
    'خمسماية': 500,
    'تلاتمية': 300,
    'تلاتماية': 300,
    'تلتمية': 300,
    'تلتماية': 300,
    'تسعمية': 900,
    'تسعماية': 900,
    'سبعمية': 700,
    'سبعماية': 700,
    'تمنمية': 800,
    'تمنماية': 800,
    'ستمية': 600,
    'ستماية': 600,
    'ميتين': 200,
    'مية': 100,
  };

  static const _tensMap = <String, int>{
    'عشرين': 20,
    'تلاتين': 30,
    'اربعين': 40,
    'خمسين': 50,
    'ستين': 60,
    'سبعين': 70,
    'تمانين': 80,
    'تسعين': 90,
  };

  static const _unitsMap = <String, int>{
    'تسعتاشر': 19,
    'تمنتاشر': 18,
    'سبعتاشر': 17,
    'خمستاشر': 15,
    'اربعتاشر': 14,
    'تلاتاشر': 13,
    'تلتاشر': 13,
    'اتناشر': 12,
    'احداشر': 11,
    'حداشر': 11,
    'ستاشر': 16,
    'عشرة': 10,
    'عشره': 10,
    'تسعة': 9,
    'تسعه': 9,
    'تمانية': 8,
    'تمانيه': 8,
    'سبعة': 7,
    'سبعه': 7,
    'خمسة': 5,
    'خمسه': 5,
    'اربعة': 4,
    'اربعه': 4,
    'تلاتة': 3,
    'تلاته': 3,
    'اتنين': 2,
    'ستة': 6,
    'سته': 6,
    'واحد': 1,
  };

  static final _compoundUnitTenRx = RegExp(
    r'(?<=^|\s)(و)?(تسعة|تسعه|تمانية|تمانيه|سبعة|سبعه|ستة|سته|خمسة|خمسه|اربعة|اربعه|تلاتة|تلاته|اتنين|واحد)\s+و(عشرين|تلاتين|اربعين|خمسين|ستين|سبعين|تمانين|تسعين)(?=\s|$|%)',
  );

  static final _compoundHundredTailRx = RegExp(
    r'(?<=^|\s)(و)?(اربعمية|اربعماية|ربعمية|خمسمية|خمسماية|تلاتمية|تلاتماية|تلتمية|تلتماية|تسعمية|تسعماية|سبعمية|سبعماية|تمنمية|تمنماية|ستمية|ستماية|ميتين|مية)\s+و(\d{1,2}|عشرين|تلاتين|اربعين|خمسين|ستين|سبعين|تمانين|تسعين|تسعتاشر|تمنتاشر|سبعتاشر|خمستاشر|اربعتاشر|تلاتاشر|تلتاشر|اتناشر|احداشر|حداشر|ستاشر|عشرة|عشره|تسعة|تسعه|تمانية|تمانيه|سبعة|سبعه|خمسة|خمسه|اربعة|اربعه|تلاتة|تلاته|اتنين|ستة|سته|واحد)(?=\s|$|%)',
  );

  static final _standaloneNumberWordRx = RegExp(
    r'(?<=^|\s)(و)?(اربعمية|اربعماية|ربعمية|خمسمية|خمسماية|تلاتمية|تلاتماية|تلتمية|تلتماية|تسعمية|تسعماية|سبعمية|سبعماية|تمنمية|تمنماية|ستمية|ستماية|ميتين|مية|عشرين|تلاتين|اربعين|خمسين|ستين|سبعين|تمانين|تسعين|تسعتاشر|تمنتاشر|سبعتاشر|خمستاشر|اربعتاشر|تلاتاشر|تلتاشر|اتناشر|احداشر|حداشر|ستاشر|عشرة|عشره|تسعة|تسعه|تمانية|تمانيه|سبعة|سبعه|خمسة|خمسه|اربعة|اربعه|تلاتة|تلاته|اتنين|ستة|سته)(?=\s|$|%)',
  );

  static final _standaloneWahedRx = RegExp(r'(?<!ال)(?<=^|\s)(و)?واحد(?=\s|$)');

  /// Replaces spoken Egyptian numbers, compound thousands, and quantity units with numeric digits.
  static String replaceSpokenNumbers(String input) {
    var s = normalizeMerchantColloquial(input);

    // 1. Named fractional thousands & quantity units (compound thousands handled in Step 8)
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)ربع\s+[أا]لف(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}250',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)نص\s+[أا]لف(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}500',
    );

    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)نص\s+مليون(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}500000',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)مليون\s+ونص(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}1500000',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)مليون(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}1000000',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)ميت\s+(جني[هة]|قطعه|حبه|علبه)(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}100 ${m.group(1)}',
    );

    // 2. Thousands phrases
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:تلات|ثلاث)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 3000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:اربع|أربع)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 4000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:خمس|خمسة)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 5000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:ست|ستة)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 6000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:سبع|سبعة)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 7000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:تمن|ثماني|ثمانية)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 8000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:تسع|تسعة)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 9000');
    s = s.replaceAll(RegExp(r'(?:^|\s)(?:عشر|عشرة)\s*(?:تلاف|[آا]لاف|الاف)(?=\s|$)'), ' 10000');

    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:تلاف|[آا]لاف|الاف)'),
      (m) => ' ${int.parse(m.group(1)!) * 1000} ',
    );

    s = s.replaceAll(RegExp(r'(?:^|\s)عشرين\s+[أا]لف(?=\s|$)'), ' 20000');
    s = s.replaceAll(RegExp(r'(?:^|\s)تلاتين\s+[أا]لف(?=\s|$)'), ' 30000');
    s = s.replaceAll(RegExp(r'(?:^|\s)اربعين\s+[أا]لف(?=\s|$)'), ' 40000');
    s = s.replaceAll(RegExp(r'(?:^|\s)خمسين\s+[أا]لف(?=\s|$)'), ' 50000');
    s = s.replaceAll(RegExp(r'(?:^|\s)ستين\s+[أا]لف(?=\s|$)'), ' 60000');
    s = s.replaceAll(RegExp(r'(?:^|\s)سبعين\s+[أا]لف(?=\s|$)'), ' 70000');
    s = s.replaceAll(RegExp(r'(?:^|\s)تمانين\s+[أا]لف(?=\s|$)'), ' 80000');
    s = s.replaceAll(RegExp(r'(?:^|\s)تسعين\s+[أا]لف(?=\s|$)'), ' 90000');
    s = s.replaceAll(RegExp(r'(?:^|\s)مية\s+[أا]لف(?=\s|$)'), ' 100000');

    s = s.replaceAll(RegExp(r'(?:^|\s)[أا]لفين(?=\s|$)'), ' 2000');
    s = s.replaceAll(RegExp(r'(?<!كام\s)(?:^|\s)[أا]لف(?=\s|$)'), ' 1000');

    // 3. Quantity units
    s = s.replaceAll(RegExp(r'نص\s+دست[ةه]'), ' 6 ');
    s = s.replaceAll(RegExp(r'دستتين'), ' 24 ');
    s = s.replaceAllMapped(RegExp(r'(\d+)\s+دست[ةه]'), (m) => ' ${int.parse(m.group(1)!) * 12} ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)دست[ةه](?=\s|$)'), ' 12 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)حتتين(?=\s|$)'), ' 2 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)قطعتين(?=\s|$)'), ' 2 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)علبتين(?=\s|$)'), ' 2 ');

    // 4. Hundreds typos & alternates (ordered longest to shortest)
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:تلتيمة|تلتماية|تلتميه)(?=\s|$)'), ' 300 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:سبعيمة|سبعميه)(?=\s|$)'), ' 700 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:تمنيمة|تمنميه)(?=\s|$)'), ' 800 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:خمسميه)(?=\s|$)'), ' 500 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:ربعميه|اربعميه)(?=\s|$)'), ' 400 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:ستميه)(?=\s|$)'), ' 600 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:تسعميه)(?=\s|$)'), ' 900 ');
    s = s.replaceAll(RegExp(r'(?<=^|\s)(?:ميه)(?=\s|$)'), ' 100 ');

    // 5. Compound units + tens FIRST (e.g. خمسة وعشرين -> 25, وواحد وعشرين -> و21)
    s = s.replaceAllMapped(_compoundUnitTenRx, (m) {
      final prefix = m.group(1) != null ? 'و' : '';
      final u = _unitsMap[m.group(2)!]!;
      final t = _tensMap[m.group(3)!]!;
      return ' $prefix${u + t} ';
    });

    // 6. Compound hundreds + (1..99 digits / tens / units)
    s = s.replaceAllMapped(_compoundHundredTailRx, (m) {
      final prefix = m.group(1) != null ? 'و ' : '';
      final h = _hundredsMap[m.group(2)!]!;
      final tailStr = m.group(3)!;
      final tail = int.tryParse(tailStr) ??
          _tensMap[tailStr] ??
          _unitsMap[tailStr] ??
          0;
      return ' $prefix${h + tail} ';
    });

    // 7. Standalone hundreds, tens, units
    s = s.replaceAllMapped(_standaloneNumberWordRx, (m) {
      final prefix = m.group(1) != null ? 'و ' : '';
      final key = m.group(2)!;
      final val = _hundredsMap[key] ?? _tensMap[key] ?? _unitsMap[key]!;
      return ' $prefix$val ';
    });
    s = s.replaceAllMapped(
      _standaloneWahedRx,
      (m) => ' ${m.group(1) != null ? 'و ' : ''}1 ',
    );

    // 8. Compound thousands (e.g. "58 1000 ونص" -> "58500", "1000 و 200" -> "1200")
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s+1000\s+ونص(?=\s|$)'),
      (m) => '${int.parse(m.group(1)!) * 1000 + 500}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s+1000\s+وربع(?=\s|$)'),
      (m) => '${int.parse(m.group(1)!) * 1000 + 250}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s+1000\s+و\s*(\d+)(?=\s|$)'),
      (m) {
        final base = int.parse(m.group(1)!) * 1000;
        final tail = int.parse(m.group(2)!);
        if (tail < 1000) return '${base + tail}';
        return m.group(0)!;
      },
    );
    s = s.replaceAllMapped(
      RegExp(r'(\d+)\s+1000(?=\s|$)'),
      (m) => '${int.parse(m.group(1)!) * 1000}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)([1-9]\d*000)\s+ونص(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}${int.parse(m.group(1)!) + 500}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)([1-9]\d*000)\s+وربع(?=\s|$)'),
      (m) => '${m.group(0)!.startsWith(' ') ? ' ' : ''}${int.parse(m.group(1)!) + 250}',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?:^|\s)([1-9]\d*000)\s+و\s*(\d+)(?=\s|$)'),
      (m) {
        final tail = int.parse(m.group(2)!);
        if (tail < 1000) {
          return '${m.group(0)!.startsWith(' ') ? ' ' : ''}${int.parse(m.group(1)!) + tail}';
        }
        return m.group(0)!;
      },
    );

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
  static bool _hasAny(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text.contains(p)) return true;
    }
    return false;
  }

  static ScoredIntentResult? score(
    String rawQuery, {
    required AssistantContextMemory context,
  }) {
    final numericText = AssistantArabicNormalizer.replaceSpokenNumbers(rawQuery);
    final norm = AssistantArabicNormalizer.normalizeBasic(numericText);
    if (norm.isEmpty) return null;

    final core = AssistantArabicNormalizer.stripConversationalNoise(norm);

    // 0. Fast exact lookups for conversational & control intents
    const rejectSet = <String>{
      'لا', 'لأ', 'لا مش كدا', 'لا مش كده', 'غلط', 'مش ده', 'لا ده غلط', 'مش صح',
      'لا استنى', 'لا استني', 'استنى', 'استني', 'ثواني', 'لحظة', 'لحظه', 'دقيقة', 'دقيقه',
      'استنى شوية', 'استني شويه', 'مش مظبوط', 'لا غلطت', 'اتلخبطت', 'غلطت',
      'ده مش اللي قلته', 'اتلخبط', 'غلط في الرقم', 'مش دي', 'مش عاجبني غيرها', 'مش عاجبني',
    };
    const cancelSet = <String>{
      'الغي', 'إلغاء', 'الغاء', 'خلاص', 'بلاش', 'مش عايز', 'لا بلاش', 'سيبك', 'وقف',
      'انسى', 'انسي', 'مش عاوز', 'لأ خلاص', 'لا خلاص', 'تراجع', 'كنسل', 'cancel',
      'مفيش داعي', 'ولا يهمك سيبها', 'مش دلوقتي', 'بعدين', 'لا لا', 'ارجع', 'ماشي سيبها',
      'قفل', 'انهي العملية', 'انهي العمليه', 'مش محتاج', 'غيرت رأيي', 'غيرت رايي',
      'لا شكرا', 'لأ مش دي', 'لا مش دي', 'ولا حاجة', 'ولا حاجه', 'طنش',
    };
    const confirmSet = <String>{
      'ايوه', 'اه', 'ايوا', 'تمام', 'ماشي', 'اوكي', 'ok', 'اكيد', 'طبعا',
      'نفذ', 'نفذها', 'اعملها', 'يلا', 'ايوه نفذ', 'صح', 'مظبوط',
      'كمل', 'تمام كمل', 'موافق', 'ايوه كدا', 'ايوه كده', 'اتفضل',
      'اعمل كدا', 'اعمل كده', 'ايوة', 'آه', 'حاضر', 'ادي الاوامر', 'اتمم',
      'خلاص نفذ', 'تمام يا باشا نفذها', 'ماشي سجلها', 'هو ده', 'بالظبط', 'ايوه ده',
    };
    const chitchatSet = <String>{
      'صباح الخير', 'مساء الخير', 'السلام عليكم', 'سلام عليكم', 'ازيك', 'اهلا', 'هاي',
      'ازاي الحال', 'عامل ايه', 'يا مساعد', 'ازيك يا بيه', 'اهلين', 'هلا', 'صباح النور',
      'مساء النور', 'نهارك سعيد', 'نهارك فل', 'تسلم', 'شكرا', 'متشكر', 'تسلم ايدك',
      'الله يكرمك', 'جزاك الله خيرا', 'ميرسي', 'ممنون', 'مشكور', 'يعطيك العافية',
      'يعطيك العافيه', 'ربنا يخليك', 'كتر خيرك', 'الله ينور', 'بارك الله فيك',
      'تمام الحمد لله', 'الحمد لله', 'سلام', 'مع السلامة', 'مع السلامه', 'الى اللقاء',
      'الي اللقاء', 'باي', 'اشوفك بعدين', 'يلا سلام', 'في امان الله', 'تصبح على خير', 'تصبح علي خير',
      'ازي صحتك', 'ايه الدنيا', 'اي الدنيا', 'الدنيا ماشيه ازاي', 'اخبار الشغل ايه',
      'صباح الفل', 'صباح القشطه', 'صباح العسل', 'صباح الورد', 'مساء الفل', 'مساء الجمال',
      'مساء العسل', 'نهارك ابيض', 'يومك فل', 'منور الدنيا', 'عاش يا بطل', 'تسلم دماغك',
      'كتر الف خيرك', 'ربنا يباركلك', 'ربنا يعينك', 'الله يقويك', 'الله يفتح عليك',
      'على راسي', 'علي راسي', 'مفيش جديد', 'طمني عليك', 'كله تمام', 'ماشي الحال',
      'احلى مسا', 'احلي مسا', 'احلى صباح', 'احلي صباح', 'الف شكر ليك', 'ولا يهمك',
    };

    if (core.isEmpty) {
      for (final cw in confirmSet) {
        if (norm.startsWith('$cw ') || norm == cw) {
          return const ScoredIntentResult(intent: AssistantNluIntent.confirm, score: 20.0);
        }
      }
      for (final cw in cancelSet) {
        if (norm.startsWith('$cw ') || norm == cw) {
          return const ScoredIntentResult(intent: AssistantNluIntent.cancel, score: 20.0);
        }
      }
      for (final cw in chitchatSet) {
        if (norm.startsWith('$cw ') || norm == cw) {
          return const ScoredIntentResult(intent: AssistantNluIntent.chitchat, score: 20.0);
        }
      }
      for (final rw in rejectSet) {
        if (norm.startsWith('$rw ') || norm == rw) {
          return const ScoredIntentResult(intent: AssistantNluIntent.rejectOrFix, score: 20.0);
        }
      }
    }

    if (rejectSet.contains(core)) {
      return const ScoredIntentResult(intent: AssistantNluIntent.rejectOrFix, score: 20.0);
    }
    if (cancelSet.contains(core)) {
      return const ScoredIntentResult(intent: AssistantNluIntent.cancel, score: 20.0);
    }
    if (confirmSet.contains(core)) {
      return const ScoredIntentResult(intent: AssistantNluIntent.confirm, score: 20.0);
    }

    final chitchatMatch = ChitchatMatcher.match(norm);
    if (chitchatMatch != null) {
      if ((chitchatMatch.subIntent == 'setName' ||
              chitchatMatch.subIntent == 'changeName') &&
          chitchatMatch.extractedName != null) {
        context.userName = chitchatMatch.extractedName;
      } else if (chitchatMatch.subIntent == 'forgetName') {
        context.userName = null;
      }
      return ScoredIntentResult(
        intent: AssistantNluIntent.chitchat,
        score: 20.0,
        slots: {
          'subIntent': chitchatMatch.subIntent,
          if (chitchatMatch.extractedName != null)
            'extractedName': chitchatMatch.extractedName,
        },
      );
    }

    if (chitchatSet.contains(core)) {
      return const ScoredIntentResult(intent: AssistantNluIntent.chitchat, score: 20.0);
    }

    if (core.contains('تراجع عن اخر') ||
        core.contains('الغي اخر') ||
        core.contains('الغاء اخر') ||
        core.contains('ارجع اللي فات') ||
        core.contains('اخر عمليه غلط') ||
        core.contains('مسح اخر') ||
        core.contains('ارجع زي الاول') ||
        core.contains('اتراجع') ||
        core == 'undo') {
      return const ScoredIntentResult(intent: AssistantNluIntent.undoLast, score: 20.0);
    }

    final isHelp = core == 'help' ||
        core == 'مساعده' ||
        core == 'ساعدني' ||
        norm.contains('اوامر المساعد') ||
        norm.contains('بتعمل ايه') ||
        norm.contains('انت مين') ||
        norm.contains('تعرف تعمل ايه') ||
        norm.contains('ايه اللي بتعرفه') ||
        norm.contains('انت بتفهم') ||
        norm.contains('ايه الاوامر') ||
        norm.contains('فيه ايه من الاوامر') ||
        norm.contains('اساعدك ازاي') ||
        norm.contains('هتساعدني ازاي') ||
        norm.contains('ايه امكانياتك') ||
        norm.contains('انت ذكي') ||
        norm.contains('هتفهم عليا') ||
        norm.contains('بتتكلم مصري') ||
        norm.contains('انت اونلاين') ||
        norm.contains('انت محتاج نت') ||
        norm.contains('ازاي استعملك') ||
        norm.contains('ايه الجديد فيك') ||
        norm.contains('ممكن اطلب منك ايه') ||
        norm.contains('قايمه الاوامر') ||
        norm.contains('اعرضلي الاوامر');
    if (isHelp) {
      return const ScoredIntentResult(intent: AssistantNluIntent.help, score: 20.0);
    }

    // 1. Settings toggles & commands (must run before general cancel/confirm words)
    if (_hasAny(norm, ['قفل الورديه العمياء', 'الاقفال الاعمي', 'اخفي رصيد الدرج', 'يقفل بدون ما يشوف', 'قفله الورديه من غير'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.toggleBlindShiftClosing, score: 20.0);
    }
    if (_hasAny(norm, ['حمايه الرقم السري', 'pin المدير', 'كود المدير', 'رقم المدير السري', 'اطلب رقم سري'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.toggleManagerPinProtection, score: 20.0);
    }
    if (_hasAny(norm, ['الخصم اليدوي', 'السماح بالخصم', 'خصم الكاشير', 'خلي الكاشير يخصم', 'خصم يدوي'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.toggleAllowManualDiscount, score: 20.0);
    }
    if (_hasAny(norm, ['النسخ الاحتياطي التلقائي', 'الباك اب التلقائي', 'نسخه احتياطيه اوتوماتيك', 'حفظ نسخه تلقائي', 'باك اب اوتوماتيك', 'نسخه احتياطيه تلقائي'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.toggleAutoBackup, score: 20.0);
    }
    if (_hasAny(norm, ['غير اسم المحل', 'عدل اسم المحل', 'اسم المحل بقى', 'اسم المحل', 'غير اسم المتجر', 'اسم الفرع', 'اسم المتجر'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.updateStoreName, score: 20.0);
    }
    if (_hasAny(norm, ['غير تليفون المحل', 'عدل رقم تليفون المحل', 'رقم المحل بقى', 'رقم المحل', 'تليفون الفاتوره', 'غير رقم الموبايل بتاع المحل', 'رقم الواتساب بتاع المحل', 'تلفون الفاتوره'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.updateStorePhone, score: 20.0);
    }
    if (_hasAny(norm, ['نسخه احتياطيه فوريه', 'نسخه احتياطيه الان', 'باك اب دلوقتي', 'اعمل نسخه احتياطيه', 'اعمل باك اب', 'خد نسخه احتياطيه', 'خد نسخه من الداتا', 'خزن الداتا'])) {
      if (!norm.contains('ازاي') && !norm.contains('كيف') && !norm.contains('خطوات') && !norm.contains('طريقه')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.backupNow, score: 20.0);
      }
    }

    // 2. Business advisory queries with "ازاي" / questions (must run before generic howToGuide)
    if ((norm.contains('خصم') || norm.contains('تخفيض') || norm.contains('اوكازيون')) &&
        (norm.contains('ياثر') || norm.contains('هخسر') || norm.contains('هكسب') || norm.contains('الربح'))) {
      return const ScoredIntentResult(intent: AssistantNluIntent.whatIfPricing, score: 18.0);
    }
    if (norm.contains('سيوله') || (norm.contains('معايا فلوس') && norm.contains('بضاع'))) {
      return const ScoredIntentResult(intent: AssistantNluIntent.liquidityStrategy, score: 18.0);
    }
    if (_hasAny(norm, ['ارجع الزباين', 'ترتيب الفاترينه', 'ترتيب المحل', 'ارتب المحل', 'عرض البضاعه', 'هندسه ترتيب', 'ديكور المحل', 'العرض في المحل', 'اجذب الزبون من الشارع', 'ركن للعروض', 'استراتيجيه السيوله', 'اوزع الفلوس ازاي', 'ادير الكاش', 'رد علي الفصال', 'اقنع الزبون', 'اوصل لهدف', 'ازود الدخل', 'عميل زعلان', 'اسعر ازاي', 'الجنيه نزل'])) {
      if (norm.contains('ارجع الزباين') || norm.contains('استرداد العملاء') || norm.contains('بطلوا يجوا')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.winBackCustomers, score: 18.0);
      }
      if (norm.contains('الفاترينه') || norm.contains('ترتيب المحل') || norm.contains('ارتب المحل') || norm.contains('عرض البضاعه') || norm.contains('هندسه ترتيب') || norm.contains('ديكور') || norm.contains('العرض في المحل') || norm.contains('ترتيب البضاعه') || norm.contains('ركن للعروض') || norm.contains('اجذب الزبون')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.visualMerchandising, score: 18.0);
      }
      if (norm.contains('السيوله') || norm.contains('اوزع الفلوس') || norm.contains('ادير الكاش') || norm.contains('50 30 20')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.liquidityStrategy, score: 18.0);
      }
      if (norm.contains('الفصال') || norm.contains('اقنع الزبون') || norm.contains('بيقول غالي') || norm.contains('عميل زعلان')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.objectionReplies, score: 18.0);
      }
      if (norm.contains('اوصل لهدف') || norm.contains('ازود الدخل')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.goalPlanner, score: 18.0);
      }
      if (norm.contains('اسعر ازاي') || norm.contains('الجنيه نزل')) {
        return const ScoredIntentResult(intent: AssistantNluIntent.inflationCalculator, score: 18.0);
      }
    }

    // 2a. Conceptual / Encyclopedia Knowledge queries (must run before generic howToGuide, calculateZakat, breakEven)
    final isConceptualQuestion = _hasAny(norm, [
          'يعني ايه',
          'ايه هو',
          'ايه هي',
          'ما هو',
          'ما هي',
          'ايه الفرق بين',
          'الفرق بين',
          'نصاب الزكاه',
          'مفهوم ',
          'تعريف ',
          'اشرحلي',
          'اشرح لي',
          'اشرح ',
          'فهمني',
          'فهميني',
          'عايز افهم',
          'عاوز افهم',
          'نفسي افهم',
          'علمني',
          'علميني',
          'عايز اتعلم',
          'عاوز اتعلم',
          'عرفني',
          'عرفيني',
          'وضحلي',
          'وضح لي',
          'بسطلي',
          'بسط لي',
          'كلمني عن',
          'احكيلي عن',
          'قولي عن',
          'ايه فكره',
          'قواعد التفاوض',
          'مبادئ الاقناع',
          'بروتوكول احتواء',
          'دوره التحويل النقدي',
          'القوائم الماليه',
          'العرض الذي لا يرفض',
          'اتفاوض مع المورد',
          'اتفاوض ازاي',
          'ازاي اتعامل مع عميل غاضب',
          'عميل غاضب',
          'بضاعه نايمه',
          'سكريبت',
          'كريس فوس',
          'بيلفورت',
          'سيالديني',
          'هورموزي',
          'مايك ميكالوفيتش',
          'نظام eos',
          'جينو ويكمان',
          'اندي غروف',
          'باكو اندرهيل',
          'بيتر فادر',
          'القيمه العمريه',
          'lifetime value',
          'بلانوغرام',
          'planogram',
          'منع السرقات',
          'المخزون الرشيق',
          'lean retail',
          'علم التسوق',
          'منطقه الهبوط',
          'تاثير الطعم',
          'decoy effect',
          'اغنى رجل في بابل',
          'فقه المعاملات',
          'احكام البيع',
          'شبهة الربا',
        ]) &&
        !_hasAny(norm, [
          'احسب الزكاه',
          'احسب لي الزكاه',
          'احسب نقطه التعادل',
          'سجل',
          'ضيف',
          'اشرح اكتر',
          'وضح اكتر',
          'اشرحلي اكتر',
        ]);
    if (isConceptualQuestion) {
      return const ScoredIntentResult(
        intent: AssistantNluIntent.knowledge,
        score: 19.0,
      );
    }

    // 3. Module & specific queries that might contain "ازاي" protected before generic HowTo
    final isSpecificAdvisorOrModule = norm.contains('الدليفري ماشي ازاي') ||
        norm.contains('الديليفري ماشي ازاي') ||
        norm.contains('المحل ماشي ازاي') ||
        norm.contains('الدنيا ماشيه ازاي') ||
        norm.contains('المحل صحته عامله ازاي') ||
        norm.contains('اداء المحل عامل ازاي') ||
        norm.contains('ازاي ارتب المحل') ||
        norm.contains('ارتب المحل ازاي') ||
        norm.contains('ازاي الحال') ||
        norm.contains('اساعدك ازاي') ||
        norm.contains('هتساعدني ازاي') ||
        norm.contains('ازاي استعملك') ||
        norm.contains('ازاي ارجع الزباين') ||
        norm.contains('اوزع الفلوس ازاي') ||
        norm.contains('ادير الكاش ازاي') ||
        norm.contains('اسعر ازاي') ||
        norm.contains('ازاي اوصل لهدف') ||
        norm.contains('ازاي ازود الدخل');

    final isHowTo = !isSpecificAdvisorOrModule &&
        !_hasAny(norm, ['اشرح اكتر', 'وضح اكتر', 'اشرحلي اكتر']) &&
        (norm.contains('ازاي') ||
            norm.contains('كيف') ||
            norm.contains('خطوات') ||
            norm.contains('طريقه') ||
            norm.contains('فين الاقي') ||
            norm.contains('شرح') ||
            norm.contains('علمني') ||
            norm.contains('تعملني') ||
            norm.contains('دلني'));
    if (isHowTo) {
      return const ScoredIntentResult(
        intent: AssistantNluIntent.howToGuide,
        score: 18.0,
      );
    }



    const outOfScopePhrases = <String>[
      'رئيس مصر', 'الجو عامل ايه', 'سعر الدولار', 'ماتش الاهلي', 'احكيلي قصه',
      'اعمل لي واجب', 'ترجم الجمله', 'اخبار الكوره', 'اعمل اغنيه', 'اعمل لي اغنيه',
      'اشتري لي اكل', 'اجمل ممثله', 'الارض كرويه', 'اكتب قصيده', 'اكتب لي قصيده', 'كام الساعه',
      'الدنيا حر', 'اخبار البورصه', 'اتصل بزوجتي', 'شغل اغنيه', 'اعمل منبه',
      'عاصمه فرنسا', 'كود بايثون', 'كود جافا', 'كود دارت', 'كود فلاتر', 'كود برمجه',
      'نكته', 'قولي نكته', 'نكت', 'اضحكني', 'فزوره', 'رايك في الحكومه', 'اعمل رسمه',
      'قولي معلومه', 'ماتش الزمالك', 'اخبار السياسه', 'مين كسب', 'مين فاز', 'كاس العالم',
      'الدوري', 'محمد صلاح', 'ميسي', 'رونالدو',
      'طريقه عمل الكيكه', 'طبخه', 'اطبخ ايه', 'اكل ايه', 'وصفه اكل',
      'اغاني', 'افلام', 'مسلسلات', 'اخبار الفن', 'توقعات الابراج', 'حظك اليوم',
      'حاله الطقس', 'درجه الحراره', 'الطقس', 'الجو بكره', 'مطر',
      'ترجمه', 'ترجم لي', 'حل المساله', 'حل الواجب', 'بحبك', 'تتجوزني',
      'ترتيب الدوري', 'حجز ملعب', 'طريق الدائري', 'محطه مترو', 'ميكروباص',
      'اوبر', 'اندرايف', 'سعر البنزين', 'السوق السودا', 'سعر الدهب', 'سعر الذهب',
      'اسعار العربيات', 'اسعار الشقق', 'مكرونه بشاميل', 'كشري مصري', 'مطعم قريب',
      'تفسير حلم', 'مواعيد الصلاه', 'صلاه العصر', 'امساكيه رمضان', 'الويندوز مهنج',
      'الموبايل بيعلق', 'باسورد الواي فاي', 'لعبه ببجي', 'علاج الصداع', 'دكتور باطنه',
      'ميعاد القطر', 'الثانويه العامه', 'تنسيق الكليات', 'اخبار السياسه', 'هتمطر',
    ];
    for (final oos in outOfScopePhrases) {
      if (norm.contains(oos)) {
        return const ScoredIntentResult(intent: AssistantNluIntent.outOfScope, score: 20.0);
      }
    }

    // 5. Contextual follow-ups
    if (RegExp(r'^(?:طيب\s+)?و?امبارح[؟?]?$').hasMatch(norm) ||
        norm == 'امس' ||
        norm == 'وامس') {
      return ScoredIntentResult(
        intent: AssistantNluIntent.yesterdayFollowup,
        score: 15.0,
        slots: {'previousIntent': context.lastIntent},
      );
    }

    final normWordCount = norm.split(RegExp(r'\s+')).length;
    if (normWordCount <= 5 &&
        _hasAny(norm, ['تفاصيل اكتر', 'تفاصيل اكثر', 'اشرح اكتر', 'وضح اكتر', 'زود التفاصيل', 'هات التفاصيل'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.fuDetails, score: 15.0);
    }
    if (normWordCount <= 5 &&
        _hasAny(norm, ['خلي الرد رسمي', 'رد رسمي', 'صيغه رسميه', 'اسلوب رسمي', 'اختصر الرد'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.fuTone, score: 15.0);
    }
    if (normWordCount <= 5 &&
        _hasAny(norm, ['انسخ الرد', 'نسخ الرد', 'عايز انسخ', 'جهزها للنسخ', 'نسخه للنسخ'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.fuCopy, score: 15.0);
    }

    final isNewPurchaseWithSameSupplier = norm.contains('نفس المورد') &&
        (norm.contains('جبت') ||
            norm.contains('اشتريت') ||
            norm.contains('وكمان واحد') ||
            norm.contains('وكمان 1') ||
            RegExp(r'(?:^|\s)ب\s*\d+').hasMatch(norm));
    if (!isNewPurchaseWithSameSupplier &&
        (_hasAny(norm, ['نفس المورد', 'من نفس المورد', 'ونفس الحاج', 'نفس التاجر', 'نفس اللي فات', 'زي الاول']) ||
            norm == 'نفسه' ||
            norm == 'هو هو')) {
      return const ScoredIntentResult(intent: AssistantNluIntent.fuSameSupplier, score: 15.0);
    }

    if (_hasAny(norm, ['وكمان واحد', 'واحد كمان', 'كمان واحده', 'كمان واحدة', 'ضيف كمان', 'كرر العمليه', 'كمان مره'])) {
      return const ScoredIntentResult(intent: AssistantNluIntent.fuOneMore, score: 15.0);
    }

    if ((norm.contains('نفس الصنف') && norm.contains('سعر')) ||
        RegExp(r'^(?:لا\s+)?خلي[ه]?\s+(?:السعر\s+)?\d+').hasMatch(norm)) {
      final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(norm);
      return ScoredIntentResult(
        intent: AssistantNluIntent.updatePrice,
        score: 15.0,
        slots: {
          'mode': 'price',
          if (context.lastProductName != null) 'productName': context.lastProductName,
          if (numMatch != null) 'value': double.parse(numMatch.group(1)!),
        },
      );
    }

    final scores = <AssistantNluIntent, double>{};
    void addScore(AssistantNluIntent intent, double pts) {
      scores[intent] = (scores[intent] ?? 0) + pts;
    }

    // --- Core Action Intent Matchers ---
    final hasPurchaseVerb = RegExp(
      r'(?:^|\s)(?:اشتريت|شتريت|شريت|جبت|جيبت|استلمت|استلمنا|اشترينا|جالي|وصلني|وصلت|نزلت|طلبت\s+وجه|سجل\s+شراء|سجل\s+مشتريات|اسجل\s+مشتريات|سجل\s+فاتوره\s+شراء|فاتوره\s+مشتريات|فاتوره\s+شراء|سجلي\s+بضاعه\s+جت|اشتري|بشتري|هشتري|شراء|مشتريات|شحنه\s+جديده|بضاعه\s+جت|بضاعه\s+وصلت)(?=\s|$)',
    ).hasMatch(norm);

    if (hasPurchaseVerb && !norm.contains('اشتري مقاس ايه') && !norm.contains('اشتري ايه')) {
      addScore(AssistantNluIntent.recordPurchase, 10.0);
    }
    if (norm.contains('من مورد') ||
        norm.contains('من عند') ||
        norm.contains('من الحاج') ||
        norm.contains('من مصنع') ||
        norm.contains('من المورد') ||
        norm.contains('من نفس المورد') ||
        norm.contains('الواحد ب') ||
        norm.contains('علي الحساب') ||
        norm.contains('شكك') ||
        norm.contains('مدفعتش لسه')) {
      if (hasPurchaseVerb || norm.contains('وكمان واحد') || norm.contains('وكمان 1')) {
        addScore(AssistantNluIntent.recordPurchase, 7.0);
      }
    }

    // Pay Supplier
    final hasPayVerb = RegExp(
      r'(?:^|\s)(?:سدد|اسدد|سددت|سداد|دفعت|ادفع|حول|احول|اديت|ادي|اديه|اديله|اعطيت|سلمت|اسلم|سلمنا|خصم\s+من\s+حساب|سجل\s+دفعه|سجل\s+سداد|استلم\s+كاش|استلم|عليا\s+لـ?|خد\s+مني)(?=\s|$)',
    ).hasMatch(norm);
    final hasSupplierTarget = norm.contains('مورد') ||
        norm.contains('للمورد') ||
        norm.contains('الحاج') ||
        norm.contains('للحاج') ||
        norm.contains('تاجر') ||
        norm.contains('للتاجر') ||
        norm.contains('مصنع') ||
        norm.contains('للمصنع') ||
        norm.contains('شركه') ||
        norm.contains('للشركه') ||
        norm.contains('مؤسسه') ||
        norm.contains('للمؤسسه') ||
        norm.contains('المعلم') ||
        norm.contains('للمعلم') ||
        norm.contains('الاستاذ') ||
        norm.contains('للاستاذ') ||
        norm.contains('عم ') ||
        norm.contains('لعم ') ||
        norm.contains('ابو ') ||
        norm.contains('لابو ') ||
        norm.contains('خد مني') ||
        norm.contains('استلم مني') ||
        norm.contains('عليا ل') ||
        norm.contains('دفعت ل') ||
        norm.contains('اديت ل') ||
        norm.contains('سددت ل') ||
        norm.contains('سجل دفعه ل');

    if ((hasPayVerb || norm.contains('اسدد لمورد') || norm.contains('دفعه لمورد') || norm.contains('استلم') || norm.contains('خد مني')) &&
        (hasSupplierTarget || norm.contains('مورد')) &&
        !norm.contains('قسط') &&
        !hasPurchaseVerb) {
      addScore(AssistantNluIntent.paySupplier, 10.5);
    }

    // Collect Installment
    if (norm.contains('قسط') || norm.contains('اقساط')) {
      if (norm.contains('حصل') ||
          norm.contains('قبضت') ||
          norm.contains('استلمت') ||
          norm.contains('دفع') ||
          norm.contains('سدد') ||
          norm.contains('جاب') ||
          norm.contains('خد') ||
          norm.contains('اخد') ||
          norm.contains('اتدفع') ||
          norm.contains('تحصيل')) {
        addScore(AssistantNluIntent.collectInstallment, 11.0);
      }
    }

    // Add Product
    final hasAddProductKeywords = RegExp(
          r'(?:^|\s)(?:كارت\s+صنف|افتح\s+كارت|اعمل\s+كارت|صنف\s+جديد|منتج\s+جديد|بضاعه\s+جديده|موديل\s+جديد|ريفرنس\s+جديد|حاجه\s+جديده\s+للمخزن|ستايل\s+جديد)(?=\s|$)',
        ).hasMatch(norm) ||
        (RegExp(r'(?:^|\s)(?:ضيف|اضيف|هضيف|تضيف|نضيف|ضف|اضيفلك|نزل|انزل|تنزل|نزلي|سجل|اسجل|دخل|ادخل|اعمل|اعملي|اكتب)\s+(?:لي\s+)?(?:صنف|منتج|بضاعه|موديل|قطعه|كارت)').hasMatch(norm)) ||
        ((norm.contains('تكلفته') || norm.contains('شرائه') || norm.contains('بشتريه')) &&
            (norm.contains('بيعه') || norm.contains('هبيعه') || norm.contains('بيتباع')));

    final hasDirectItemAdd = RegExp(r'(?:^|\s)(?:ضيف|اضيف|هضيف|تضيف|نضيف|نزل|انزل|نزلي|دخل|ادخل|سجل|اسجل|اكتب|اعمل|اعملي)\s+').hasMatch(norm) &&
        (norm.contains('في المخزن') || norm.contains('للمحل') || norm.contains('جديد') || norm.contains('بسعر') || norm.contains('والكميه') || norm.contains('ادخلها') || norm.contains('هبيعها'));

    final isPreOrder = norm.contains('حجز') || norm.contains('احجز') || norm.contains('عربون');
    if (!hasPurchaseVerb &&
        !norm.contains('عميل') &&
        !norm.contains('زبون') &&
        !isPreOrder &&
        (hasAddProductKeywords || hasDirectItemAdd)) {
      addScore(AssistantNluIntent.addProduct, 9.5);
    }

    // Record Expense
    final isExpense = norm.contains('مصروف') ||
        norm.contains('مصاريف') ||
        norm.contains('صرفت') ||
        norm.contains('صرفنا') ||
        norm.contains('اتصرف') ||
        norm.contains('عدي مصروف') ||
        norm.contains('اكتب مصروف') ||
        norm.contains('حط مصروف') ||
        norm.contains('نزل مصروف') ||
        norm.contains('طلع مني') ||
        norm.contains('طلع من الدرج') ||
        norm.contains('من الدرج') ||
        norm.contains('سجلها مصروف') ||
        norm.contains('طلعت') ||
        norm.contains('فاتوره مواصلات') ||
        norm.contains('رسوم حكوميه') ||
        norm.contains('بقشيش') ||
        norm.contains('رسوم') ||
        (norm.startsWith('دفعت ') &&
            !hasSupplierTarget &&
            !norm.contains('قسط')) ||
        (norm.contains('دفعنا') && norm.contains('على'));

    const expenseCategories = [
      'كهربا', 'كهرباء', 'ايجار', 'مياه', 'ميه', 'نت', 'مرتب', 'مرتبات',
      'صيانه', 'اكياس', 'شحن', 'فطار', 'شاي', 'قهوه', 'قهوة',
      'نظافه', 'بنزين', 'مواصلات', 'دعايه', 'ورق', 'طباعه', 'ضيافه',
      'بوفيه', 'تكييف', 'رسوم', 'بقشيش', 'كرتون', 'كراتين', 'ادوات مكتبيه',
      'غداء عمال', 'غداء', 'عمال', 'باقه', 'لمبات', 'تيكت', 'شماعات', 'لزق', 'تغليف',
    ];
    final hasExpCat = expenseCategories.any((cat) => norm.contains(cat));
    if (isExpense || (hasExpCat && (norm.contains('دفعت') || norm.contains('فاتوره') || norm.contains('صرفت') || norm.contains('اتصرف') || norm.contains('دفعنا') || norm.contains('ادفع')))) {
      if (!hasSupplierTarget && !norm.contains('قسط') && !norm.contains('المصاريف مرتفعه ليه') && !norm.contains('هغطي مصاريفي') && !norm.contains('زادت ولا قلت') && !norm.contains('مقارنه المصاريف')) {
        addScore(AssistantNluIntent.recordExpense, 9.5);
      }
    }

    // Add Customer
    final hasCustomerNoun = norm.contains('عميل') ||
        norm.contains('زبون') ||
        norm.contains('عميله') ||
        norm.contains('زبونه') ||
        norm.contains('كارت عميل') ||
        norm.contains('حساب عميل');

    final hasCustomerAction = norm.contains('ضيف') ||
        norm.contains('اضيف') ||
        norm.contains('اضافه') ||
        norm.contains('سجل') ||
        norm.contains('اكتب') ||
        norm.contains('دخل') ||
        norm.contains('افتح حساب') ||
        norm.contains('اعمل كارت') ||
        norm.contains('جديد');

    if ((hasCustomerNoun && hasCustomerAction) ||
        norm.contains('جه المحل اول مره') ||
        norm.contains('افتح حساب ل') ||
        (hasCustomerNoun && (norm.contains('اسمه') || norm.contains('رقمه')))) {
      addScore(AssistantNluIntent.addCustomer, 10.0);
    }

    // Update Price
    if (RegExp(r'(?:غير|خلي|عدل|بدل|ضبط)\s+(?:لي\s+)?سعر').hasMatch(norm) ||
        RegExp(r'سعر\s+.+\s+(?:بقى|بقي|هو|وصل|خليه|خلي)\s+\d+').hasMatch(norm) ||
        RegExp(r'(?:زود|نزل|ارفع|خفض)\s+سعر').hasMatch(norm) ||
        RegExp(r'(?:بقى|بقي)\s+بـ?\s*\d+').hasMatch(norm) ||
        norm.contains('السعر غلط عدله') ||
        norm.contains('غير سعر صنف') ||
        norm.contains('عدل سعر منتج') ||
        norm.contains('غالي خليه') ||
        norm.contains('سعر البيع بتاع') ||
        RegExp(r'اعمل\s+.+\s+بـ?\s*\d+').hasMatch(norm)) {
      addScore(AssistantNluIntent.updatePrice, 9.5);
    }

    // Update Stock
    final isStagnant = norm.contains('بضاعه واقفه') ||
        norm.contains('بضاعه راكده') ||
        norm.contains('اصناف راكده') ||
        norm.contains('المخزون الراكد') ||
        norm.contains('بضاعه مبتبعش') ||
        norm.contains('مبيتحركش') ||
        norm.contains('مبيتبعش') ||
        norm.contains('ترتيب البضاعه') ||
        norm.contains('ترتيب المحل');

    if (!hasPurchaseVerb && !norm.contains('مصروف') && !norm.contains('البضاعه الراكده') && !norm.contains('بضاعه الشتا') && !isStagnant) {
      if (RegExp(r'(?:زود|نقص|عدل|شيل|انقص|حط)\s+(?:لي\s+)?(?:رصيد|كميه)').hasMatch(norm) ||
          (!norm.contains('سعر') && RegExp(r'(?:زودلي|نقصلي|زود|نقص|شيل|انقص)\s+.+\s+\d+(?:\s*(?:حتت|حته|قطع|قطعه))?').hasMatch(norm)) ||
          RegExp(r'رصيد\s+.+\s+(?:المفروض|بقى|بقي|هو|طلع)\s+\d+').hasMatch(norm) ||
          RegExp(r'جرد\s+.+\s+طلع\s+\d+').hasMatch(norm) ||
          RegExp(r'(?:^|\s)(?:اتكسر|باظ|باظت|ضاع|تالف)(?:\s|$)').hasMatch(norm) ||
          norm.contains('الرصيد مش مظبوط عدله') ||
          norm.contains('اغير رصيد صنف') ||
          norm.contains('عدل كميه بضاعه') ||
          norm.contains('ضبط جرد') ||
          norm.contains('في المخزن عدلها') ||
          norm.contains('من الرصيد') ||
          RegExp(r'فيه\s+\d+\s+.+\s+بس\s+في\s+المخزن').hasMatch(norm)) {
        addScore(AssistantNluIntent.updateStock, 9.5);
      }
    }

    // Zakat
    if (norm.contains('زكاه') ||
        norm.contains('الزكاه') ||
        norm.contains('ازكي') ||
        norm.contains('زكاتي')) {
      addScore(AssistantNluIntent.calculateZakat, 10.0);
    }

    // --- Analytical / Advisory Intents ---
    if (_hasAny(norm, ['كسبت كام', 'ربح النهارده', 'الارباح النهارده', 'صافي ربح اليوم', 'الدخل النهارده', 'كسبان ولا خسران', 'المكسب كام', 'كسبنا كام', 'طلعت كام النهارده', 'الي دخل النهارده', 'ايه اللي كسبته', 'الربح مقارنه بامس', 'احسن من امبارح', 'بعت بكام', 'بعنا بكام', 'مبيعات النهارده', 'النهارده كام صافي'])) {
      if (!norm.contains('سجل') && !norm.contains('ضيف')) {
        addScore(AssistantNluIntent.todayProfit, 9.5);
      }
    }

    if (_hasAny(norm, ['المبيعات واقعه', 'المبيعات قليله', 'سبب نزول البيع', 'الشغل واقف', 'البيع نايم', 'مفيش بيع', 'المحل ميت', 'حلل لي سبب نزول المبيعات', 'ايه اللي حصل في المبيعات', 'مبيعاتي نزلت', 'مبيعاتي نازله', 'مبيعاتي بتقل', 'الكساد ده سببه ايه', 'الايراد قل', 'ليه الايراد', 'الزباين قلت', 'الدنيا رخمه ليه', 'السوق واقف ولا العيب فينا', 'نايمه ليه', 'الدنيا نايمه', 'البيع واقف', 'ليه البيع واقف'])) {
      addScore(AssistantNluIntent.salesDiagnosis, 10.0);
    }

    if (_hasAny(norm, ['الاقساط المتاخره', 'الاقساط اللي فاتت', 'مين متاخر', 'مين عليه فلوس', 'متاخرات الاقساط', 'الديون اللي ليا', 'مين مماطل', 'كشف العملاء المتاخرين', 'المتاخرين في السداد', 'المتاخرين', 'الفلوس اللي بره', 'مين لسه مدفعش'])) {
      addScore(AssistantNluIntent.overdueInstallments, 9.5);
    }

    if (_hasAny(norm, ['ماذا لو', 'لو عملت خصم', 'لو عملت تخفيضات', 'اوكازيون', 'لو زودت السعر', 'لو رفعت الاسعار', 'لو خصمت', 'محاكاه خصم', 'محاكاة خصم', 'لو خليت الخصم'])) {
      addScore(AssistantNluIntent.whatIfPricing, 9.5);
    }

    if (_hasAny(norm, ['بيقول غالي', 'الزبون بيقول غالي', 'السعر غالي', 'بيفاصل', 'رد علي الزبون', 'رد دبلوماسي', 'لقيتها ارخص', 'لاقيته بره ارخص', 'لقيته بره ارخص', 'بره ارخص', 'ارخص من كده', 'ارد عليه بايه', 'خصم كبير', 'اقنع الزبون', 'الزبون بيقول هفكر', 'الزبون عايز يرجع', 'اعمل ايه لو قال غالي', 'ازاي ارد علي الفصال', 'عميل زعلان'])) {
      addScore(AssistantNluIntent.objectionReplies, 9.5);
    }

    if (_hasAny(norm, [
      'المحل ماشي ازاي', 'نبض المحل', 'طمني علي الشغل', 'حال المحل', 'المحل عامل ايه',
      'الدنيا ماشيه ازاي', 'كله تمام النهارده', 'اديني لمحه سريعه', 'ملخص سريع',
      'ايه الوضع', 'شغلنا ماشي كويس', 'الحال ايه', 'عامل ايه المحل', 'ايه الاخبار',
      'قولي حال المحل', 'ايه اللي بيحصل في المحل', 'اطمن علي المحل', 'اطمن على المحل',
      'فيه ايه جديد في المحل', 'الشغل عامل ايه', 'قولي نبض المحل', 'طمني ع الشغل'
    ])) {
      addScore(AssistantNluIntent.storePulse, 9.0);
    }

    if (_hasAny(norm, ['صحه المحل', 'قيمني المحل', 'درجه المحل من 100', 'مؤشر صحه المحل', 'قيم شغلي', 'تشخيص المحل', 'هل المحل بحاله كويسه', 'اداء المحل عامل ازاي', 'المحل ماشي صح', 'نقاط المحل كام'])) {
      addScore(AssistantNluIntent.storeHealthScore, 9.0);
    }

    if (_hasAny(norm, ['ارفع المبيعات', 'هدف الشهر', 'اوصل لهدف', 'حطلي هدف', 'اهداف المبيعات', 'خطه تحقيق التارجت', 'خطه اوصل بيها', 'ازود الدخل', 'عايز ابيع بـ', 'ايه المطلوب عشان اوصل الهدف', 'عايز ابيع ب'])) {
      addScore(AssistantNluIntent.goalPlanner, 9.0);
    }

    if (_hasAny(norm, ['تقرير قفله اليوم', 'قفله النهارده', 'ملخص اليوم', 'تقرير اخر اليوم', 'تقرير اليوميه', 'تقفيل اليوم', 'رساله اليوميه', 'اقفل اليوم وقولي الحصيله', 'تقرير نهايه اليوم', 'اقفل اليوم وقوولي الحصيله'])) {
      addScore(AssistantNluIntent.endOfDayReport, 9.5);
    }

    if (_hasAny(norm, ['اكتر حاجه بتكسب', 'اعلي الاصناف ربحا', 'ايه اكتر صنف بيجيب فلوس', 'الاصناف الرابحه', 'اربح 5 اصناف', 'نجم المحل', 'ايه الحاجات اللي بتكسبني', 'اكتر منتج مكسب', 'الاكتر ربحيه', 'بضاعه بتكسب', 'الاصناف اللي بتجيب ربح', 'الاصناف الللي بتجيب'])) {
      addScore(AssistantNluIntent.topProfitProducts, 9.0);
    }

    if (_hasAny(norm, ['البضاعه الراكده', 'بضاعه راكده', 'اصناف راكده', 'المخزون الراكد', 'ايه اللي مش بيتباع', 'اصناف نايمه', 'بضاعه واقفه', 'المخزون الميت', 'اصفي الراكد', 'اصناف بقالها كتير', 'اتخلص من الراكد', 'راكد', 'بضاعه مبتبعش', 'مبيتحركش'])) {
      addScore(AssistantNluIntent.stagnantStock, 9.5);
    }

    if (_hasAny(norm, ['طلبيه الشراء', 'ايه اللي لازم اطلبه', 'نواقص المحل', 'النواقص', 'قايمه الطلبات', 'جهزلي طلبيه', 'ريستوك', 'اوشكت علي النفاد', 'اللي قرب يخلص', 'ايه اللي خلص', 'اطلب ايه النهارده', 'ايه المطلوب اشتريه', 'اشتري ايه', 'اللي رصيده قليل'])) {
      addScore(AssistantNluIntent.smartReorderList, 9.5);
    }

    if (_hasAny(norm, ['اكتر مقاس', 'اكتر لون', 'المقاسات الاكتر طلبا', 'الالوان الاكتر بيعا', 'اشتري مقاس ايه', 'الالوان اللي بتتطلب', 'المقاسات اللي بتخلص', 'لون الجينز اللي بيتباع', 'مقاس l ولا xl', 'المقاس الاكتر مطلوب', 'المقاس الاكثر مطلوب', 'اكتر مقاس مطلوب', 'المقاس المطلوب'])) {
      addScore(AssistantNluIntent.topVariants, 9.5);
    }

    if (_hasAny(norm, ['ارخص مورد', 'ارخص سعر للصنف', 'قارن اسعار الموردين', 'مقارنه الموردين', 'مين بيبيع ارخص', 'سعر مين احسن', 'اشتري من مين اوفر', 'مورد ارخص', 'اقل سعر في'])) {
      addScore(AssistantNluIntent.cheapestSupplier, 12.0);
    }

    if (_hasAny(norm, ['الباركود ده ايه', 'ابحث عن باركود', 'السكيو ده بتاع ايه', 'دورلي علي', 'دور علي صنف', 'رصيد الصنف', 'الصنف ده عندي ولا', 'تشوفلي صنف', 'سعر الصنف ده كام', 'لاقيلي المنتج', 'مش لاقي الرصيد', 'عندي بنطلون'])) {
      addScore(AssistantNluIntent.searchByBarcodeOrSku, 9.0);
    }

    if (_hasAny(norm, ['الفلوس بتروح فين', 'تسريب الارباح', 'تسرب الارباح', 'ايه اللي بياكل الربح', 'خصومات الكاشير', 'هامش الربح بيقل', 'الخصومات كتير', 'ليه الربح قليل', 'حد بيخصم زياده', 'فين الهامش', 'ايه اللي بيياكل'])) {
      addScore(AssistantNluIntent.marginLeak, 9.0);
    }

    if (_hasAny(norm, ['نقطه التعادل', 'ابيع بكام عشان اغطي', 'البريك ايفن', 'التعادل', 'لازم ابيع كام عشان مخسرش', 'اقل مبيعات تغطي', 'اقل بيع في اليوم', 'امتي هكسب', 'هغطي مصاريفي', 'هغطي مصاريف', 'حد ادني للمبيعات'])) {
      addScore(AssistantNluIntent.breakEven, 9.5);
    }

    if (_hasAny(norm, ['اداء الكاشير', 'مين احسن كاشير', 'الكاشيرات عاملين ايه', 'ترتيب الكاشيرات', 'مبيعات كل كاشير', 'مين اللي بيبيع اكتر', 'الموظفين بيشتغلوا كويس', 'تقييم العمال', 'بتاع الكاشير شاطر', 'مين شاطر من العمال'])) {
      addScore(AssistantNluIntent.cashierPerformance, 9.0);
    }

    if (_hasAny(norm, ['الملغيات النهارده', 'مين الغي فاتوره', 'فواتير ملغيه', 'سجل التدقيق', 'مين مسح حاجه', 'رقابه اليوم', 'حد لعب في حاجه', 'المرتجعات والالغاء', 'التعديلات النهارده', 'عمليات مشبوهه', 'مين لاغي فاتوره'])) {
      addScore(AssistantNluIntent.todayAudits, 9.0);
    }

    if (_hasAny(norm, ['بوست', 'منشور', 'اعلان للمحل', 'كابشن', 'رساله ترويجيه', 'اعملي بوست', 'اكتب اعلان', 'ريلز', 'اعلان باقه', 'اعمللي اعلان', 'عرض اعلنه', 'عايز عرض اعلنه'])) {
      addScore(AssistantNluIntent.promoPost, 9.0);
    }

    if (_hasAny(norm, ['عليا كام للموردين', 'مستحقات الموردين', 'مديونيه الموردين', 'حساب الموردين', 'الفلوس اللي عليا', 'ديوني', 'انا مديون بكام', 'مين لازم اسدده'])) {
      addScore(AssistantNluIntent.suppliersDues, 9.0);
    }

    if (_hasAny(norm, ['مقارنه المصاريف', 'ميزانيه المصاريف', 'المصاريف زادت ولا قلت', 'المصروفات زادت ولا قلت', 'تحليل المصروفات', 'المصاريف مرتفعه ليه', 'صرفنا كام الشهر ده', 'مصاريف الشهر ده ازاي', 'المصروفات زادت', 'المصاريف زادت'])) {
      addScore(AssistantNluIntent.budgetComparison, 10.0);
    }

    if (_hasAny(norm, ['رجع العملاء الغايبين', 'استرداد العملاء', 'رساله للعملاء القدام', 'رساله وحشتونا', 'كلم الزباين اللي اختفوا', 'العملاء اللي مجوش', 'بطلوا يجوا'])) {
      addScore(AssistantNluIntent.winBackCustomers, 9.0);
    }

    if (_hasAny(norm, ['رساله تذكير بالقسط', 'ذكر العميل بالقسط', 'تذكير الاقساط', 'رساله مطالبه بالقسط', 'كلم المتاخرين بشياكه', 'رساله للمتاخر', 'اكتبلي رساله للمتاخر', 'كلم المتاخرين', 'صيغه رساله قسط'])) {
      addScore(AssistantNluIntent.installmentReminderMessage, 9.0);
    }

    if (_hasAny(norm, ['خطه العيد', 'استعداد رمضان', 'موسم المدارس', 'خطه الصيف', 'عروض الشتا', 'البلاك فرايدي', 'بضاعه الشتا امتي اجيبها', 'اجهزه لرمضان', 'بضاعه الشتا'])) {
      addScore(AssistantNluIntent.seasonPlan, 9.5);
    }

    if (_hasAny(norm, ['التضخم', 'حاسبه التضخم', 'احسب الغلا', 'البضاعه غليت عليا', 'الدولار زاد اعمل ايه', 'الجنيه نزل اسعر ازاي', 'الاسعار غليت', 'غليت عليا', 'البضاعه غليت'])) {
      addScore(AssistantNluIntent.inflationCalculator, 9.0);
    }

    if (_hasAny(norm, ['استراتيجيه السيوله', 'قسم الارباح', '50 30 20', 'ادير الكاش', 'الفلوس مش فاضله', 'اصرف منين واحوش منين', 'السيوله قليله'])) {
      addScore(AssistantNluIntent.liquidityStrategy, 9.0);
    }

    if (_hasAny(norm, ['ترتيب الفاترينه', 'ديكور المحل', 'العرض في المحل', 'ركن للعروض', 'اجذب الزبون', 'ترتيب البضاعه', 'هندسه ترتيب', 'ارتب المحل'])) {
      addScore(AssistantNluIntent.visualMerchandising, 9.5);
    }

    // --- Extra Modules ---
    if (_hasAny(norm, ['الدرج المفتوح', 'الورديه المفتوحه', 'ملخص الدرج', 'الدرج فيه كام', 'الدرج دلوقتي', 'كام في الخزنه', 'الورديه اتقفلت', 'ملخص الورديه'])) {
      addScore(AssistantNluIntent.shiftSummary, 9.0);
    }

    if (_hasAny(norm, ['حجوزات', 'طلبات الحجز', 'الحجز المسبق', 'مين هيستلم النهارده', 'الحجوزات المعلقه', 'مين حاجز'])) {
      addScore(AssistantNluIntent.preOrderQuery, 9.0);
    }

    if (_hasAny(norm, ['سجل حجز', 'احجزلي قطعه', 'حجز بعربون', 'سجل عربون', 'عميل حجز', 'حجزت قطعه', 'احجزلي', 'اعمل حجز جديد', 'حجز جديد', 'اعمل حجز'])) {
      addScore(AssistantNluIntent.preOrderCreate, 10.5);
    }

    if (_hasAny(norm, ['عهده الطيارين', 'حساب الطيارين', 'طلبات الديليفري', 'الديليفري المعلق', 'الطيار معاه كام', 'الدليفري ماشي ازاي', 'الديليفري ماشي ازاي', 'الدليفري', 'الديليفري', 'فين الاوردر', 'الاوردر وصل', 'الاوردر فين'])) {
      addScore(AssistantNluIntent.deliveryQuery, 9.0);
    }

    if (_hasAny(norm, ['تذاكر الصيانه', 'الصيانه الجاهزه', 'اجهزه الصيانه', 'موبايل الصيانه خلص', 'الموبايلات اللي خلصت', 'جاهزه للتسليم', 'الاجهزه اللي جاهزه', 'صيانه الموبايل'])) {
      addScore(AssistantNluIntent.repairQuery, 9.0);
    }

    if (_hasAny(norm, ['رصيد المحافظ', 'المحافظ الالكترونيه', 'فودافون كاش', 'انستا باي', 'كاش المحفظه', 'المحفظه فيها كام'])) {
      addScore(AssistantNluIntent.walletQuery, 9.0);
    }

    if (_hasAny(norm, ['سجل تحويل', 'حول من محفظه', 'شحن محفظه', 'سحب من المحفظه', 'تحويل محفظه', 'حول رصيد'])) {
      addScore(AssistantNluIntent.walletTransfer, 10.5);
    }

    if (_hasAny(norm, ['حصص الشركاء', 'ارباح الشركاء', 'توزيع الارباح علي الشركاء', 'كل شريك له كام', 'نصيب كل شريك', 'نصيب كل شرك', 'حصه الشركاء', 'حصه كل شريك'])) {
      addScore(AssistantNluIntent.partnerShares, 9.0);
    }

    if (_hasAny(norm, ['الشريك خد فلوس', 'مسحوبات شريك', 'شريك سحب', 'سحب ابو علي', 'الشريك سحب', 'سحب شريك', 'مسحوبات الشركاء', 'سحب من الارباح'])) {
      addScore(AssistantNluIntent.partnerWithdraw, 10.5);
    }

    if (scores.isEmpty) return null;

    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
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
      case AssistantNluIntent.preOrderCreate:
        return _extractPreOrder(numericText);
      case AssistantNluIntent.walletTransfer:
        return _extractWalletTransfer(numericText, norm);
      case AssistantNluIntent.partnerWithdraw:
        return _extractPartnerWithdraw(numericText);
      default:
        return const {};
    }
  }

  static String _stripLeadingPrefixes(String text) {
    return AssistantArabicNormalizer.stripConversationalNoise(text);
  }

  static Map<String, dynamic> _extractAddProduct(String text, String norm) {
    var body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:ضيف|[أا]ضيف|تضيف|نضيف|هضيف|ضف|نزل|انزل|تنزل|سجل|[أا]سجل|دخل|[أا]دخل|اعمل|اعملي|[أا]فتح\s+كارت|[أا]عمل\s+كارت)?\s*(?:لي\s+)?(?:صنف|منتج|بضاع[ةه]|موديل|كارت|قطعة)?\s*(?:جديد[ةه]?)?\s*(?:ع\s+السيستم|على\s+السيستم|للمحل|في\s+المخزن)?\s*',
          ),
          '',
        )
        .trim();

    final costMatch = RegExp(
      r'(?:تكلف[ةه]|تكلفته|بيشتري\s+بـ?|بشتريه\s+بـ?|شراء\s+بـ?|شرائه\s+بـ?|شرائه)\s*(\d+(?:\.\d+)?)',
    ).firstMatch(body);
    final sellMatch = RegExp(
      r'(?:بيتباع(?:\s+بـ?)?|بيع(?:\s+بـ?)?|بيعه(?:\s+بـ?)?|وهبيعه(?:\s+بـ?)?|سعر\s+البيع|سعر|بسعر)\s*(\d+(?:\.\d+)?)',
    ).firstMatch(body);
    final qtyMatch = RegExp(
      r'(?:وعندي\s+منه|عندي\s+منه|كمي[ةه]|عدد|والكمية)\s*(\d+)',
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
        .replaceFirst(RegExp(r'\s*(?:جديد[ةه]?|ع\s+السيستم|في\s+المخزن|للمحل)$'), '')
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
    var body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:اشتريت|[أا]شتري|جبت|جيبت|استلمت|استلمنا|اشترينا|شراء|سجل\s+مشتريات|سجل\s+فاتورة\s+شراء)\s*(?:لي\s+)?',
          ),
          '',
        )
        .trim();

    final isCredit =
        norm.contains('اجل') || norm.contains('شكك') || norm.contains('علي الحساب');

    int? leadingQty;
    final leadingQtyMatch = RegExp(r'^(\d+)\s+(?!جنيه|ج\.?م)').firstMatch(body);
    if (leadingQtyMatch != null) {
      leadingQty = int.tryParse(leadingQtyMatch.group(1)!);
      body = body.substring(leadingQtyMatch.end).trim();
    }

    final supMatch = RegExp(
      r'من\s+(?:عند\s+)?(?:المورد\s+|مورد\s+)?([^\d]+?)(?=\s+(?:الواحد\s+بـ?|بسعر|سعر|بـ?\s*\d|عدد|كمي[ةه]|نقدي|كاش|[آا]جل|شكك)|$)',
    ).firstMatch(body);
    final costMatch = RegExp(
      r'(?:الواحد\s+بـ?|بسعر|سعر|بـ?)\s*(\d+(?:\.\d+)?)',
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
    if (prodName == 'بضاعة' ||
        prodName == 'بضاعه' ||
        prodName == 'صنف' ||
        prodName == 'واحد' ||
        prodName == 'وكمان' ||
        prodName == 'وكمان 1' ||
        prodName == 'كمان 1') {
      if (prodName == 'وكمان' || prodName == 'وكمان 1' || prodName == 'كمان 1') {
        leadingQty ??= 1;
      }
      prodName = context.lastProductName ?? '';
    } else if (prodName.isEmpty && context.lastProductName != null) {
      prodName = context.lastProductName!;
    }

    final qty = qtyMatch != null ? int.tryParse(qtyMatch.group(1)!) : leadingQty;
    var supName = supMatch?.group(1)?.trim();
    if (supName == 'نفس المورد' || supName == 'نفس التاجر' || supName == 'نفس الحاج') {
      supName = context.lastSupplierName;
    }

    return {
      if (prodName.isNotEmpty) 'productName': prodName,
      if (supName != null && supName.isNotEmpty) 'supplierName': supName,
      if (costMatch != null) 'costEgp': double.tryParse(costMatch.group(1)!),
      if (qty != null && qty > 0) 'qty': qty,
      'paymentType': isCredit ? 'credit' : 'cash',
    }..removeWhere((_, v) => v == null);
  }

  static Map<String, dynamic> _extractExpense(String text) {
    var body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:سجل\s+مصروف|[أا]سجل\s+مصروف|[أا]ضف\s+مصروف|مصروف\s+جديد|دفعت|طلع\s+من\s+الدرج|صرفت|صرفنا|دفعنا|اتصرف)\s*',
          ),
          '',
        )
        .trim();
    body = body
        .replaceAll(RegExp(r'\s*(?:النهارده|النهاردة|اليوم|امبارح|جنيه|ج\.?م)\s*'), ' ')
        .trim();

    final trailingAmt = RegExp(r'(\d+(?:\.\d+)?)$').firstMatch(body);
    if (trailingAmt != null) {
      var cat = body
          .substring(0, trailingAmt.start)
          .replaceFirst(RegExp(r'^(?:بـ?|على|لـ?)\s*'), '')
          .trim();
      if (cat == 'ب' || cat == 'على' || cat == 'ل') cat = '';
      return {
        if (cat.isNotEmpty) 'category': cat,
        'amountEgp': double.tryParse(trailingAmt.group(1)!),
      }..removeWhere((_, v) => v == null);
    }

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
    if (supName == 'تاجر' ||
        supName == 'التاجر' ||
        supName == 'لتاجر' ||
        supName == 'مورد' ||
        supName == 'المورد') {
      supName = '';
    }
    return {
      if (supName != null && supName.isNotEmpty) 'supplierName': supName,
      if (amount != null && amount > 0) 'amountEgp': amount,
    };
  }

  static Map<String, dynamic> _extractCollectInstallment(String text) {
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
    var body = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(
            r'^(?:ضيف|[أا]ضيف|[أا]ضف|[إا]ضاف[ةه]|سجل|اكتب|دخل)\s*(?:كارت\s+|حساب\s+)?(?:عميل|زبون|عميلة|زبونة)\s*(?:جديد)?\s*',
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
        .replaceAll(RegExp(r'\s+(?:دلوقتي|فورا|شكرا)$'), '')
        .replaceFirst(
          RegExp(
            r'^(?:(?:خلي|[أا]خلي|تخلي|عدل|[أا]عدل|تعدل|غير|[أا]غير|تغير|عدّل|بدل|ضبط)\s+(?:لي\s+)?)?سعر\s+',
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
          .replaceFirst(RegExp(r'\s+(?:لـ?|إلى|الى|بـ?|خلي[ه]?|بقى|بقي|هو|وصل)$'), '')
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

    final body = _stripLeadingPrefixes(text)
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

  static Map<String, dynamic> _extractPreOrder(String text) {
    final cleaned = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(r'^(?:سجل\s+حجز|احجزلي|حجز\s+بعربون|سجل\s+عربون|حجزت)\s*'),
          '',
        )
        .trim();
    final amtMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ج\.?م|جنيه)?').firstMatch(cleaned);
    final deposit = amtMatch != null ? double.tryParse(amtMatch.group(1)!) : null;
    final custMatch = RegExp(
      r'(?:للعميل|لـ?|عميل)\s+([^\d]+?)(?=\s+(?:عربون|بـ?\s*\d)|\s*$)',
    ).firstMatch(cleaned);
    var custName = custMatch?.group(1)?.trim();
    if (custName == null || custName.isEmpty) {
      final beforeNum = amtMatch != null
          ? cleaned.substring(0, amtMatch.start).trim()
          : cleaned;
      final stripped = beforeNum
          .replaceAll(RegExp(r'(?:بعربون|عربون|بـ)$'), '')
          .trim();
      if (stripped.isNotEmpty) custName = stripped;
    }
    return {
      if (custName != null && custName.isNotEmpty) 'customerName': custName,
      if (deposit != null && deposit > 0) 'amountEgp': deposit,
    };
  }

  static Map<String, dynamic> _extractWalletTransfer(String text, String norm) {
    final amtMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    final amt = amtMatch != null ? double.tryParse(amtMatch.group(1)!) : null;
    String walletName = 'محفظة إلكترونية';
    if (norm.contains('فودافون')) {
      walletName = 'فودافون كاش';
    } else if (norm.contains('انستا')) {
      walletName = 'انستا باي';
    } else if (norm.contains('اورانج')) {
      walletName = 'اورانج كاش';
    } else if (norm.contains('اتصالات')) {
      walletName = 'اتصالات كاش';
    }
    final isWithdraw = norm.contains('سحب');
    return {
      'walletName': walletName,
      'txType': isWithdraw ? 'withdraw' : 'deposit',
      if (amt != null && amt > 0) 'amountEgp': amt,
    };
  }

  static Map<String, dynamic> _extractPartnerWithdraw(String text) {
    final cleaned = _stripLeadingPrefixes(text)
        .replaceFirst(
          RegExp(r'^(?:الشريك\s+خد\s+فلوس|مسحوبات\s+شريك|شريك\s+سحب|سحب\s+الشريك|سحب)\s*'),
          '',
        )
        .trim();
    final amtMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
    final amt = amtMatch != null ? double.tryParse(amtMatch.group(1)!) : null;
    var partner = amtMatch != null
        ? cleaned.substring(0, amtMatch.start).trim()
        : cleaned;
    partner = partner.replaceAll(RegExp(r'(?:مبلغ|بـ|جنيه)$'), '').trim();
    return {
      if (partner.isNotEmpty) 'partnerName': partner,
      if (amt != null && amt > 0) 'amountEgp': amt,
    };
  }
}
