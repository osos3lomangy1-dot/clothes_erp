import 'dart:convert';
import 'dart:io';

import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_engine.dart';

void main() async {
  final file = File('tool/assistant_egyptian_corpus.jsonl');
  if (!file.existsSync()) {
    print('File not found: ${file.path}');
    return;
  }

  final lines = await file.readAsLines();
  print('Loaded ${lines.length} lines from ${file.path}');

  final context = AssistantContextMemory();

  int totalCommands = 0;
  // ignore: unused_local_variable
  int correctCommands = 0;

  final missedByIntent = <String, int>{};
  final totalByIntent = <String, int>{};
  final sampleMisses = <String, List<String>>{};

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    final text = row['text'] as String;
    final intent = row['intent'] as String;

    totalByIntent[intent] = (totalByIntent[intent] ?? 0) + 1;

    // Test IntentScorer
    final res = AssistantIntentScorer.score(text, context: context);
    final scoredIntentName = res?.intent.name;

    if (totalCommands > 0 && totalCommands % 1000 == 0) {
      print('Processed $totalCommands / ${lines.length}...');
    }

    // Check match based on intent mapping
    bool isMatch = false;
    if (intent == 'addProduct' && scoredIntentName == 'addProduct')
      isMatch = true;
    if (intent == 'recordPurchase' && scoredIntentName == 'recordPurchase')
      isMatch = true;
    if (intent == 'recordExpense' && scoredIntentName == 'recordExpense')
      isMatch = true;
    if (intent == 'paySupplier' && scoredIntentName == 'paySupplier')
      isMatch = true;
    if (intent == 'addCustomer' && scoredIntentName == 'addCustomer')
      isMatch = true;
    if (intent == 'collectInstallment' &&
        scoredIntentName == 'collectInstallment')
      isMatch = true;
    if (intent == 'updateProductPriceOrStock' &&
        (scoredIntentName == 'updatePrice' ||
            scoredIntentName == 'updateStock'))
      isMatch = true;
    if (intent == 'calculateZakat' && scoredIntentName == 'calculateZakat')
      isMatch = true;
    if (intent == 'getTodayProfitInsight' && scoredIntentName == 'todayProfit')
      isMatch = true;
    if (intent == 'getSalesDiagnosisInsight' &&
        scoredIntentName == 'salesDiagnosis')
      isMatch = true;
    if (intent == 'getLateInstallmentsInsight' &&
        scoredIntentName == 'overdueInstallments')
      isMatch = true;
    if (intent == 'getWhatIfPricingInsight' &&
        scoredIntentName == 'whatIfPricing')
      isMatch = true;
    if (intent == 'getCustomerObjectionRepliesInsight' &&
        scoredIntentName == 'objectionReplies')
      isMatch = true;
    if (intent == 'getStorePulseInsight' && scoredIntentName == 'storePulse')
      isMatch = true;
    if (intent == 'getStoreHealthScoreInsight' &&
        scoredIntentName == 'storeHealthScore')
      isMatch = true;
    if (intent == 'getGoalPlannerInsight' && scoredIntentName == 'goalPlanner')
      isMatch = true;
    if (intent == 'getEndOfDayReportInsight' &&
        scoredIntentName == 'endOfDayReport')
      isMatch = true;
    if (intent == 'getTopProfitProductsInsight' &&
        scoredIntentName == 'topProfitProducts')
      isMatch = true;
    if (intent == 'getStagnantProductsInsight' &&
        scoredIntentName == 'stagnantStock')
      isMatch = true;
    if (intent == 'getSmartReorderListInsight' &&
        scoredIntentName == 'smartReorderList')
      isMatch = true;
    if (intent == 'getTopVariantsByProductInsight' &&
        scoredIntentName == 'topVariants')
      isMatch = true;
    if (intent == 'getCheapestSupplierForProductInsight' &&
        scoredIntentName == 'cheapestSupplier')
      isMatch = true;
    if (intent == 'searchByBarcodeOrSkuInsight' &&
        scoredIntentName == 'searchByBarcodeOrSku')
      isMatch = true;
    if (intent == 'getMarginLeakInsight' && scoredIntentName == 'marginLeak')
      isMatch = true;
    if (intent == 'getBreakEvenInsight' && scoredIntentName == 'breakEven')
      isMatch = true;
    if (intent == 'getCashierPerformanceInsight' &&
        scoredIntentName == 'cashierPerformance')
      isMatch = true;
    if (intent == 'getTodayAuditsAndCancellationsInsight' &&
        scoredIntentName == 'todayAudits')
      isMatch = true;
    if (intent == 'getMarketingPostInsight' && scoredIntentName == 'promoPost')
      isMatch = true;
    if (intent == 'getSupplierDuesInsight' &&
        scoredIntentName == 'suppliersDues')
      isMatch = true;
    if (intent == 'getBudgetComparisonInsight' &&
        scoredIntentName == 'budgetComparison')
      isMatch = true;
    if (intent == 'getWinBackCustomersInsight' &&
        scoredIntentName == 'winBackCustomers')
      isMatch = true;
    if (intent == 'getInstallmentReminderMessageInsight' &&
        scoredIntentName == 'installmentReminderMessage')
      isMatch = true;
    if (intent == 'getSeasonPlanInsight' && scoredIntentName == 'seasonPlan')
      isMatch = true;
    if (intent == 'getInflationCalculatorInsight' &&
        scoredIntentName == 'inflationCalculator')
      isMatch = true;
    if (intent == 'getLiquidityStrategyInsight' &&
        scoredIntentName == 'liquidityStrategy')
      isMatch = true;
    if (intent == 'getVisualMerchandisingInsight' &&
        scoredIntentName == 'visualMerchandising')
      isMatch = true;
    if (intent == 'toggleBlindShiftClosing' &&
        scoredIntentName == 'toggleBlindShiftClosing')
      isMatch = true;
    if (intent == 'toggleManagerPinProtection' &&
        scoredIntentName == 'toggleManagerPinProtection')
      isMatch = true;
    if (intent == 'toggleAllowManualDiscount' &&
        scoredIntentName == 'toggleAllowManualDiscount')
      isMatch = true;
    if (intent == 'toggleAutoBackup' && scoredIntentName == 'toggleAutoBackup')
      isMatch = true;
    if (intent == 'updateStoreName' && scoredIntentName == 'updateStoreName')
      isMatch = true;
    if (intent == 'updateStorePhone' && scoredIntentName == 'updateStorePhone')
      isMatch = true;
    if (intent == 'backupNow' && scoredIntentName == 'backupNow')
      isMatch = true;
    if (intent == 'shiftSummary' && scoredIntentName == 'shiftSummary')
      isMatch = true;
    if (intent == 'preOrderQuery' && scoredIntentName == 'preOrderQuery')
      isMatch = true;
    if (intent == 'preOrderCreate' && scoredIntentName == 'preOrderCreate')
      isMatch = true;
    if (intent == 'deliveryQuery' && scoredIntentName == 'deliveryQuery')
      isMatch = true;
    if (intent == 'repairQuery' && scoredIntentName == 'repairQuery')
      isMatch = true;
    if (intent == 'walletQuery' && scoredIntentName == 'walletQuery')
      isMatch = true;
    if (intent == 'walletTransfer' && scoredIntentName == 'walletTransfer')
      isMatch = true;
    if (intent == 'partnerShares' && scoredIntentName == 'partnerShares')
      isMatch = true;
    if (intent == 'partnerWithdraw' && scoredIntentName == 'partnerWithdraw')
      isMatch = true;
    if (intent == 'howToGuide' && scoredIntentName == 'howToGuide')
      isMatch = true;
    if (intent == 'cancel' && scoredIntentName == 'cancel') isMatch = true;
    if (intent == 'confirm' && scoredIntentName == 'confirm') isMatch = true;
    if (intent == 'chitchat' && scoredIntentName == 'chitchat') isMatch = true;
    if (intent == 'out_of_scope' && scoredIntentName == 'outOfScope')
      isMatch = true;
    if (intent == 'reject_or_fix' && scoredIntentName == 'rejectOrFix')
      isMatch = true;
    if (intent == 'undoLast' && scoredIntentName == 'undoLast') isMatch = true;
    if (intent == 'help' && scoredIntentName == 'help') isMatch = true;

    if (isMatch) {
      correctCommands++;
    } else {
      missedByIntent[intent] = (missedByIntent[intent] ?? 0) + 1;
      sampleMisses
          .putIfAbsent(intent, () => [])
          .add('$text (got: $scoredIntentName)');
    }
    totalCommands++;
  }

  print(
    '\n=== Full Corpus Benchmark Results (Actions + Analytics + Settings + Modules) ===',
  );
  int totalTested = 0;
  int totalCorrect = 0;

  final sortedByTotal = totalByIntent.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sortedByTotal) {
    final intentName = entry.key;
    if (intentName.startsWith('slot_') || intentName.startsWith('fu_'))
      continue;

    final tot = entry.value;
    final miss = missedByIntent[intentName] ?? 0;
    final cor = tot - miss;
    totalTested += tot;
    totalCorrect += cor;
    final acc = ((cor / tot) * 100).toStringAsFixed(1);
    print('${intentName.padRight(40)}: $cor / $tot ($acc%)');
    if (sampleMisses[intentName] != null &&
        sampleMisses[intentName]!.isNotEmpty &&
        (tot - cor) > 0) {
      print('    eg: ${sampleMisses[intentName]!.first}');
    }
  }

  print(
    '\nOVERALL FULL CORPUS ACCURACY: $totalCorrect / $totalTested (${(totalCorrect / totalTested * 100).toStringAsFixed(2)}%)',
  );
}
