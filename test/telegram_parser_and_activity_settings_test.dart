import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/features/pre_orders/data/services/telegram_message_parser.dart';
import 'package:clothes_erp/features/pre_orders/domain/entities/pre_order_entity.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';

void main() {
  group('TelegramMessageParser Tests', () {
    test('extracts single and multiple URLs correctly', () {
      const text = 'السلام عليكم، محتاج أحجز ده https://m.shein.com/ar/goods-p-12345.html ولينك تاني https://www.trendyol.com/brand/item-p-999';
      final links = TelegramMessageParser.extractLinks(text);
      expect(links.length, 2);
      expect(links[0], contains('shein.com'));
      expect(links[1], contains('trendyol.com'));
    });

    test('detects platform correctly from URL', () {
      expect(TelegramMessageParser.detectPlatform('https://shein.top/abc'), PreOrderPlatforms.shein);
      expect(TelegramMessageParser.detectPlatform('https://www.trendyol.com/item'), PreOrderPlatforms.trendyol);
      expect(TelegramMessageParser.detectPlatform('https://www.zara.com/eg/ar/coat'), PreOrderPlatforms.zara);
      expect(TelegramMessageParser.detectPlatform('https://www.amazon.eg/dp/B08X'), PreOrderPlatforms.amazon);
      expect(TelegramMessageParser.detectPlatform('https://unknown-shop.com/prod'), 'متجر خارجي');
    });

    test('extracts phone numbers accurately from multiple formats', () {
      expect(TelegramMessageParser.extractPhone('موبايل: 01012345678'), '01012345678');
      expect(TelegramMessageParser.extractPhone('رقمي +201123456789 للتواصل'), '01123456789');
      expect(TelegramMessageParser.extractPhone('تليفون: 012-3456-7890'), '01234567890');
      expect(TelegramMessageParser.extractPhone('01511223344'), '01511223344');
      expect(TelegramMessageParser.extractPhone('رسالة بدون رقم تليفون'), isNull);
    });

    test('extracts real customer name accurately with fallback', () {
      expect(TelegramMessageParser.extractCustomerName('الاسم مريم خالد'), 'مريم خالد');
      expect(TelegramMessageParser.extractCustomerName('الاسم: سارة أحمد'), 'سارة أحمد');
      expect(TelegramMessageParser.extractCustomerName('اسم العميل: محمد علي'), 'محمد علي');
      expect(TelegramMessageParser.extractCustomerName('اسم العميل محمد علي'), 'محمد علي');
      expect(TelegramMessageParser.extractCustomerName('العميل / مريم كمال'), 'مريم كمال');
      expect(TelegramMessageParser.extractCustomerName('الاسم- نورهان محمود'), 'نورهان محمود');
      expect(TelegramMessageParser.extractCustomerName('رسالة بدون اسم', defaultName: 'User Profile'), 'User Profile');
    });

    test('extracts deposit accurately', () {
      expect(TelegramMessageParser.extractDeposit('عربون: 200'), 200.0);
      expect(TelegramMessageParser.extractDeposit('عربون 50'), 50.0);
      expect(TelegramMessageParser.extractDeposit('عربون 500 جنيه مصري'), 500.0);
      expect(TelegramMessageParser.extractDeposit('العربون 150.50 ج'), 150.5);
      expect(TelegramMessageParser.extractDeposit('دفعت عربون 300 ج.م كاش'), 300.0);
      expect(TelegramMessageParser.extractDeposit('رسالة بدون عربون'), isNull);
    });

    test('extracts sale price accurately', () {
      expect(TelegramMessageParser.extractSalePrice('السعر: 450 جنيه'), 450.0);
      expect(TelegramMessageParser.extractSalePrice('سعر البيع 400'), 400.0);
      expect(TelegramMessageParser.extractSalePrice('السعر 400'), 400.0);
      expect(TelegramMessageParser.extractSalePrice('بسعر 350'), 350.0);
      expect(TelegramMessageParser.extractSalePrice('سعر البيع: 600 ج.م'), 600.0);
      expect(TelegramMessageParser.extractSalePrice('سعر القطاعي: 550'), 550.0);
      expect(TelegramMessageParser.extractSalePrice('سعر: 500'), 500.0);
      expect(TelegramMessageParser.extractSalePrice('price: 120.5'), 120.5);
      expect(TelegramMessageParser.extractSalePrice('سعر الجملة: 300'), isNull);
      expect(TelegramMessageParser.extractSalePrice('سعر الجملة 300'), isNull);
    });

    test('extracts cost / wholesale price accurately', () {
      expect(TelegramMessageParser.extractCostPrice('سعر الجملة: 300 ج'), 300.0);
      expect(TelegramMessageParser.extractCostPrice('سعر الجملة 300'), 300.0);
      expect(TelegramMessageParser.extractCostPrice('سعر التكلفة: 250 جنيه'), 250.0);
      expect(TelegramMessageParser.extractCostPrice('الجملة: 300 ج'), 300.0);
      expect(TelegramMessageParser.extractCostPrice('جملة 300'), 300.0);
      expect(TelegramMessageParser.extractCostPrice('جملة: 200'), 200.0);
      expect(TelegramMessageParser.extractCostPrice('تكلفة: 180'), 180.0);
      expect(TelegramMessageParser.extractCostPrice('cost: 90.0'), 90.0);
      expect(TelegramMessageParser.extractCostPrice('السعر: 450'), isNull);
    });

    test('cleanProductName extracts real customer product title', () {
      expect(
        TelegramMessageParser.cleanProductName('1. فستان أسود سواريه مقاس L السعر: 450 جنيه جملة: 300 https://shein.com/1'),
        'فستان أسود سواريه',
      );
      expect(
        TelegramMessageParser.cleanProductName('عايزة فستان أسود سواريه مقاس لارج بسعر 350'),
        'فستان أسود سواريه',
      );
      expect(
        TelegramMessageParser.cleanProductName('- بلوزة بيضاء شيفون مقاس M عدد 2'),
        'بلوزة بيضاء شيفون',
      );
      expect(
        TelegramMessageParser.cleanProductName('شوز جلد بيج مقاس 38'),
        'شوز جلد بيج',
      );
      expect(
        TelegramMessageParser.cleanProductName('المنتج 1: دبلة الخطوبة'),
        'دبلة الخطوبة',
      );
      expect(
        TelegramMessageParser.cleanProductName('المنتج: فستان أسود'),
        'فستان أسود',
      );
    });

    test('extracts size correctly without deposit confusion', () {
      expect(TelegramMessageParser.extractSize('فستان مقاس L لون أبيض'), 'L');
      expect(TelegramMessageParser.extractSize('شوز مقاس 39 كحلي'), '39');
      expect(TelegramMessageParser.extractSize('بلوزة مقاس اكس لارج'), 'XL');
      expect(TelegramMessageParser.extractSize('قميص سايز XXL'), 'XXL');
      expect(TelegramMessageParser.extractSize('عربون 50'), isNull);
      expect(TelegramMessageParser.extractSize('دبلة الخطوبة مقاس 18 عربون 50'), '18');
      expect(TelegramMessageParser.extractSize('فستان لارج عربون 50 وسعر البيع 450'), 'L');
      expect(TelegramMessageParser.extractSize('شنطة بدون مقاس'), isNull);
    });

    test('extracts color correctly from Arabic keywords', () {
      expect(TelegramMessageParser.extractColor('فستان مقاس M لون أسود شيك'), 'أسود');
      expect(TelegramMessageParser.extractColor('بلوزة كحلي مقاس لارج'), 'كحلي');
      expect(TelegramMessageParser.extractColor('جاكيت بيج مقاس 40'), 'بيج');
      expect(TelegramMessageParser.extractColor('صنف عادي بدون لون'), isNull);
    });

    test('extracts quantity correctly', () {
      expect(TelegramMessageParser.extractQuantity('عايز منه عدد 3 قطع'), 3);
      expect(TelegramMessageParser.extractQuantity('محتاج 2 من الصنف ده'), 2);
      expect(TelegramMessageParser.extractQuantity('أوردر لقطعة واحدة'), 1);
    });

    test('extracts SKU / Code correctly', () {
      expect(TelegramMessageParser.extractSku('كود: SH-99823 مقاس XL'), 'SH-99823');
      expect(TelegramMessageParser.extractSku('sku: TY12345'), 'TY12345');
    });

    test('parses multi-line per-item customer message with phone, name, deposit, and separate items', () {
      const message = '''
السلام عليكم
الاسم: سارة أحمد
موبايل: 01012345678
عربون: 300
1. فستان أسود سواريه مقاس L
https://m.shein.com/ar/dress-1.html
2. بلوزة بيضاء شيفون مقاس M عدد 2
https://m.shein.com/ar/blouse-2.html
3. شوز جلد بيج مقاس 38
''';

      final parsed = TelegramMessageParser.parse(
        message,
        senderName: 'Sara Profile',
        senderUsername: 'sara_tg',
      );

      // 1. Phone, Name, Deposit
      expect(parsed.customerName, 'سارة أحمد');
      expect(parsed.customerPhone, '01012345678');
      expect(parsed.deposit, 300.0);

      // 2. Separate Items
      expect(parsed.suggestedItems.length, 3);

      // Item 1
      final item1 = parsed.suggestedItems[0];
      expect(item1.productName, 'فستان أسود سواريه');
      expect(item1.variantDescription, contains('L'));
      expect(item1.variantDescription, contains('أسود'));
      expect(item1.quantity, 1);
      expect(item1.itemUrl, contains('dress-1.html'));

      // Item 2
      final item2 = parsed.suggestedItems[1];
      expect(item2.productName, 'بلوزة بيضاء شيفون');
      expect(item2.variantDescription, contains('M'));
      expect(item2.variantDescription, contains('أبيض'));
      expect(item2.quantity, 2);
      expect(item2.itemUrl, contains('blouse-2.html'));

      // Item 3
      final item3 = parsed.suggestedItems[2];
      expect(item3.productName, 'شوز جلد بيج');
      expect(item3.variantDescription, contains('38'));
      expect(item3.variantDescription, contains('بيج'));
      expect(item3.quantity, 1);
    });

    test('applies extracted sale price and cost price to PreOrderItemEntity', () {
      const message = '''
السلام عليكم
الاسم: ندى سامي
تليفون: 01099887766
عربون: 200
فستان سواريه مقاس L
السعر: 450 جنيه
سعر الجملة: 300 ج
عدد: 2
https://shein.com/item1
''';

      final parsed = TelegramMessageParser.parse(message);

      expect(parsed.customerName, 'ندى سامي');
      expect(parsed.customerPhone, '01099887766');
      expect(parsed.deposit, 200.0);
      expect(parsed.salePrice, 450.0);
      expect(parsed.costPrice, 300.0);

      expect(parsed.suggestedItems.length, 1);
      final item = parsed.suggestedItems.first;
      expect(item.productName, 'فستان سواريه');
      expect(item.unitPricePiasters, 45000); // 450 EGP
      expect(item.costPricePiasters, 30000); // 300 EGP
      expect(item.commissionPiasters, 15000); // 450 - 300 = 150 EGP
      expect(item.totalPricePiasters, 90000); // 45000 * 2
      expect(item.quantity, 2);
    });

    test('handles metadata without colons and ignores non-product lines', () {
      const message = '''
الاسم مريم خالد
موبايل 01012345678
المنتج 1: دبلة الخطوبة
المقاس 18
عربون 50
سعر الجملة 300
سعر البيع 450
اللينك: لسه
''';

      final parsed = TelegramMessageParser.parse(message);

      expect(parsed.customerName, 'مريم خالد');
      expect(parsed.customerPhone, '01012345678');
      expect(parsed.deposit, 50.0);
      expect(parsed.costPrice, 300.0);
      expect(parsed.salePrice, 450.0);

      // Should only have 1 product, NOT 8 phantom products from metadata lines
      expect(parsed.suggestedItems.length, 1);
      final item = parsed.suggestedItems.first;
      expect(item.productName, 'دبلة الخطوبة');
      expect(item.variantDescription, contains('18'));
      expect(item.variantDescription, isNot(contains('50')));
      expect(item.unitPricePiasters, 45000);
      expect(item.costPricePiasters, 30000);
      expect(item.commissionPiasters, 15000);
    });
  });

  group('ActivityType Aliases and Codes Tests', () {
    test('supports all aliases and canonical codes', () {
      expect(ActivityType.fromString('clothing'), ActivityType.clothing);
      expect(ActivityType.fromString('clothes'), ActivityType.clothing);

      expect(ActivityType.fromString('footwear_bags'), ActivityType.footwearBags);
      expect(ActivityType.fromString('shoes_bags'), ActivityType.footwearBags);

      expect(ActivityType.fromString('accessories_beauty'), ActivityType.accessoriesBeauty);
      expect(ActivityType.fromString('accessories'), ActivityType.accessoriesBeauty);

      expect(ActivityType.fromString('home_living'), ActivityType.homeLiving);
      expect(ActivityType.fromString('home'), ActivityType.homeLiving);

      expect(ActivityType.fromString('general'), ActivityType.general);
      expect(ActivityType.fromString('unknown_value'), ActivityType.clothing);
    });
  });
}
