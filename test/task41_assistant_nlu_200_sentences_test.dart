import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_engine.dart';
import 'package:clothes_erp/features/dashboard/data/services/offline_smart_assistant_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late OfflineSmartAssistantService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = OfflineSmartAssistantService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 41.1: 15 Real Merchant Colloquial Sentences & Context Memory', () {
    test('handles all 15 real merchant scenarios accurately', () async {
      // 1. Add product (missing name)
      final d1a = service.parseErpDraft('عايز اضيف صنف جديد');
      expect(d1a?.kind, AssistantCommandKind.addProduct);
      expect(d1a?.missingField, 'productName');

      final d1b = service.parseErpDraft('محتاج انزل بضاعة جديدة ع السيستم');
      expect(d1b?.kind, AssistantCommandKind.addProduct);
      expect(d1b?.missingField, 'productName');

      // 2. Typo + spoken numbers + Arabic digits + "دستة"
      final d2 = service.parseErpDraft(
        'نزل لي منتح تيشيرت قطن بيشتري بـ ميتين وبيتباع بـ ٣٥٠ وعندي منه دستة',
      );
      expect(d2?.kind, AssistantCommandKind.addProduct);
      expect(d2?.isComplete, isTrue);
      expect(d2?.fields['productName'], 'تيشيرت قطن');
      expect(d2?.fields['costEgp'], 200.0);
      expect(d2?.fields['sellEgp'], 350.0);
      expect(d2?.fields['qty'], 12);

      // 3. Purchase with leading qty + supplier + credit ("شكك")
      final d3 = service.parseErpDraft(
        'جبت 10 بناطيل جينز من الحاج محمود الواحد بـ 300 شكك',
      );
      expect(d3?.kind, AssistantCommandKind.recordPurchase);
      expect(d3?.isComplete, isTrue);
      expect(d3?.fields['productName'], 'بناطيل جينز');
      expect(d3?.fields['qty'], 10);
      expect(d3?.fields['supplierName'], 'الحاج محمود');
      expect(d3?.fields['costEgp'], 300.0);
      expect(d3?.fields['paymentType'], 'credit');

      // 4. Context memory: "هات نفس الصنف بس خلي السعر 400" / "لا خليه ٥٠٠"
      final d4a = service.parseErpDraft('هات نفس الصنف بس خلي السعر 400');
      expect(d4a?.kind, AssistantCommandKind.updateProductPriceOrStock);
      expect(d4a?.fields['productName'], 'بناطيل جينز');
      expect(d4a?.fields['value'], 400.0);

      final d4b = service.parseErpDraft('لا خليه ٥٠٠');
      expect(d4b?.kind, AssistantCommandKind.updateProductPriceOrStock);
      expect(d4b?.fields['productName'], 'بناطيل جينز');
      expect(d4b?.fields['value'], 500.0);

      // 5. Context memory: "وكمان واحد من نفس المورد بـ 250"
      final d5 = service.parseErpDraft('وكمان واحد من نفس المورد بـ 250');
      expect(d5?.kind, AssistantCommandKind.recordPurchase);
      expect(d5?.fields['supplierName'], 'الحاج محمود');
      expect(d5?.fields['productName'], 'بناطيل جينز');
      expect(d5?.fields['costEgp'], 250.0);
      expect(d5?.fields['qty'], 1);

      // 6. Expenses: "دفعت كهربا المحل 600 جنيه النهارده" / "طلع من الدرج الف ونص ايجار"
      final d6a = service.parseErpDraft('دفعت كهربا المحل 600 جنيه النهارده');
      expect(d6a?.kind, AssistantCommandKind.recordExpense);
      expect(d6a?.fields['category'], 'كهربا المحل');
      expect(d6a?.fields['amountEgp'], 600.0);

      final d6b = service.parseErpDraft('طلع من الدرج الف ونص ايجار');
      expect(d6b?.kind, AssistantCommandKind.recordExpense);
      expect(d6b?.fields['category'], 'ايجار');
      expect(d6b?.fields['amountEgp'], 1500.0);

      // 7. Supplier payment: "اديت للحاج محمود دفعة 3 آلاف"
      final d7 = service.parseErpDraft('اديت للحاج محمود دفعة 3 آلاف');
      expect(d7?.kind, AssistantCommandKind.paySupplier);
      expect(d7?.fields['supplierName'], 'الحاج محمود');
      expect(d7?.fields['amountEgp'], 3000.0);

      // 8. Installment collection & overdue query
      final d8a = service.parseErpDraft('محمود العميل جه دفع 500 من قسطه');
      expect(d8a?.kind, AssistantCommandKind.collectInstallment);
      expect(d8a?.fields['customerName'], 'محمود');
      expect(d8a?.fields['amountEgp'], 500.0);

      final r8b = await service.ask('شوفلي مين متأخر في الفلوس');
      expect(r8b.any((i) => i.id == 'overdue_installments'), isTrue);

      // 9. Stock update & breakage in stocktake
      final d9a = service.parseErpDraft('زودلي الجاكيت الاسود 5 حتت');
      expect(d9a?.kind, AssistantCommandKind.updateProductPriceOrStock);
      expect(d9a?.fields['mode'], 'stock');
      expect(d9a?.fields['productName'], 'الجاكيت الاسود');
      expect(d9a?.fields['value'], 5);

      final d9b = service.parseErpDraft('اتكسر مني حتتين في الجرد');
      expect(d9b?.kind, AssistantCommandKind.updateProductPriceOrStock);
      expect(d9b?.fields['mode'], 'stock');
      expect(d9b?.fields['value'], -2);
      expect(d9b?.missingField, 'productName');

      // 10. Promo post on WhatsApp
      final r10 = await service.ask('ابعتلي بوست حلو اشد بيه الزباين ع الواتس');
      expect(r10.any((i) => i.id.startsWith('promo_post')), isTrue);

      // 11. Compound query: sales diagnosis + today profit
      final r11 = await service.ask('النهارده الدنيا نايمة ليه وبعت بكام؟');
      expect(r11.any((i) => i.id == 'sales_diagnosis'), isTrue);
      expect(r11.any((i) => i.id == 'today_profit'), isTrue);

      // 12. Contextual follow-up: "طيب وامبارح؟"
      final r12 = await service.ask('طيب وامبارح؟');
      expect(r12.any((i) => i.id == 'yesterday_followup'), isTrue);

      // 13. What-if pricing with spoken percentage
      final r13 = await service.ask('لو عملت خصم عشرين في المية هخسر ولا هكسب؟');
      expect(r13.any((i) => i.id.startsWith('what_if_')), isTrue);
      expect(r13.first.title, contains('20%'));

      // 14. Zakat with spoken thousands & Arabic digits
      final d14 = service.parseErpDraft('احسبلي الزكاة بتاعتي والدهب بـ ٤ تلاف');
      expect(d14?.kind, AssistantCommandKind.calculateZakat);
      expect(d14?.fields['goldPrice24'], 4000.0);

      // 15. Objection reply ("الزبون بيقولي لاقيته بره ارخص ارد عليه بايه")
      final r15 = await service.ask('الزبون بيقولي لاقيته بره ارخص ارد عليه بايه');
      expect(r15.any((i) => i.id == 'customer_objection_replies'), isTrue);
    });
  });

  group('Task 41.2: 200+ Natural Sentence Accuracy Benchmark', () {
    test('achieves >= 95% accuracy across 210 diverse colloquial merchant phrases', () {
      final ctx = AssistantContextMemory()
        ..lastProductName = 'تيشيرت قطن'
        ..lastSupplierName = 'الحاج محمود'
        ..lastIntent = AssistantNluIntent.todayProfit;

      final cases = <(String, AssistantNluIntent?)>[
        // --- Add Product (25) ---
        ('عايز اضيف صنف جديد', AssistantNluIntent.addProduct),
        ('محتاج انزل بضاعة جديدة ع السيستم', AssistantNluIntent.addProduct),
        ('ضيف صنف شورت جينز تكلفة 120 بيع 220 كمية 10', AssistantNluIntent.addProduct),
        ('ممكن لو سمحت تضيف منتج جديد', AssistantNluIntent.addProduct),
        ('نزل لي منتح قميص كتان بيشتري بـ ميتين وبيتباع بـ ٣٥٠ وعندي منه دستة', AssistantNluIntent.addProduct),
        ('حابب اضيف موديل جديد', AssistantNluIntent.addProduct),
        ('سجل لي صنف فستان صيفي تكلفة 250 بيع 450 كمية 6', AssistantNluIntent.addProduct),
        ('انزل بضاعة جديدة في المحل', AssistantNluIntent.addProduct),
        ('ضيف منتج سويتشيرت تكلفة 180 بيع 320 كمية 8', AssistantNluIntent.addProduct),
        ('ابغى اضيف صنف جديد', AssistantNluIntent.addProduct),
        ('لو سمحت ضف لي صنف حذاء رياضي', AssistantNluIntent.addProduct),
        ('عاوز انزل منتج كاب قطن تكلفة 50 بيع 100 كمية 20', AssistantNluIntent.addProduct),
        ('هضيف بضاعة جديدة دلوقتي', AssistantNluIntent.addProduct),
        ('ضيف لي موديل بلوزة شيفون تكلفة 140 بيع 260 كمية 5', AssistantNluIntent.addProduct),
        ('اريد اضافة صنف جديد', AssistantNluIntent.addProduct),
        ('ممكن تنزل صنف شنطة جلد تكلفة 300 بيع 500 كمية 4', AssistantNluIntent.addProduct),
        ('عايز اسجل منتج جديد', AssistantNluIntent.addProduct),
        ('ضيف صنف شراب قطن تكلفة 15 بيع 35 كمية 50', AssistantNluIntent.addProduct),
        ('نزل صنف حزام جلد طبيعي تكلفة 90 بيع 180 كمية 12', AssistantNluIntent.addProduct),
        ('يا ريت تضيف منتج بيجامة اطفال', AssistantNluIntent.addProduct),
        ('ضيف بضاعة جديدة جينز', AssistantNluIntent.addProduct),
        ('محتاج اضيف موديل عباية', AssistantNluIntent.addProduct),
        ('سجل منتج طرحة شيفون تكلفة 40 بيع 85 كمية 24', AssistantNluIntent.addProduct),
        ('عاوز اضيف صنف جاكيت جلد', AssistantNluIntent.addProduct),
        ('ضيف صنف كوتشي ابيض تكلفة 400 بيع 650 كمية 6', AssistantNluIntent.addProduct),

        // --- Record Purchase (25) ---
        ('جبت 10 بناطيل جينز من الحاج محمود الواحد بـ 300 شكك', AssistantNluIntent.recordPurchase),
        ('اشتريت تيشيرت من المورد علي بسعر 150 عدد 5', AssistantNluIntent.recordPurchase),
        ('عايز اشتري بضاعة', AssistantNluIntent.recordPurchase),
        ('وكمان واحد من نفس المورد بـ 250', AssistantNluIntent.recordPurchase),
        ('اشتريت 20 قطعة شراب من شركة النور بسعر 15 نقدي', AssistantNluIntent.recordPurchase),
        ('جبت دستة قمصان من المورد حسن الواحد بـ 200', AssistantNluIntent.recordPurchase),
        ('سجل مشتريات جاكيت شتوي من مصنع السلام بسعر 350 كمية 8 آجل', AssistantNluIntent.recordPurchase),
        ('انا اشتريت 12 عباية من الحاج سعيد بسعر 400 شكك', AssistantNluIntent.recordPurchase),
        ('بشتري بضاعة جديدة من المورد طارق', AssistantNluIntent.recordPurchase),
        ('جبت 5 فساتين من المورد كريم بسعر 300 كاش', AssistantNluIntent.recordPurchase),
        ('شراء جينز من المورد نبيل بسعر 220 عدد 15', AssistantNluIntent.recordPurchase),
        ('محتاج اسجل مشتريات من المورد احمد', AssistantNluIntent.recordPurchase),
        ('جبت 6 كوتشي من الحاج مصطفى الواحد بـ 450 نقدي', AssistantNluIntent.recordPurchase),
        ('اشتريت دستتين طرح من المورد هاني بسعر 35', AssistantNluIntent.recordPurchase),
        ('شريت 10 بيجامات من مصنع الامل بسعر 180 اجل', AssistantNluIntent.recordPurchase),
        ('جبت بضاعة من نفس المورد بـ 190', AssistantNluIntent.recordPurchase),
        ('اشتريت سويتشيرت من المورد عادل بسعر 170 عدد 10', AssistantNluIntent.recordPurchase),
        ('جبت 15 بنطلون جبردين من الحاج ابراهيم بسعر 240 شكك', AssistantNluIntent.recordPurchase),
        ('شراء كابات من المورد يحيى بسعر 45 كمية 30', AssistantNluIntent.recordPurchase),
        ('انا جبت 8 شنط من المورد سامي الواحد بـ 280', AssistantNluIntent.recordPurchase),
        ('اشتريت حزام جلد من المورد رضا بسعر 80 عدد 20', AssistantNluIntent.recordPurchase),
        ('جبت 4 ترنجات من الحاج فؤاد بسعر 320 نقدي', AssistantNluIntent.recordPurchase),
        ('اشتريت بضاعة اجل من المورد خالد', AssistantNluIntent.recordPurchase),
        ('سجل مشتريات فوط من مصنع المحلة بسعر 90 عدد 25', AssistantNluIntent.recordPurchase),
        ('جبت 10 بلوزات من المورد وليد بسعر 160 شكك', AssistantNluIntent.recordPurchase),

        // --- Record Expense (20) ---
        ('دفعت كهربا المحل 600 جنيه النهارده', AssistantNluIntent.recordExpense),
        ('طلع من الدرج الف ونص ايجار', AssistantNluIntent.recordExpense),
        ('عايز اسجل مصروف', AssistantNluIntent.recordExpense),
        ('عاوز اسجل مصروف كهرباء 300', AssistantNluIntent.recordExpense),
        ('صرفت 200 جنيه نظافة', AssistantNluIntent.recordExpense),
        ('دفعت فاتورة نت 400 جنيه', AssistantNluIntent.recordExpense),
        ('سجل مصروف مياه 150', AssistantNluIntent.recordExpense),
        ('مصروف جديد ضيافة 100', AssistantNluIntent.recordExpense),
        ('دفعت ايجار المحل 5 تلاف', AssistantNluIntent.recordExpense),
        ('طلع من الدرج 250 شحن', AssistantNluIntent.recordExpense),
        ('صرفت صيانة تكييف 800 جنيه', AssistantNluIntent.recordExpense),
        ('اسجل مصروف مرتبات 4000', AssistantNluIntent.recordExpense),
        ('دفعت غاز 120 النهارده', AssistantNluIntent.recordExpense),
        ('سجل مصروف اكياس وتغليف 350', AssistantNluIntent.recordExpense),
        ('محتاج اسجل مصروف دعاية 500', AssistantNluIntent.recordExpense),
        ('طلع من الدرج ميتين جنيه اكرامية', AssistantNluIntent.recordExpense),
        ('دفعت فاتورة تليفون 250', AssistantNluIntent.recordExpense),
        ('صرفت بنزين توصيل 180', AssistantNluIntent.recordExpense),
        ('سجل مصروف نقل بضاعة 300', AssistantNluIntent.recordExpense),
        ('دفعت تصليح اضاءة 450', AssistantNluIntent.recordExpense),

        // --- Pay Supplier (15) ---
        ('اديت للحاج محمود دفعة 3 آلاف', AssistantNluIntent.paySupplier),
        ('دفعت للمورد علي 2000', AssistantNluIntent.paySupplier),
        ('سداد مورد حسن 1500', AssistantNluIntent.paySupplier),
        ('سددت للمورد ابراهيم 5000', AssistantNluIntent.paySupplier),
        ('اديت للمورد طارق دفعة الفين', AssistantNluIntent.paySupplier),
        ('دفعت لمورد النور 1200', AssistantNluIntent.paySupplier),
        ('اديت للحاج سعيد 4000 جنيه', AssistantNluIntent.paySupplier),
        ('سداد مورد خالد الف ونص', AssistantNluIntent.paySupplier),
        ('دفعت للمورد نبيل دفعة 2500', AssistantNluIntent.paySupplier),
        ('سددت للحاج مصطفى 1000', AssistantNluIntent.paySupplier),
        ('عايز ادفع للمورد سامي 800', AssistantNluIntent.paySupplier),
        ('اديت لمورد السلام دفعة 6000', AssistantNluIntent.paySupplier),
        ('سداد مورد فؤاد 900', AssistantNluIntent.paySupplier),
        ('دفعت للحاج رضا 3500', AssistantNluIntent.paySupplier),
        ('سددت للمورد وليد 750', AssistantNluIntent.paySupplier),

        // --- Add Customer & Collect Installment (25) ---
        ('عايز اضيف عميل', AssistantNluIntent.addCustomer),
        ('ضيف عميل احمد محمد 01012345678', AssistantNluIntent.addCustomer),
        ('عميل جديد سارة علي 01122334455', AssistantNluIntent.addCustomer),
        ('ضيف زبون مصطفى حسن', AssistantNluIntent.addCustomer),
        ('ممكن تضيف عميل جديد', AssistantNluIntent.addCustomer),
        ('سجل عميل جديد كريم', AssistantNluIntent.addCustomer),
        ('زبون جديد هاني', AssistantNluIntent.addCustomer),
        ('ضيف عميل ندى محمود 01234567890', AssistantNluIntent.addCustomer),
        ('عاوز اضيف زبون', AssistantNluIntent.addCustomer),
        ('اضافة عميل ياسمين', AssistantNluIntent.addCustomer),
        ('محمود العميل جه دفع 500 من قسطه', AssistantNluIntent.collectInstallment),
        ('عايز احصل قسط', AssistantNluIntent.collectInstallment),
        ('العميل احمد دفع قسط 400', AssistantNluIntent.collectInstallment),
        ('تحصيل قسط سارة 300', AssistantNluIntent.collectInstallment),
        ('الزبون علي جه دفع 600 من قسطه', AssistantNluIntent.collectInstallment),
        ('سارة دفعت قسط 250', AssistantNluIntent.collectInstallment),
        ('تحصيل قسط من محمود 1000', AssistantNluIntent.collectInstallment),
        ('عاوز احصل قسط العميل طارق 350', AssistantNluIntent.collectInstallment),
        ('العميل كريم دفع قسط 700', AssistantNluIntent.collectInstallment),
        ('تحصيل قسط هاني 450', AssistantNluIntent.collectInstallment),
        ('محتاج احصل قسط', AssistantNluIntent.collectInstallment),
        ('مصطفى دفع 800 من قسطه', AssistantNluIntent.collectInstallment),
        ('العميل ندى دفع قسط 500', AssistantNluIntent.collectInstallment),
        ('تحصيل قسط ياسمين 200', AssistantNluIntent.collectInstallment),
        ('خالد العميل جه دفع قسط 1200', AssistantNluIntent.collectInstallment),

        // --- Update Price & Stock (25) ---
        ('هات نفس الصنف بس خلي السعر 400', AssistantNluIntent.updatePrice),
        ('لا خليه ٥٠٠', AssistantNluIntent.updatePrice),
        ('عايز اعدل سعر الجاكيت لـ 500', AssistantNluIntent.updatePrice),
        ('خلي سعر التيشيرت 250', AssistantNluIntent.updatePrice),
        ('غير سعر البنطلون 380', AssistantNluIntent.updatePrice),
        ('عدل لي سعر الكوتشي 700', AssistantNluIntent.updatePrice),
        ('ممكن تخلي سعر القميص 320', AssistantNluIntent.updatePrice),
        ('خليه 600', AssistantNluIntent.updatePrice),
        ('غير سعر الشنطة 450', AssistantNluIntent.updatePrice),
        ('عدل سعر العباية لـ 550', AssistantNluIntent.updatePrice),
        ('زودلي الجاكيت الاسود 5 حتت', AssistantNluIntent.updateStock),
        ('اتكسر مني حتتين في الجرد', AssistantNluIntent.updateStock),
        ('زود رصيد تيشيرت قطن 10', AssistantNluIntent.updateStock),
        ('نقص رصيد بنطلون جينز 3', AssistantNluIntent.updateStock),
        ('زود كمية الشراب 24 قطعة', AssistantNluIntent.updateStock),
        ('باظ مني 3 حتت في المخزن', AssistantNluIntent.updateStock),
        ('ضاع قطعتين في الجرد', AssistantNluIntent.updateStock),
        ('زود لي رصيد القميص 6 حتت', AssistantNluIntent.updateStock),
        ('نقص كمية الكاب 4 حتت', AssistantNluIntent.updateStock),
        ('تالف 5 حتت في الجرد', AssistantNluIntent.updateStock),
        ('زود رصيد الفستان 8 قطع', AssistantNluIntent.updateStock),
        ('اتكسر مني 4 حتت', AssistantNluIntent.updateStock),
        ('نقص رصيد الحزام 2 حتة', AssistantNluIntent.updateStock),
        ('زود لي كمية الشنط 7 حتت', AssistantNluIntent.updateStock),
        ('باظ حتتين من المخزون', AssistantNluIntent.updateStock),

        // --- Zakat, Analytical, Follow-up, Objections & How-To Exclusions (75) ---
        ('احسبلي الزكاة بتاعتي والدهب بـ ٤ تلاف', AssistantNluIntent.calculateZakat),
        ('احسب الزكاة الذهب بـ 4000', AssistantNluIntent.calculateZakat),
        ('زكاة المال والذهب 4200', AssistantNluIntent.calculateZakat),
        ('عايز احسب زكاة التجارة', AssistantNluIntent.calculateZakat),
        ('حاسبة الزكاة عيار 24 بـ 3900', AssistantNluIntent.calculateZakat),
        ('شوفلي مين متأخر في الفلوس', AssistantNluIntent.overdueInstallments),
        ('الاقساط المتاخره', AssistantNluIntent.overdueInstallments),
        ('مين عليه فلوس متأخرة', AssistantNluIntent.overdueInstallments),
        ('عايز اشوف المتاخرين في السداد', AssistantNluIntent.overdueInstallments),
        ('مين متاخر في الاقساط', AssistantNluIntent.overdueInstallments),
        ('ابعتلي بوست حلو اشد بيه الزباين ع الواتس', AssistantNluIntent.promoPost),
        ('اكتب بوست واتساب', AssistantNluIntent.promoPost),
        ('اعملي منشور فيسبوك يجذب الزباين', AssistantNluIntent.promoPost),
        ('اكتب بوست انستا للمحل', AssistantNluIntent.promoPost),
        ('عايز بوست اشد بيه الزباين', AssistantNluIntent.promoPost),
        ('النهارده الدنيا نايمة ليه وبعت بكام؟', AssistantNluIntent.salesDiagnosis),
        ('المبيعات قليلة ليه', AssistantNluIntent.salesDiagnosis),
        ('ليه البيع واقف النهارده', AssistantNluIntent.salesDiagnosis),
        ('مبيعاتي نازلة ليه اليومين دول', AssistantNluIntent.salesDiagnosis),
        ('الدنيا نايمة ليه في المحل', AssistantNluIntent.salesDiagnosis),
        ('بعت بكام النهارده', AssistantNluIntent.todayProfit),
        ('كسبت كام النهارده', AssistantNluIntent.todayProfit),
        ('ربح النهارده كام', AssistantNluIntent.todayProfit),
        ('مبيعات النهارده قد ايه', AssistantNluIntent.todayProfit),
        ('صافي ربح اليوم كام', AssistantNluIntent.todayProfit),
        ('طيب وامبارح؟', AssistantNluIntent.yesterdayFollowup),
        ('وامبارح؟', AssistantNluIntent.yesterdayFollowup),
        ('امبارح', AssistantNluIntent.yesterdayFollowup),
        ('طيب وامبارح', AssistantNluIntent.yesterdayFollowup),
        ('وامس', AssistantNluIntent.yesterdayFollowup),
        ('لو عملت خصم عشرين في المية هخسر ولا هكسب؟', AssistantNluIntent.whatIfPricing),
        ('لو عملت خصم 15% أحتاج أبيع كام؟', AssistantNluIntent.whatIfPricing),
        ('ماذا لو عملت خصم 10%', AssistantNluIntent.whatIfPricing),
        ('لو خصمت 25% هكسب ولا هخسر', AssistantNluIntent.whatIfPricing),
        ('خصم 30% يأثر ازاي على الربح', AssistantNluIntent.whatIfPricing),
        ('الزبون بيقولي لاقيته بره ارخص ارد عليه بايه', AssistantNluIntent.objectionReplies),
        ('العميل بيقول غالي', AssistantNluIntent.objectionReplies),
        ('الزبون لقيته بره ارخص من كده', AssistantNluIntent.objectionReplies),
        ('العميل بيقول السعر غالي ارد عليه بايه', AssistantNluIntent.objectionReplies),
        ('زبون بيقول غالي عليا', AssistantNluIntent.objectionReplies),
        // Educational How-To exclusions MUST return null from IntentScorer
        ('ازاي اضيف صنف', null),
        ('ازاي اضيف كاشير', null),
        ('كيف اعمل جرد للمخزون', null),
        ('طريقة اضافة عميل جديد', null),
        ('خطوات تقفيل الوردية', null),
        ('ازاي ارجع فاتورة', null),
        ('كيف اسجل مصروف', null),
        ('طريقة طباعة الباركود', null),
        ('ازاي اعمل خصم في الكاشير', null),
        ('خطوات النسخ الاحتياطي', null),

        // --- Extra 25 Diverse Colloquial Sentences (Total 210) ---
        ('ضيف صنف بلوفر صوف تكلفة 220 بيع 380 كمية 10', AssistantNluIntent.addProduct),
        ('نزل منتج جديد جلابية رجالي', AssistantNluIntent.addProduct),
        ('عاوز اضيف بضاعة جديدة تيشيرتات', AssistantNluIntent.addProduct),
        ('جبت 12 جاكيت من المورد سامح بسعر 310 كاش', AssistantNluIntent.recordPurchase),
        ('اشتريت 6 شنط من الحاج جمال الواحد بـ 250 شكك', AssistantNluIntent.recordPurchase),
        ('محتاج اشتري بضاعة من المورد نبيل', AssistantNluIntent.recordPurchase),
        ('دفعت ايجار المخزن 2000 جنيه', AssistantNluIntent.recordExpense),
        ('صرفت 150 نظافة المحل', AssistantNluIntent.recordExpense),
        ('طلع من الدرج 500 صيانة', AssistantNluIntent.recordExpense),
        ('اديت للمورد جمال دفعة 2000', AssistantNluIntent.paySupplier),
        ('سددت للحاج علي 3500', AssistantNluIntent.paySupplier),
        ('ضيف عميل حسام الدين 01099887766', AssistantNluIntent.addCustomer),
        ('عميل جديد ياسر احمد', AssistantNluIntent.addCustomer),
        ('العميل حسام دفع قسط 400', AssistantNluIntent.collectInstallment),
        ('تحصيل قسط ياسر 350', AssistantNluIntent.collectInstallment),
        ('عدل سعر البلوفر لـ 420', AssistantNluIntent.updatePrice),
        ('خلي سعر الطرحة 95', AssistantNluIntent.updatePrice),
        ('زودلي البلوفر 4 حتت', AssistantNluIntent.updateStock),
        ('اتكسر مني 3 حتت في الجرد', AssistantNluIntent.updateStock),
        ('احسبلي الزكاة والدهب بـ 4100', AssistantNluIntent.calculateZakat),
        ('شوفلي مين متاخر في الفلوس', AssistantNluIntent.overdueInstallments),
        ('ابعتلي بوست حلو للفيسبوك', AssistantNluIntent.promoPost),
        ('النهارده الدنيا نايمة ليه', AssistantNluIntent.salesDiagnosis),
        ('بعت بكام النهارده يا مساعد', AssistantNluIntent.todayProfit),
        ('لو عملت خصم 12% هكسب ولا هخسر', AssistantNluIntent.whatIfPricing),
      ];

      expect(cases.length, greaterThanOrEqualTo(200));

      int passed = 0;
      final failures = <String>[];
      for (final (phrase, expected) in cases) {
        final actual = AssistantIntentScorer.score(phrase, context: ctx)?.intent;
        if (actual == expected) {
          passed++;
        } else {
          failures.add('"$phrase": expected $expected, got $actual');
        }
      }

      final accuracy = (passed / cases.length) * 100.0;
      // Print accuracy for visibility in test output
      // ignore: avoid_print
      print('NLU Benchmark: $passed / ${cases.length} (${accuracy.toStringAsFixed(1)}%)');
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(accuracy, greaterThanOrEqualTo(95.0));
    });
  });

  group('Task 41.3: Levenshtein Typo Tolerance & Commerce Encyclopedia Topics', () {
    test('corrects 1-char typos via Levenshtein distance in NLU', () {
      expect(
        AssistantArabicNormalizer.levenshteinDistance('مننج', 'منتج'),
        1,
      );
      final d1 = service.parseErpDraft('عايز اضيف مننج جديد');
      expect(d1?.kind, AssistantCommandKind.addProduct);

      final d2 = service.parseErpDraft('سجل مصرزف كهرباء 250');
      expect(d2?.kind, AssistantCommandKind.recordExpense);
      expect(d2?.fields['amountEgp'], 250.0);

      final d3 = service.parseErpDraft('احسبلي الذكاة والذهب 4000');
      expect(d3?.kind, AssistantCommandKind.calculateZakat);
      expect(d3?.fields['goldPrice24'], 4000.0);
    });

    test('answers topics from Book of Commerce & 6-Book Encyclopedia with sector awareness', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final tMargin = await service.searchKnowledgeBase(
        'الفرق بين الهامش Margin ونسبة الاضافة Markup',
      );
      expect(tMargin, isNotEmpty);
      expect(tMargin.first.id, 'kb_book_margin_vs_markup');

      final tLast = await service.searchKnowledgeBase(
        'بروتوكول احتواء العميل الغاضب LAST',
      );
      expect(tLast, isNotEmpty);
      expect(tLast.first.id, 'kb_enc2_last_angry_customer');

      final tAbc = await service.searchKnowledgeBase('تصنيف ABC للمخزون');
      expect(tAbc, isNotEmpty);
      expect(tAbc.first.id, 'kb_book_abc_inventory_rescue');

      final tSop = await service.searchKnowledgeBase(
        'بناء دليل التشغيل SOP ونظام الفريق E-Myth',
      );
      expect(tSop, isNotEmpty);
      expect(tSop.first.id, 'kb_enc5_emyth_sop_and_hiring');

      final tFnb = await service.searchKnowledgeBase(
        'اضبط Food Cost والهالك في المطعم ازاي',
        activeSector: 'fnb',
      );
      expect(tFnb, isNotEmpty);
      expect(tFnb.first.id, 'kb_enc6_fnb_food_cost_menu_waste');
    });
  });
}
