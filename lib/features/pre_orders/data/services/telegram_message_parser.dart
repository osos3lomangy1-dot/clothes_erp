import 'package:uuid/uuid.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';

class ParsedTelegramMessage {
  final List<String> links;
  final String? sku;
  final String? size;
  final String? color;
  final int qty;
  final String detectedPlatform;
  final List<PreOrderItemEntity> suggestedItems;
  final String? customerName;
  final String? customerPhone;
  final double? deposit;
  final double? salePrice;
  final double? costPrice;

  const ParsedTelegramMessage({
    required this.links,
    this.sku,
    this.size,
    this.color,
    required this.qty,
    required this.detectedPlatform,
    required this.suggestedItems,
    this.customerName,
    this.customerPhone,
    this.deposit,
    this.salePrice,
    this.costPrice,
  });
}

class TelegramMessageParser {
  static final _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );

  static final _phoneRegex = RegExp(
    r'(?:\+?20|0020)?\s*0?1[0125][0-9]{8}\b',
  );

  static final _nameRegex = RegExp(
    r'(?:اسم\s*العميل|الاسم|العميل)(?:\s*[:#\/\-]?\s+|\s*[:#\/\-]\s*)([^\n\r,\;،]+)',
    caseSensitive: false,
  );

  static final _depositRegex = RegExp(
    r'(?:دفعت\s*عربون|دفع\s*عربون|عربون|العربون)\s*[:#\/\-]?\s*(\d+(?:\.\d+)?)\s*(?:جنيه|ج\.م|ج|egp|le)?',
    caseSensitive: false,
  );

  static final _costPriceRegex = RegExp(
    r'(?:سعر\s*الجملة|سعر\s*التكلفة|الجملة|التكلفة|جملة|تكلفة|cost)\s*[:#\/\-]?\s*(\d+(?:\.\d+)?)\s*(?:جنيه|ج\.م|ج|egp|le)?',
    caseSensitive: false,
  );

  static final _salePriceRegex = RegExp(
    r'(?:سعر\s*البيع|سعر\s*القطاعي|السعر|القطاعي|قطاعي|بسعر|price|(?:سعر(?!\s*(?:الجملة|جملة|التكلفة|تكلفة))))\s*[:#\/\-]?\s*(\d+(?:\.\d+)?)\s*(?:جنيه|ج\.م|ج|egp|le)?',
    caseSensitive: false,
  );

  static final _skuRegex = RegExp(
    r'(?:كود|رمز|كود\s*شي\s*إن|sku|code)\s*[:#\-]?\s*([a-zA-Z0-9_\-]+)',
    caseSensitive: false,
  );

  static final _sizeKeywords = [
    '3XL', '2XL', 'XXL', 'XL', 'XS', 'S', 'M', 'L',
    '34', '35', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46', '47', '48', '49', '50',
    'سمول', 'ميديم', 'لارج', 'اكس لارج', 'دبل اكس', 'اوفر سايز'
  ];

  static final _colorKeywords = [
    'أسود', 'اسود', 'سوداء',
    'أبيض', 'ابيض', 'بيضاء',
    'أحمر', 'احمر', 'حمراء',
    'أزرق', 'ازرق', 'زرقاء',
    'كحلي', 'بيج', 'رمادي', 'رصاصي',
    'أخضر', 'اخضر', 'خضراء', 'زيتي',
    'وردي', 'بينك', 'بني', 'نبيتي',
    'أصفر', 'اصفر', 'صفراء', 'برتقالي',
    'موف', 'بنفسجي', 'فوشيا', 'تركواز', 'سماوي'
  ];

  /// استخراج رقم الموبايل (المصري أو الدولي المعتاد)
  static String? extractPhone(String text) {
    final cleanHyphen = text.replaceAll(RegExp(r'[\-\.]'), '');
    final match = _phoneRegex.firstMatch(cleanHyphen);
    if (match != null) {
      String phone = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
      if (phone.startsWith('+20')) {
        phone = '0${phone.substring(3)}';
      } else if (phone.startsWith('0020')) {
        phone = '0${phone.substring(4)}';
      } else if (phone.startsWith('20') && phone.length == 12) {
        phone = '0${phone.substring(2)}';
      } else if (!phone.startsWith('0')) {
        phone = '0$phone';
      }
      return phone;
    }
    return null;
  }

  /// استخراج الاسم الحقيقي للعميل من النص مع الرجوع للافتراضي عند عدم وجوده
  static String? extractCustomerName(String text, {String? defaultName}) {
    final match = _nameRegex.firstMatch(text);
    if (match != null) {
      String extracted = match.group(1)?.trim() ?? '';
      extracted = extracted
          .replaceAll(
            RegExp(
              r'(?:موبايل|تليفون|هاتف|عربون|العربون|سعر|جملة|تكلفة|اللينك|لينك|رقم).*$',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      extracted = extracted.replaceAll(RegExp(r'[\/\\:,\-;]+$'), '').trim();
      if (extracted.isNotEmpty && extracted.length >= 2) {
        return extracted;
      }
    }
    return defaultName?.trim();
  }

  /// استخراج مبلغ العربون
  static double? extractDeposit(String text) {
    final match = _depositRegex.firstMatch(text);
    if (match != null) {
      final numStr = match.group(1);
      if (numStr != null) {
        return double.tryParse(numStr);
      }
    }
    return null;
  }

  /// استخراج سعر البيع
  static double? extractSalePrice(String text) {
    final match = _salePriceRegex.firstMatch(text);
    if (match != null) {
      final numStr = match.group(1);
      if (numStr != null) {
        return double.tryParse(numStr);
      }
    }
    return null;
  }

  /// استخراج سعر الجملة / التكلفة
  static double? extractCostPrice(String text) {
    final match = _costPriceRegex.firstMatch(text);
    if (match != null) {
      final numStr = match.group(1);
      if (numStr != null) {
        return double.tryParse(numStr);
      }
    }
    return null;
  }

  /// استخراج الروابط
  static List<String> extractLinks(String text) {
    final links = <String>[];
    final urlMatches = _urlRegex.allMatches(text);
    for (final m in urlMatches) {
      final url = m.group(0)?.trim();
      if (url != null && url.isNotEmpty && !links.contains(url)) {
        links.add(url);
      }
    }
    return links;
  }

  /// التعرف على المنصة
  static String detectPlatform(String urlOrText) {
    final lower = urlOrText.toLowerCase();
    if (lower.contains('shein')) return PreOrderPlatforms.shein;
    if (lower.contains('trendyol')) return PreOrderPlatforms.trendyol;
    if (lower.contains('zara')) return PreOrderPlatforms.zara;
    if (lower.contains('amazon')) return PreOrderPlatforms.amazon;
    if (lower.contains('تفصيل') || lower.contains('تصنيع')) return PreOrderPlatforms.customTailoring;
    if (lower.contains('مورد') || lower.contains('تاجر') || lower.contains('محلي')) return PreOrderPlatforms.localSupplierOther;
    return 'متجر خارجي';
  }

  /// استخراج كود الصنف
  static String? extractSku(String text) {
    final skuMatch = _skuRegex.firstMatch(text);
    return skuMatch?.group(1)?.trim();
  }

  /// استخراج المقاس
  static String? extractSize(String text) {
    if (text.trim().isEmpty) return null;

    // 1. أولاً: تجريد مبالغ العربون وأسعار البيع والتكلفة وأرقام الهواتف والروابط
    // لمنع أي لبس بين أرقام المبالغ (مثل: عربون 50) والمقاسات العددية (مثل: مقاس 50)
    String sizeCandidate = text;
    sizeCandidate = sizeCandidate.replaceAll(_urlRegex, ' ');
    sizeCandidate = sizeCandidate.replaceAll(_phoneRegex, ' ');
    sizeCandidate = sizeCandidate.replaceAll(_depositRegex, ' ');
    sizeCandidate = sizeCandidate.replaceAll(_salePriceRegex, ' ');
    sizeCandidate = sizeCandidate.replaceAll(_costPriceRegex, ' ');
    sizeCandidate = sizeCandidate.replaceAll(
      RegExp(
        r'(?:عربون|العربون|دفعت|دفع|سعر|السعر|جملة|الجملة|تكلفة|التكلفة|قطاعي)\s*[:#\/\-]?\s*\d+(?:\.\d+)?',
        caseSensitive: false,
      ),
      ' ',
    );
    sizeCandidate = sizeCandidate.replaceAll(
      RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:جنيه|ج\.م|ج|egp|le)(?:\s|[^\w\u0600-\u06FF]|$)',
        caseSensitive: false,
      ),
      ' ',
    );

    // 2. الكلمات الدلالية النصية للمقاسات
    if (sizeCandidate.contains('اكس لارج') || sizeCandidate.contains('إكس لارج')) return 'XL';
    if (sizeCandidate.contains('دبل اكس') || sizeCandidate.contains('دبل إكس')) return 'XXL';
    if (sizeCandidate.contains('سمول')) return 'S';
    if (sizeCandidate.contains('ميديم')) return 'M';
    if (sizeCandidate.contains('لارج')) return 'L';
    if (sizeCandidate.contains('اوفر سايز')) return 'Oversized';

    // 3. البحث الصريح عن بادئة مقاس (مثل: المقاس 18 أو مقاس 38 أو مقاس L أو سايز 42)
    final explicitMatch = RegExp(
      r'(?:المقاس|مقاس|السايز|سايز|size)\s*[:#\-]?\s*([0-9]{1,3}|[a-zA-Z]{1,4})(?:\s|[^\w\u0600-\u06FF]|$)',
      caseSensitive: false,
    ).firstMatch(sizeCandidate);
    if (explicitMatch != null) {
      return explicitMatch.group(1)?.toUpperCase();
    }

    // 4. فحص المقاسات المتبقية بعد تجريد المبالغ والأسعار
    for (final s in _sizeKeywords) {
      if (RegExp(r'^[a-zA-Z]+$').hasMatch(s)) {
        final sizeRegex = RegExp('\\b$s\\b', caseSensitive: false);
        if (sizeRegex.hasMatch(sizeCandidate)) {
          return s;
        }
      } else {
        final numRegex = RegExp('(?<!\\d)$s(?!\\d)');
        if (sizeCandidate.contains('مقاس $s') || sizeCandidate.contains('سايز $s')) {
          return s;
        }
        if (numRegex.hasMatch(sizeCandidate)) {
          return s;
        }
      }
    }
    return null;
  }

  /// استخراج اللون
  static String? extractColor(String text) {
    for (final c in _colorKeywords) {
      if (text.contains(c)) {
        if (c == 'بيضاء' || c == 'ابيض') return 'أبيض';
        if (c == 'سوداء' || c == 'اسود') return 'أسود';
        if (c == 'حمراء' || c == 'احمر') return 'أحمر';
        if (c == 'زرقاء' || c == 'ازرق') return 'أزرق';
        if (c == 'خضراء' || c == 'اخضر') return 'أخضر';
        if (c == 'صفراء' || c == 'اصفر') return 'أصفر';
        return c;
      }
    }
    return null;
  }

  /// استخراج الكمية
  static int extractQuantity(String text) {
    final prefixMatch = RegExp(r'(?:عدد|الكمية|qty)\s*[:#\-]?\s*(\d+)', caseSensitive: false).firstMatch(text);
    if (prefixMatch != null) {
      return int.tryParse(prefixMatch.group(1) ?? '1') ?? 1;
    }

    final suffixMatch = RegExp(r'(\d+)\s*(?:قطع|قطعة|حبة|حبات|pcs|items?)\b', caseSensitive: false).firstMatch(text);
    if (suffixMatch != null) {
      return int.tryParse(suffixMatch.group(1) ?? '1') ?? 1;
    }

    final phraseMatch = RegExp(r'([1-9]\d?)\s+من').firstMatch(text);
    if (phraseMatch != null) {
      return int.tryParse(phraseMatch.group(1) ?? '1') ?? 1;
    }

    return 1;
  }

  /// استخراج اسم المنتج النظيف كما كتبه العميل بعد تجريده من الروابط والمقاسات والأرقام
  static String cleanProductName(
    String text, {
    String? fallbackPlatform,
    String? sku,
  }) {
    String cleaned = text;

    // 1. إزالة الروابط
    cleaned = cleaned.replaceAll(_urlRegex, ' ');

    // 2. إزالة الترقيم والتنقيط وبادئات ترقيم الأصناف (مثل: 1. أو 1- أو المنتج 1: أو المنتج: أو صنف 1:)
    cleaned = cleaned.replaceAll(
      RegExp(r'^(?:\d+[\.\)\-]|[\-\*•])\s*', multiLine: true),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^(?:المنتج|صنف|الصنف|البند|بند|قطعة|القطعة|item|product)\s*(?:\d+|رقم\s*\d+)?\s*[:#\/\-]?\s*',
        caseSensitive: false,
        multiLine: true,
      ),
      ' ',
    );

    // 3. إزالة أكواد الـ SKU
    cleaned = cleaned.replaceAll(_skuRegex, ' ');

    // 4. إزالة عبارات الكمية
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(?:العدد|عدد|الكمية|كمية|qty)\s*[:#\-]?\s*\d+\s*(?:قطع|قطعة|حبة|حبات|pcs|items?)?',
        caseSensitive: false,
      ),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\b\d+\s*(?:قطع|قطعة|حبة|حبات|pcs|items?)\b', caseSensitive: false),
      ' ',
    );

    // 5. إزالة عبارات المقاس الصريحة
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(?:المقاس|مقاس|السايز|سايز|size)\s*[:#\-]?\s*(?:[0-9]{1,3}|[a-zA-Z]{1,4}|اكس لارج|دبل اكس|لارج|ميديم|سمول|اوفر سايز)',
        caseSensitive: false,
      ),
      ' ',
    );

    // 6. إزالة الكلمات الدلالية للمقاس المستقلة
    cleaned = cleaned.replaceAll(RegExp(r'(?:\b(?:3XL|2XL|XXL|XL|XS|S|M|L)\b|اكس لارج|دبل اكس|لارج|ميديم|سمول|اوفر سايز)', caseSensitive: false), ' ');

    // 7. إزالة بادئات اللون الصريحة
    cleaned = cleaned.replaceAll(RegExp(r'(?:لون|اللون)\s*[:#\-]?\s*[^\s]+', caseSensitive: false), ' ');

    // 8. إزالة الكلمات الاستهلالية للطلب
    cleaned = cleaned.replaceAll(RegExp(r'^(?:عايز|عايزة|محتاج|محتاجة|طلب|أوردر|اريد|لو سمحت|ممكن|احجز|احجزلي|احجزيلي|وده|ودي|و ده|و دي|و)\s+', caseSensitive: false), ' ');

    // 9. إزالة عبارات أسعار البيع والتكلفة والعملات
    cleaned = cleaned.replaceAll(_salePriceRegex, ' ');
    cleaned = cleaned.replaceAll(_costPriceRegex, ' ');
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b\d+(?:\.\d+)?\s*(?:جنيه|ج\.م|ج|egp|le)(?:\s|[^\w\u0600-\u06FF]|$)',
        caseSensitive: false,
      ),
      ' ',
    );

    // 10. إزالة أسطر الميتا داتا إن كانت مدمجة (مع نقطتين اختيارية)
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(?:الاسم|اسم العميل|موبايل|تليفون|هاتف|عربون|العربون|العنوان|اللينك|لينك|سعر|جملة|تكلفة)\s*[:#\/\-]?.*$',
        caseSensitive: false,
      ),
      ' ',
    );

    // 11. تنظيف الفواصل والمسافات
    cleaned = cleaned.replaceAll(RegExp(r'[\/\\:,\-_;*•\(\)]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.length >= 2) {
      return cleaned;
    }

    if (sku != null && sku.isNotEmpty) {
      return 'صنف كود $sku';
    }
    if (fallbackPlatform != null && fallbackPlatform.isNotEmpty) {
      return 'صنف $fallbackPlatform';
    }
    return 'طلب صنف خارجي';
  }

  /// التحقق إن كان السطر مجرد بيانات وصفية (اسم/تليفون/عربون/تحية) وليس صنفاً
  static bool _isMetadataLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return true;

    // تحيات واستهلال
    if (RegExp(
      r'^(?:السلام\s*عليكم|صباح\s*الخير|مساء\s*الخير|أهلاً|اهلا|هاي|مرحبا|ازيك|ازي\s*حضرتك|شكرا|شكراً|تمام|اوك|اوكي)(?:\s|[^\w\u0600-\u06FF]|$)',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    // سطر الاسم (مع أو بدون نقطتين، مثال: الاسم مريم خالد أو الاسم: مريم خالد)
    if (RegExp(
      r'^(?:اسم\s*العميل|الاسم|العميل)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      if (!trimmed.startsWith('اسم المنتج') && !trimmed.startsWith('اسم الصنف')) {
        return true;
      }
    }

    // سطر الهاتف أو رقم هاتف مستقل
    if (RegExp(
      r'^(?:موبايل|تليفون|هاتف|رقم\s*الموبايل|رقم\s*الهاتف|phone|mobile)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^(?:\+?20|0020)?\s*0?1[0125][0-9]{8}$').hasMatch(
      trimmed.replaceAll(RegExp(r'[\s\-]'), ''),
    )) {
      return true;
    }

    // سطر العربون (مع أو بدون نقطتين، مثال: عربون 50 أو عربون: 50)
    if (RegExp(
      r'^(?:عربون|العربون|دفعت\s*عربون|دفع\s*عربون|deposit)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    // سطر سعر الجملة / التكلفة (مع أو بدون نقطتين، مثال: سعر الجملة 300 أو جملة 300)
    if (RegExp(
      r'^(?:سعر\s*الجملة|سعر\s*التكلفة|الجملة|التكلفة|جملة|تكلفة|cost)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    // سطر سعر البيع / القطاعي (مع أو بدون نقطتين، مثال: سعر البيع 400 أو السعر 400)
    if (RegExp(
      r'^(?:سعر\s*البيع|سعر\s*القطاعي|السعر|القطاعي|قطاعي|بسعر|price)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    // سطر اللينك إن لم يكن رابطاً حقيقياً (مثال: اللينك: لسه أو اللينك لسه)
    if (RegExp(
      r'^(?:اللينك|لينك|الرابط|رابط|link|url)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      if (!_urlRegex.hasMatch(trimmed)) {
        return true;
      }
    }

    // سطر العنوان
    if (RegExp(
      r'^(?:العنوان|محافظة|المدينة|مكان\s*الاستلام|address)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    // سطر الملاحظات أو الشحن
    if (RegExp(
      r'^(?:ملاحظات|ملاحظة|الشحن|مصاريف\s*الشحن|notes|note)\s*[:#\/\-\s]?',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  /// تقسيم نص الرسالة إلى كتل تمثل كل منها صنفاً مستقلاً
  static List<List<String>> _groupIntoItemBlocks(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final itemCandidateLines = <String>[];
    for (final line in lines) {
      if (!_isMetadataLine(line)) {
        itemCandidateLines.add(line);
      }
    }

    if (itemCandidateLines.isEmpty) {
      return [];
    }

    // 1. البحث عن الأسطر المرقمة أو المنقطة أو التي تبدأ ببادئة صنف (المنتج 1: ، صنف: ، 1. ، إلخ)
    final itemHeaderPattern = RegExp(
      r'^(?:(?:\d+[\.\)\-]|[\-\*•])\s+|(?:المنتج|صنف|الصنف|البند|بند|قطعة|القطعة|item|product)\s*(?:\d+|رقم\s*\d+)?\s*[:#\/\-]?\s+)',
      caseSensitive: false,
    );
    final hasItemHeaders = itemCandidateLines.any((l) => itemHeaderPattern.hasMatch(l));

    if (hasItemHeaders) {
      final blocks = <List<String>>[];
      List<String>? currentBlock;

      for (final line in itemCandidateLines) {
        if (itemHeaderPattern.hasMatch(line)) {
          if (currentBlock != null && currentBlock.isNotEmpty) {
            blocks.add(currentBlock);
          }
          currentBlock = [line];
        } else {
          if (currentBlock != null) {
            currentBlock.add(line);
          } else {
            currentBlock = [line];
          }
        }
      }
      if (currentBlock != null && currentBlock.isNotEmpty) {
        blocks.add(currentBlock);
      }
      return blocks;
    }

    // 2. في حالة عدم وجود تنقيط ولكن مع وجود روابط متعددة: تقسيم حول كل رابط
    final urlsInCandidates = <int>[];
    for (int i = 0; i < itemCandidateLines.length; i++) {
      if (_urlRegex.hasMatch(itemCandidateLines[i])) {
        urlsInCandidates.add(i);
      }
    }

    if (urlsInCandidates.length > 1) {
      final blocks = <List<String>>[];
      int lastIndex = 0;
      for (int i = 0; i < urlsInCandidates.length; i++) {
        final urlIdx = urlsInCandidates[i];
        final block = itemCandidateLines.sublist(lastIndex, urlIdx + 1);
        blocks.add(block);
        lastIndex = urlIdx + 1;
      }
      if (lastIndex < itemCandidateLines.length && blocks.isNotEmpty) {
        blocks.last.addAll(itemCandidateLines.sublist(lastIndex));
      }
      return blocks;
    }

    // 3. كتلة واحدة تمثل الصنف الواحد
    return [itemCandidateLines];
  }

  static ParsedTelegramMessage parseMessage({
    required String messageText,
    String? senderName,
    String? senderUsername,
  }) {
    return parse(messageText, senderName: senderName, senderUsername: senderUsername);
  }

  /// التحليل الشامل لرسالة تيليجرام واستخراج البيانات والأصناف المتعددة
  static ParsedTelegramMessage parse(
    String text, {
    String? senderName,
    String? senderUsername,
  }) {
    if (text.trim().isEmpty) {
      return const ParsedTelegramMessage(
        links: [],
        qty: 1,
        detectedPlatform: PreOrderPlatforms.shein,
        suggestedItems: [],
      );
    }

    // 1. استخراج البيانات العامة للعميل والأوردر
    final customerName = extractCustomerName(text, defaultName: senderName);
    final customerPhone = extractPhone(text);
    final deposit = extractDeposit(text);
    final allLinks = extractLinks(text);

    String defaultPlatform = PreOrderPlatforms.shein;
    if (allLinks.isNotEmpty) {
      defaultPlatform = detectPlatform(allLinks.first);
    } else {
      defaultPlatform = detectPlatform(text);
    }

    final globalSku = extractSku(text);
    final globalSize = extractSize(text);
    final globalColor = extractColor(text);
    final globalQty = extractQuantity(text);
    final globalSalePrice = extractSalePrice(text);
    final globalCostPrice = extractCostPrice(text);

    // 2. تقسيم الرسالة إلى بنود/أصناف متعددة
    final itemBlocks = _groupIntoItemBlocks(text);
    final suggestedItems = <PreOrderItemEntity>[];

    if (itemBlocks.isNotEmpty) {
      for (int i = 0; i < itemBlocks.length; i++) {
        final block = itemBlocks[i];
        final blockText = block.join('\n');

        final itemLinks = extractLinks(blockText);
        String? itemUrl;
        if (itemLinks.isNotEmpty) {
          itemUrl = itemLinks.first;
        } else if (i < allLinks.length) {
          itemUrl = allLinks[i];
        }

        final itemPlatform = itemUrl != null ? detectPlatform(itemUrl) : defaultPlatform;
        final itemSku = extractSku(blockText) ?? (itemBlocks.length == 1 ? globalSku : null);
        final itemSize = extractSize(blockText) ?? (itemBlocks.length == 1 ? globalSize : null);
        final itemColor = extractColor(blockText) ?? (itemBlocks.length == 1 ? globalColor : null);
        final itemQty = extractQuantity(blockText);
        final itemSalePrice = extractSalePrice(blockText) ?? (itemBlocks.length == 1 ? globalSalePrice : null);
        final itemCostPrice = extractCostPrice(blockText) ?? (itemBlocks.length == 1 ? globalCostPrice : null);

        int unitPricePiasters;
        int costPricePiasters;
        int commissionPiasters;

        if (itemSalePrice != null && itemCostPrice != null) {
          unitPricePiasters = (itemSalePrice * 100).toInt();
          costPricePiasters = (itemCostPrice * 100).toInt();
          commissionPiasters = unitPricePiasters - costPricePiasters;
        } else if (itemSalePrice != null) {
          unitPricePiasters = (itemSalePrice * 100).toInt();
          costPricePiasters = 0;
          commissionPiasters = 5000;
        } else if (itemCostPrice != null) {
          costPricePiasters = (itemCostPrice * 100).toInt();
          commissionPiasters = 5000;
          unitPricePiasters = costPricePiasters + commissionPiasters;
        } else {
          unitPricePiasters = 5000;
          costPricePiasters = 0;
          commissionPiasters = 5000;
        }

        final totalPricePiasters = unitPricePiasters * itemQty;

        final itemName = cleanProductName(
          blockText,
          fallbackPlatform: itemPlatform,
          sku: itemSku,
        );

        final colorAndSizeParts = <String>[];
        if (itemSize != null && itemSize.isNotEmpty) colorAndSizeParts.add('مقاس $itemSize');
        if (itemColor != null && itemColor.isNotEmpty) colorAndSizeParts.add('لون $itemColor');
        final variantDescription = colorAndSizeParts.join(' - ');

        suggestedItems.add(
          PreOrderItemEntity(
            id: const Uuid().v4(),
            preOrderId: '',
            productName: itemName,
            variantDescription: variantDescription.isNotEmpty ? variantDescription : null,
            itemUrl: itemUrl,
            quantity: itemQty,
            costPricePiasters: costPricePiasters,
            commissionPiasters: commissionPiasters,
            unitPricePiasters: unitPricePiasters,
            totalPricePiasters: totalPricePiasters,
            sourcePlatform: itemPlatform,
            status: 'active',
          ),
        );
      }
    } else {
      int fallbackUnitPricePiasters;
      int fallbackCostPricePiasters;
      int fallbackCommissionPiasters;

      if (globalSalePrice != null && globalCostPrice != null) {
        fallbackUnitPricePiasters = (globalSalePrice * 100).toInt();
        fallbackCostPricePiasters = (globalCostPrice * 100).toInt();
        fallbackCommissionPiasters = fallbackUnitPricePiasters - fallbackCostPricePiasters;
      } else if (globalSalePrice != null) {
        fallbackUnitPricePiasters = (globalSalePrice * 100).toInt();
        fallbackCostPricePiasters = 0;
        fallbackCommissionPiasters = 5000;
      } else if (globalCostPrice != null) {
        fallbackCostPricePiasters = (globalCostPrice * 100).toInt();
        fallbackCommissionPiasters = 5000;
        fallbackUnitPricePiasters = fallbackCostPricePiasters + fallbackCommissionPiasters;
      } else {
        fallbackUnitPricePiasters = 5000;
        fallbackCostPricePiasters = 0;
        fallbackCommissionPiasters = 5000;
      }

      final fallbackTotalPricePiasters = fallbackUnitPricePiasters * globalQty;

      // حالة الرسالة بدون نصوص أصناف (مثلاً روابط فقط)
      if (allLinks.isNotEmpty) {
        for (int i = 0; i < allLinks.length; i++) {
          final link = allLinks[i];
          final plat = detectPlatform(link);
          final itemName = globalSku != null
              ? 'صنف كود $globalSku'
              : (allLinks.length == 1 ? 'صنف $plat' : 'صنف ${i + 1} $plat');

          final colorAndSizeParts = <String>[];
          if (globalSize != null && globalSize.isNotEmpty) colorAndSizeParts.add('مقاس $globalSize');
          if (globalColor != null && globalColor.isNotEmpty) colorAndSizeParts.add('لون $globalColor');
          final variantDescription = colorAndSizeParts.join(' - ');

          suggestedItems.add(
            PreOrderItemEntity(
              id: const Uuid().v4(),
              preOrderId: '',
              productName: itemName,
              variantDescription: variantDescription.isNotEmpty ? variantDescription : null,
              itemUrl: link,
              quantity: globalQty,
              costPricePiasters: fallbackCostPricePiasters,
              commissionPiasters: fallbackCommissionPiasters,
              unitPricePiasters: fallbackUnitPricePiasters,
              totalPricePiasters: fallbackTotalPricePiasters,
              sourcePlatform: plat,
              status: 'active',
            ),
          );
        }
      } else {
        final itemName = globalSku != null ? 'صنف كود $globalSku' : 'طلب حجز من تيليجرام';
        final colorAndSizeParts = <String>[];
        if (globalSize != null && globalSize.isNotEmpty) colorAndSizeParts.add('مقاس $globalSize');
        if (globalColor != null && globalColor.isNotEmpty) colorAndSizeParts.add('لون $globalColor');
        final variantDescription = colorAndSizeParts.join(' - ');

        suggestedItems.add(
          PreOrderItemEntity(
            id: const Uuid().v4(),
            preOrderId: '',
            productName: itemName,
            variantDescription: variantDescription.isNotEmpty ? variantDescription : null,
            itemUrl: null,
            quantity: globalQty,
            costPricePiasters: fallbackCostPricePiasters,
            commissionPiasters: fallbackCommissionPiasters,
            unitPricePiasters: fallbackUnitPricePiasters,
            totalPricePiasters: fallbackTotalPricePiasters,
            sourcePlatform: defaultPlatform,
            status: 'active',
          ),
        );
      }
    }

    return ParsedTelegramMessage(
      links: allLinks,
      sku: globalSku,
      size: globalSize,
      color: globalColor,
      qty: globalQty,
      detectedPlatform: defaultPlatform,
      suggestedItems: suggestedItems,
      customerName: customerName,
      customerPhone: customerPhone,
      deposit: deposit,
      salePrice: globalSalePrice,
      costPrice: globalCostPrice,
    );
  }
}
