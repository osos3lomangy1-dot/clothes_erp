import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/services/local_backup_service.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/services/cashier_permissions_service.dart';
import '../../../invoices/data/services/receipt_settings_service.dart';
import 'assistant_nlu_engine.dart';

part 'assistant_draft_engine_part.dart';
part 'assistant_knowledge_matcher_part.dart';
part 'assistant_analytics_advisor_part.dart';
part 'assistant_marketing_advisor_part.dart';

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
  calculateZakat,
  runBackupNow,
}

class AssistantUndoToken {
  final AssistantCommandKind kind;
  final String recordId;
  final String label;

  const AssistantUndoToken({
    required this.kind,
    required this.recordId,
    required this.label,
  });
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
      if (nextDraft.fields.isNotEmpty) {
        final intent = switch (nextDraft.kind) {
          AssistantCommandKind.addProduct => AssistantNluIntent.addProduct,
          AssistantCommandKind.recordPurchase =>
            AssistantNluIntent.recordPurchase,
          AssistantCommandKind.recordExpense =>
            AssistantNluIntent.recordExpense,
          AssistantCommandKind.paySupplier => AssistantNluIntent.paySupplier,
          AssistantCommandKind.addCustomer => AssistantNluIntent.addCustomer,
          AssistantCommandKind.collectInstallment =>
            AssistantNluIntent.collectInstallment,
          AssistantCommandKind.calculateZakat =>
            AssistantNluIntent.calculateZakat,
          AssistantCommandKind.updateProductPriceOrStock =>
            nextDraft.fields['mode'] == 'stock'
                ? AssistantNluIntent.updateStock
                : AssistantNluIntent.updatePrice,
          _ => AssistantNluIntent.addProduct,
        };
        contextMemory.updateFromDraft(intent: intent, fields: nextDraft.fields);
      }
      if (!nextDraft.isComplete) {
        return AssistantTurnResult(
          insights: [_buildDraftPromptInsight(nextDraft)],
          activeDraft: nextDraft,
        );
      }
      if (nextDraft.kind == AssistantCommandKind.calculateZakat) {
        final zakatInsight = await getZakatCalculatorInsight(
          goldGramPrice24Egp:
              (nextDraft.fields['goldPrice24'] as num).toDouble(),
          extraBankCashPiasters:
              (((nextDraft.fields['extraBankCashEgp'] as num?) ?? 0) * 100)
                  .round(),
          extraDebtsOnBusinessPiasters:
              (((nextDraft.fields['extraDebtsEgp'] as num?) ?? 0) * 100)
                  .round(),
          isGregorianYear: nextDraft.fields['isGregorianYear'] == true,
        );
        return AssistantTurnResult(insights: [zakatInsight], activeDraft: null);
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
      if (erpDraft.kind == AssistantCommandKind.calculateZakat) {
        final zakatInsight = await getZakatCalculatorInsight(
          goldGramPrice24Egp:
              (erpDraft.fields['goldPrice24'] as num).toDouble(),
          isGregorianYear: erpDraft.fields['isGregorianYear'] == true,
        );
        return AssistantTurnResult(insights: [zakatInsight], activeDraft: null);
      }
      return AssistantTurnResult(
        insights: [_buildPendingCommandInsight(erpDraft)],
        activeDraft: null,
      );
    }

    final insights = await ask(query);
    return AssistantTurnResult(insights: insights, activeDraft: null);
  }

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
      if (erpDraft.isComplete &&
          erpDraft.kind == AssistantCommandKind.calculateZakat) {
        return [
          await getZakatCalculatorInsight(
            goldGramPrice24Egp:
                (erpDraft.fields['goldPrice24'] as num).toDouble(),
            isGregorianYear: erpDraft.fields['isGregorianYear'] == true,
          ),
        ];
      }
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

    // 2b. NLU IntentScorer for natural colloquial analytical & follow-up queries
    final nluMatch = AssistantIntentScorer.score(query, context: contextMemory);
    if (nluMatch != null) {
      final intentsToRun = <AssistantNluIntent>[
        nluMatch.intent,
        ...nluMatch.secondaryIntents,
      ];
      for (final intent in intentsToRun) {
        switch (intent) {
          case AssistantNluIntent.overdueInstallments:
            contextMemory.updateAnalyticalIntent(intent);
            results.add(await getOverdueInstallmentsInsight());
            break;
          case AssistantNluIntent.promoPost:
            contextMemory.updateAnalyticalIntent(intent);
            results.add(
              await getPromoPostGeneratorInsight(
                AssistantArabicNormalizer.replaceSpokenNumbers(query),
              ),
            );
            break;
          case AssistantNluIntent.salesDiagnosis:
            contextMemory.updateAnalyticalIntent(intent);
            results.add(await getSalesDiagnosisInsight());
            break;
          case AssistantNluIntent.todayProfit:
            contextMemory.updateAnalyticalIntent(intent);
            results.add(await getTodayProfitInsight());
            break;
          case AssistantNluIntent.yesterdayFollowup:
            results.add(await _buildYesterdayFollowupInsight());
            break;
          case AssistantNluIntent.whatIfPricing:
            contextMemory.updateAnalyticalIntent(intent);
            results.add(
              await getWhatIfPricingInsight(
                AssistantArabicNormalizer.replaceSpokenNumbers(query),
              ),
            );
            break;
          case AssistantNluIntent.objectionReplies:
            contextMemory.updateAnalyticalIntent(intent);
            results.add(await getCustomerObjectionRepliesInsight(query));
            break;
          default:
            break;
        }
      }
      if (results.isNotEmpty) {
        return results;
      }
    }

    // 2c. Additional ERP Modules (FeatureGate-aware): Shifts, PreOrders, Delivery, Repair, Wallets, Partners
    if (q.contains('الدرج المفتوح') ||
        q.contains('الورديه المفتوحه') ||
        q.contains('ملخص الدرج') ||
        q.contains('الدرج فيه كام')) {
      results.add(await getOpenShiftSummaryInsight());
    }
    if (q.contains('حجوزات') || q.contains('طلبات الحجز') || q.contains('الحجز المسبق')) {
      results.add(await getPreOrdersSummaryInsight());
    }
    if (q.contains('عهده الطيارين') ||
        q.contains('حساب الطيارين') ||
        q.contains('طلبات الديليفري') ||
        q.contains('الديليفري المعلق')) {
      results.add(await getDeliveryPendingSummaryInsight());
    }
    if (q.contains('تذاكر الصيانه') ||
        q.contains('الصيانه الجاهزه') ||
        q.contains('اجهزه الصيانه')) {
      results.add(await getRepairReadyInsight());
    }
    if (q.contains('رصيد المحافظ') ||
        q.contains('المحافظ الالكترونيه') ||
        q.contains('فودافون كاش')) {
      results.add(await getWalletsBalanceInsight());
    }
    if (q.contains('حصص الشركاء') ||
        q.contains('ارباح الشركاء') ||
        q.contains('توزيع الارباح على الشركاء')) {
      results.add(await getPartnersProfitSharesInsight());
    }

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
    if (q.contains('بزنس مان') ||
        q.contains('انصحني') ||
        q.contains('اعمل ايه في محلي') ||
        q.contains('استشاره') ||
        q.contains('رايك كتاجر')) {
      results.add(await getBusinessmanConsultationInsight());
    }
    if (q.contains('عايز اكسب') ||
        q.contains('هدف الربح') ||
        q.contains('هدف ربح') ||
        q.contains('حقق ربح') ||
        q.contains('تارجت ربح')) {
      results.add(await getGoalPlannerInsight(query));
    }
    if (q.contains('صحه المحل') ||
        q.contains('تقييم المحل') ||
        q.contains('مؤشر صحه') ||
        q.contains('كام من 100')) {
      results.add(await getStoreHealthScoreInsight());
    }
    if (q.contains('طلبيه الشراء') ||
        q.contains('اطلب بضاعه') ||
        q.contains('طلبيه شراء') ||
        q.contains('جهز طلبيه') ||
        q.contains('نواقص للطلب')) {
      results.add(await getSmartReorderListInsight());
    }
    if (q.contains('بيقول غالي') ||
        q.contains('غالي عليا') ||
        q.contains('تاخير ديليفري') ||
        q.contains('استرجاع بعد المده') ||
        q.contains('رد علي العميل') ||
        q.contains('اعتراض العميل')) {
      results.add(await getCustomerObjectionRepliesInsight(query));
    }
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
      final kbMatches = await searchKnowledgeBase(query);
      if (kbMatches.isNotEmpty) {
        return kbMatches;
      }

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

  // ─────────────────────────────────────────────────────────────────────────
  // OFFLINE KNOWLEDGE DISTILLATION & FUZZY SYNONYM SCORING ENGINE
  // ─────────────────────────────────────────────────────────────────────────

  static final OfflineKnowledgeMatcher _knowledgeMatcher =
      OfflineKnowledgeMatcher();

  Future<int> getKnowledgeTopicCount() => _knowledgeMatcher.topicCount();

  Future<List<AssistantInsight>> searchKnowledgeBase(
    String rawQuery, {
    int maxResults = 2,
    String? activeSector,
  }) async {
    final sector = activeSector ?? await detectStoreSector();
    return _knowledgeMatcher.match(
      rawQuery,
      maxResults: maxResults,
      activeSector: sector,
    );
  }
}
