import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_classifier.dart';
import 'package:clothes_erp/features/dashboard/data/services/assistant_nlu_engine.dart';
import 'package:clothes_erp/features/dashboard/data/services/offline_smart_assistant_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late OfflineSmartAssistantService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = OfflineSmartAssistantService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 42.1: Egyptian Numbers v2 & Voice Elongation Normalization', () {
    test('parses compound thousands, fractions, and voice elongations accurately', () {
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('تمانية وخمسين الف ونص'),
        '58500',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('الف ومييتين'),
        '1200',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('واحد وسبعين الف ونص'),
        '71500',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('سبعة واربعين الف ونص'),
        '47500',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('اتنين وتلاتين الف ونص'),
        '32500',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('نص الف'),
        '500',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('ربع الف'),
        '250',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('احداشر'),
        '11',
      );
      expect(
        AssistantArabicNormalizer.replaceSpokenNumbers('تلات تلاف وميتين وخمسين'),
        '3250',
      );
      expect(
        AssistantArabicNormalizer.normalizeMerchantColloquial('الززززبون واقف'),
        'الزبون واقف',
      );
    });
  });

  group('Task 42.2: Egyptian Corpus v2 Sentences & Slot Extraction', () {
    test('extracts intents and slots from noisy corpus v2 merchant sentences', () {
      // Price update with politeness prefix/suffix & Arabic-Indic digits
      final d1 = service.parseErpDraft('اتمنى سعر جينز واسع خليه ٣٣٠٠ دلوقتي');
      expect(d1?.kind, AssistantCommandKind.updateProductPriceOrStock);
      expect(d1?.fields['mode'], 'price');
      expect(d1?.fields['value'], 3300.0);

      // Expense with compound spoken thousands & politeness
      final d2 = service.parseErpDraft(
        'اول حاجة طلعت على نجار تمانية وخمسين الف ونص جنيه من فضلك',
      );
      expect(d2?.kind, AssistantCommandKind.recordExpense);
      expect(d2?.fields['amountEgp'], 58500.0);
      expect(d2?.fields['category'], contains('نجار'));

      // Purchase with "نفسي جيبت" + "الف ومييتين" + "يا كبير"
      final d3 = service.parseErpDraft(
        'نفسي جيبت خمسين بنطلون قماش من ابو عمر بـ الف ومييتين القطعة كاش يا كبير',
      );
      expect(d3?.kind, AssistantCommandKind.recordPurchase);
      expect(d3?.fields['qty'], 50);
      expect(d3?.fields['costEgp'], 1200.0);
      expect(d3?.fields['supplierName'], contains('ابو عمر'));
      expect(d3?.fields['paymentType'], 'cash');
    });
  });

  group('Task 42.3: Multi-Turn Dialogues v2 (Prepositions, Compound Slots & Mid-Draft HowTo)', () {
    test('handles d00001 expense dialogue with preposition slot reply', () async {
      final t1 = await service.askWithDraft('دفعت بـ 72500');
      expect(t1.activeDraft?.kind, AssistantCommandKind.recordExpense);
      expect(t1.activeDraft?.missingField, 'category');

      final t2 = await service.askWithDraft(
        'على اشتراك برنامج',
        activeDraft: t1.activeDraft,
      );
      expect(t2.activeDraft, isNull);
      expect(t2.insights.first.pendingCommand?.payload['category'], 'اشتراك برنامج');
      expect(t2.insights.first.pendingCommand?.payload['amountEgp'], 72500.0);
    });

    test('handles d00004 purchase dialogue with compound qty+cost and mid-draft HowTo interruption', () async {
      final t1 = await service.askWithDraft('نزلت من عند ابو عمر');
      expect(t1.activeDraft?.kind, AssistantCommandKind.recordPurchase);
      expect(t1.activeDraft?.fields['supplierName'], 'ابو عمر');

      final t2 = await service.askWithDraft('سامسونج A54', activeDraft: t1.activeDraft);
      expect(t2.activeDraft?.missingField, 'qty');

      // Compound qty + unit_cost in one reply ("اتناشر بـ 3550")
      final t3 = await service.askWithDraft('اتناشر بـ 3550', activeDraft: t2.activeDraft);
      expect(t3.activeDraft, isNull);
      expect(t3.insights.first.pendingCommand?.payload['qty'], 12);
      expect(t3.insights.first.pendingCommand?.payload['costEgp'], 3550.0);

      // Mid-draft HowTo interruption keeps activeDraft alive
      final t4 = await service.askWithDraft(
        'ازاي اضيف صنف',
        activeDraft: t2.activeDraft,
      );
      expect(t4.activeDraft, isNotNull);
      expect(t4.insights.first.id, startsWith('howto_'));
    });

    test('handles d00007 supplier payment dialogue with mid-draft HowTo & spoken 47,500', () async {
      final t1 = await service.askWithDraft('دفعت لتاجر');
      expect(t1.activeDraft?.kind, AssistantCommandKind.paySupplier);

      final tMid = await service.askWithDraft(
        'كيف اسدد مورد',
        activeDraft: t1.activeDraft,
      );
      expect(tMid.activeDraft, isNotNull);

      final t2 = await service.askWithDraft('الحاج رمضان', activeDraft: tMid.activeDraft);
      expect(t2.activeDraft?.missingField, 'amountEgp');

      final t3 = await service.askWithDraft(
        'سبعة واربعين الف ونص',
        activeDraft: t2.activeDraft,
      );
      expect(t3.activeDraft, isNull);
      expect(t3.insights.first.pendingCommand?.payload['supplierName'], 'الحاج رمضان');
      expect(t3.insights.first.pendingCommand?.payload['amountEgp'], 47500.0);
    });
  });

  group('Task 42.4: Chitchat Lexicon & User Name Memory', () {
    test('handles social chitchat, offlineInfo, capabilities, and business guard', () async {
      final salam = await service.ask('السلام عليكم يا باشا');
      expect(salam.first.id, 'chitchat_greetingSalam');

      final morning = await service.ask('صباح الخير');
      expect(morning.first.id, 'chitchat_greetingMorning');

      final howAreYou = await service.ask('اي الاخبار عامل اي');
      expect(howAreYou.first.id, 'chitchat_howAreYou');

      final howAreYou2 = await service.ask('الدنيا عامله ايه النهارده يا باشا');
      expect(howAreYou2.first.id, 'chitchat_howAreYou');

      final offline = await service.ask('انت شغال بالنت ولا اوفلاين');
      expect(offline.first.id, 'chitchat_offlineInfo');

      final caps = await service.ask('بتعرف تعمل ايه يا مساعد');
      expect(caps.first.id, 'chitchat_capabilities');
      expect(caps.first.details.length, greaterThanOrEqualTo(6));

      final capsBare = await service.ask('بتعرف تعمل اي');
      expect(capsBare.first.id, 'chitchat_capabilities');

      final capsStore = await service.ask('بتعرف تعمل اي في المحل');
      expect(capsStore.first.id, 'chitchat_capabilities');

      final role = await service.ask('انت دورك اي');
      expect(role.first.id, 'chitchat_identity');
      expect(role.first.details.length, greaterThanOrEqualTo(6));

      final thanks = await service.ask('تسلم ايدك يا معلم');
      expect(thanks.first.id, 'chitchat_thanks');

      // Business guard: must NOT treat store query as chitchat
      final biz = await service.ask('المحل عامل ايه');
      expect(biz.first.id, isNot(startsWith('chitchat_')));
    });

    test('remembers, recalls, changes, and forgets user name', () async {
      final setRes = await service.ask('اسمي احمد');
      expect(setRes.first.id, 'chitchat_setName');
      expect(setRes.first.title, contains('احمد'));

      final askRes = await service.ask('اسمي ايه');
      expect(askRes.first.id, 'chitchat_askMyName');
      expect(askRes.first.title, contains('احمد'));

      final chgRes = await service.ask('غير اسمي كريم');
      expect(chgRes.first.id, 'chitchat_changeName');
      expect(chgRes.first.title, contains('كريم'));

      // Persists across a fresh service instance via AppMeta
      final freshService = OfflineSmartAssistantService(db);
      final persistedAsk = await freshService.ask('اسمي ايه');
      expect(persistedAsk.first.id, 'chitchat_askMyName');
      expect(persistedAsk.first.title, contains('كريم'));

      final fgtRes = await freshService.ask('امسح اسمي');
      expect(fgtRes.first.id, 'chitchat_forgetName');
      expect(freshService.contextMemory.userName, isNull);
    });

    test('handles undoLast, fuDetails, fuTone, and fuCopy follow-up intents', () async {
      final undoNone = await service.ask('اتراجع عن اخر عمليه');
      expect(undoNone.first.id, 'undo_none');

      await service.ask('كسبت كام النهارده');
      final details = await service.ask('تفاصيل اكتر');
      expect(details.first.id, startsWith('followup_details_'));

      final tone = await service.ask('خلي الرد رسمي');
      expect(tone.first.id, startsWith('followup_tone_'));
      expect(tone.first.summary, contains('تحية طيبة'));

      final copy = await service.ask('انسخ الرد');
      expect(copy.first.id, startsWith('followup_copy_'));
      expect(copy.first.details, isNotEmpty);
    });
  });

  group('Task 42.5: Trained On-Device NLU Classifier (75k Corpus v2)', () {
    test('loads assistant_nlu_model.json and classifies colloquial queries', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final classifier = OfflineNluClassifier();
      await classifier.ensureLoaded();
      expect(classifier.isLoaded, isTrue);
      expect(classifier.labelCount, greaterThanOrEqualTo(60));

      final p1 = await classifier.classify('ربح اليوم كام');
      expect(p1?.intent, AssistantNluIntent.todayProfit);

      final p2 = await classifier.classify('ايه البضاعة الراكدة اللي مش بتتباع');
      expect(p2?.intent, AssistantNluIntent.stagnantStock);

      final p3 = await classifier.classify('عايز اعمل جرد واضبط رصيد المخزن');
      expect(p3, isNotNull);

      final unknown = await classifier.classify('اختبار عشوائي غير معروف', minConfidence: 0.65);
      expect(unknown, isNull);
    });
  });

  group('Task 42.6: Self-Learning Logger & Extra Module Commands', () {
    test('records unmatched queries and exports JSONL', () async {
      await service.ask('اختبار عشوائي غير معروف');
      final list = await service.getUnmatchedQueries();
      expect(list, contains('اختبار عشوائي غير معروف'));

      final jsonl = await service.exportUnmatchedQueriesJsonl();
      expect(jsonl, contains('"intent":"TODO"'));
      expect(jsonl, contains('اختبار عشوائي غير معروف'));

      await service.clearUnmatchedQueries();
      expect(await service.getUnmatchedQueries(), isEmpty);
    });

    test('parses and executes walletTransfer and partnerWithdraw commands', () async {
      final now = DateTime.now();
      await db.into(db.cashWallets).insert(
            CashWalletsCompanion.insert(
              id: 'w_vf',
              branchId: 'b1',
              name: 'فودافون كاش',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final gate = FeatureGate(
        db,
        _FakeAuthLocalDataSource(),
        TxWriter(db),
        BranchProvider(db),
      );
      final wTurn = await service.askWithDraft('شحن محفظة فودافون كاش 500');
      expect(wTurn.insights.first.pendingCommand?.kind, AssistantCommandKind.walletTransfer);
      final wMsg = await service.executeCommand(
        wTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      expect(wMsg, contains('500.00'));

      final pTurn = await service.askWithDraft('مسحوبات شريك احمد 1200');
      expect(pTurn.insights.first.pendingCommand?.kind, AssistantCommandKind.partnerWithdraw);
      final pMsg = await service.executeCommand(
        pTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      expect(pMsg, contains('1200.00'));
    });
  });
}

