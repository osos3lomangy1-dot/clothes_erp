import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/partners/domain/entities/partner_entity.dart';
import 'package:clothes_erp/features/partners/data/datasources/partners_local_data_source.dart';
import 'package:clothes_erp/features/partners/data/repositories/partner_repository_impl.dart';
import 'package:clothes_erp/features/partners/presentation/cubits/partners_cubit.dart';
import 'package:clothes_erp/features/partners/presentation/screens/partners_screen.dart';

class _FakeFeatureGate implements FeatureGate {
  @override
  Future<bool> isEnabled(String key) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PartnerDeposit Entity Tests', () {
    test('PartnerDeposit creates correctly and returns localized labels', () {
      final now = DateTime.now();
      final d1 = PartnerDeposit(
        id: 'dep1',
        amount: 250000, // 2500 EGP
        category: 'goods',
        note: 'دفع فاتورة قماش من الجيب',
        date: now,
      );

      final d2 = PartnerDeposit(
        id: 'dep2',
        amount: 100000,
        category: 'expenses',
        note: 'سداد فاتورة كهرباء',
        date: now,
      );

      final d3 = PartnerDeposit(
        id: 'dep3',
        amount: 50000,
        category: 'cash',
        note: 'سيولة بالدرج',
        date: now,
      );

      expect(d1.categoryLabel, 'تكملة / شراء بضاعة');
      expect(d2.categoryLabel, 'سداد مصروفات أو إيجار');
      expect(d3.categoryLabel, 'سيولة نقدية في المحل');
    });

    test('PartnerDeposit serializes to JSON and deserializes accurately', () {
      final now = DateTime(2026, 11, 19, 14, 30);
      final deposit = PartnerDeposit(
        id: 'dep_json',
        amount: 350000,
        category: 'goods',
        note: 'تكملة ثمن بضاعة لمورد خارجي',
        date: now,
      );

      final json = deposit.toJson();
      final restored = PartnerDeposit.fromJson(json);

      expect(restored.id, deposit.id);
      expect(restored.amount, 350000);
      expect(restored.category, 'goods');
      expect(restored.note, 'تكملة ثمن بضاعة لمورد خارجي');
      expect(restored.date, now);
      expect(restored, deposit);
    });
  });

  group('PartnerEntity Retained Profit & Net Balance Calculations', () {
    test('calculates totalDeposited, getUnwithdrawnProfit, and calculateNetBalance correctly', () {
      final now = DateTime.now();
      final partner = PartnerEntity(
        id: 'p1',
        name: 'كريم أحمد',
        percentage: 50.0,
        capital: 10000000, // 100,000 EGP capital
        deposits: [
          PartnerDeposit(
            id: 'd1',
            amount: 1500000, // 15,000 EGP out of pocket for goods
            category: 'goods',
            date: now,
          ),
          PartnerDeposit(
            id: 'd2',
            amount: 500000, // 5,000 EGP out of pocket for rent
            category: 'expenses',
            date: now,
          ),
        ],
        withdrawals: [
          PartnerWithdrawal(
            id: 'w1',
            amount: 800000, // 8,000 EGP profit withdrawn
            type: 'profit',
            date: now,
          ),
        ],
        createdAt: now,
      );

      // 1. Total deposited from pocket
      expect(partner.totalDeposited, 2000000); // 20,000 EGP

      // 2. Active capital
      expect(partner.currentCapital, 10000000); // 100,000 EGP

      // 3. Profit earned in period: 20,000 EGP (2,000,000 piasters)
      const earnedProfit = 2000000;
      final unwithdrawnProfit = partner.getUnwithdrawnProfit(earnedProfit);
      expect(unwithdrawnProfit, 1200000); // 20,000 - 8,000 = 12,000 EGP retained

      // 4. Net balance entitlement:
      // capital (100,000) + totalDeposited (20,000) + unwithdrawnProfit (12,000) = 132,000 EGP
      final netBalance = partner.calculateNetBalance(earnedProfit);
      expect(netBalance, 13200000); // 132,000 EGP in piasters
    });

    test('getUnwithdrawnProfit returns 0 when withdrawals exceed or equal earned profit', () {
      final now = DateTime.now();
      final partner = PartnerEntity(
        id: 'p2',
        name: 'عمر شريف',
        percentage: 30.0,
        capital: 5000000,
        withdrawals: [
          PartnerWithdrawal(
            id: 'w1',
            amount: 1000000,
            type: 'profit',
            date: now,
          ),
        ],
        createdAt: now,
      );

      // When earned profit is smaller than what was withdrawn
      expect(partner.getUnwithdrawnProfit(500000), 0);
      // When earned profit exactly matches withdrawal
      expect(partner.getUnwithdrawnProfit(1000000), 0);
    });
  });

  group('PartnersCubit Deposit & Reinvestment Workflows', () {
    late AppDatabase db;
    late PartnersLocalDataSource ds;
    late PartnerRepositoryImpl repo;
    late PartnersCubit cubit;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      ds = PartnersLocalDataSourceImpl(db);
      repo = PartnerRepositoryImpl(ds, _FakeFeatureGate());
      cubit = PartnersCubit(repo);
    });

    tearDown(() async {
      await cubit.close();
      await db.close();
    });

    test('recordDeposit records funding and persists to database', () async {
      final now = DateTime.now();
      final initialPartner = PartnerEntity(
        id: 'partner_fund_1',
        name: 'هيثم خالد',
        percentage: 50.0,
        capital: 5000000,
        createdAt: now,
      );

      await ds.savePartner(initialPartner);
      await cubit.loadData();

      // Record out-of-pocket funding for goods
      final depositSuccess = await cubit.recordDeposit(
        partnerId: 'partner_fund_1',
        amount: 2500000, // 25,000 EGP
        category: 'goods',
        note: 'دفع فاتورة ملابس للمورد كاش من الجيب',
      );

      expect(depositSuccess, true);

      final updatedPartner = cubit.state.partners.firstWhere((p) => p.id == 'partner_fund_1');
      expect(updatedPartner.deposits.length, 1);
      expect(updatedPartner.deposits.first.amount, 2500000);
      expect(updatedPartner.deposits.first.category, 'goods');
      expect(updatedPartner.deposits.first.note, 'دفع فاتورة ملابس للمورد كاش من الجيب');
      expect(updatedPartner.totalDeposited, 2500000);

      // Verify persistent round-trip from database
      final fromDb = await ds.getPartners();
      final loadedPartner = fromDb.firstWhere((p) => p.id == 'partner_fund_1');
      expect(loadedPartner.totalDeposited, 2500000);
      expect(loadedPartner.deposits.first.category, 'goods');
    });

    test('reinvestProfitIntoCapital increases partner capital and records profit withdrawal', () async {
      final now = DateTime.now();
      final initialPartner = PartnerEntity(
        id: 'partner_reinvest_1',
        name: 'ياسر ممدوح',
        percentage: 40.0,
        capital: 4000000, // 40,000 EGP
        createdAt: now,
      );

      await ds.savePartner(initialPartner);
      await cubit.loadData();

      // Partner leaves 15,000 EGP of their profit in the store to increase capital
      final reinvestSuccess = await cubit.reinvestProfitIntoCapital(
        partnerId: 'partner_reinvest_1',
        amount: 1500000, // 15,000 EGP
        note: 'تدوير أرباح الربع السنوي لزيادة رأس المال',
      );

      expect(reinvestSuccess, true);

      final updatedPartner = cubit.state.partners.firstWhere((p) => p.id == 'partner_reinvest_1');
      // Capital increased by 15,000 EGP (40,000 + 15,000 = 55,000 EGP)
      expect(updatedPartner.capital, 5500000);
      // Withdrawal recorded under profit
      expect(updatedPartner.withdrawals.length, 1);
      expect(updatedPartner.withdrawals.first.amount, 1500000);
      expect(updatedPartner.withdrawals.first.type, 'profit');
      expect(updatedPartner.totalProfitWithdrawn, 1500000);

      // Verify round-trip persistence in database
      final fromDb = await ds.getPartners();
      final loadedPartner = fromDb.firstWhere((p) => p.id == 'partner_reinvest_1');
      expect(loadedPartner.capital, 5500000);
      expect(loadedPartner.withdrawals.length, 1);
    });

    test('partner with zero initial capital and direct percentage works seamlessly', () async {
      final now = DateTime.now();
      // Partner agreed by pure percentage (e.g. 50% / 50% from years ago, without specifying initial capital)
      final directPercentagePartner = PartnerEntity(
        id: 'partner_direct_percent',
        name: 'شريك بالنسبة فقط',
        percentage: 50.0,
        capital: 0,
        createdAt: now,
      );

      final saveOk = await cubit.savePartner(directPercentagePartner);
      expect(saveOk, true);

      // Profit calculation: 10,000 EGP net profit (1,000,000 piasters)
      const netProfit = 1000000;
      final share = directPercentagePartner.calculateProfitShare(netProfit);
      expect(share, 500000); // 50% = 5,000 EGP

      // If they later fund goods from pocket: 2,000 EGP
      await cubit.recordDeposit(
        partnerId: 'partner_direct_percent',
        amount: 200000,
        category: 'goods',
        note: 'دفع فاتورة مورد من الجيب',
      );

      final updated = cubit.state.partners.firstWhere((p) => p.id == 'partner_direct_percent');
      expect(updated.capital, 0); // Capital remains 0
      expect(updated.totalDeposited, 200000); // Funding tracked
      expect(updated.calculateNetBalance(share), 700000); // 5,000 EGP profit + 2,000 EGP goods funding
    });

    test('refundDeposit reduces remainingDeposited and leaves capital intact', () async {
      final now = DateTime.now();
      final partner = PartnerEntity(
        id: 'p_refund_test',
        name: 'شريك استرداد',
        percentage: 50.0,
        capital: 5000000,
        deposits: [
          PartnerDeposit(
            id: 'dep_1',
            amount: 1000000, // 10,000 EGP from pocket
            category: 'goods',
            date: now,
          ),
        ],
        createdAt: now,
      );

      await ds.savePartner(partner);
      await cubit.loadData();

      // Partner gets reimbursed 4,000 EGP from drawer
      final ok = await cubit.refundDeposit(
        partnerId: 'p_refund_test',
        amount: 400000,
        note: 'استرداد كاش من الدرج عن دفعة البضاعة',
      );
      expect(ok, true);

      final updated = cubit.state.partners.firstWhere((p) => p.id == 'p_refund_test');
      expect(updated.totalDeposited, 1000000);
      expect(updated.totalDepositsRefunded, 400000);
      expect(updated.remainingDeposited, 600000); // 6,000 EGP remaining
      expect(updated.currentCapital, 5000000); // Capital unchanged
      expect(updated.withdrawals.last.type, 'deposit_refund');
    });

    test('convertDepositToCapital moves personal funding into active capital', () async {
      final now = DateTime.now();
      final partner = PartnerEntity(
        id: 'p_convert_test',
        name: 'شريك ضم رأس المال',
        percentage: 50.0,
        capital: 5000000, // 50,000 EGP
        deposits: [
          PartnerDeposit(
            id: 'dep_c1',
            amount: 2000000, // 20,000 EGP from pocket
            category: 'goods',
            date: now,
          ),
        ],
        createdAt: now,
      );

      await ds.savePartner(partner);
      await cubit.loadData();

      // Partner converts the full 20,000 EGP into capital
      final ok = await cubit.convertDepositToCapital(
        partnerId: 'p_convert_test',
        amount: 2000000,
        note: 'ضم دفعة البضاعة لحصة رأس المال',
      );
      expect(ok, true);

      final updated = cubit.state.partners.firstWhere((p) => p.id == 'p_convert_test');
      expect(updated.capital, 7000000); // 50,000 + 20,000 = 70,000 EGP
      expect(updated.remainingDeposited, 0); // 0 remaining personal funding
      expect(updated.totalDepositsRefunded, 2000000);
      expect(updated.withdrawals.last.type, 'deposit_to_capital');
    });
  });

  group('PartnersScreen UI Widget Tests', () {
    late AppDatabase db;
    late PartnersLocalDataSource ds;
    late PartnerRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ds = PartnersLocalDataSourceImpl(db);
      repo = PartnerRepositoryImpl(ds, _FakeFeatureGate());

      if (getIt.isRegistered<PartnersCubit>()) {
        getIt.unregister<PartnersCubit>();
      }
      getIt.registerFactory<PartnersCubit>(() => PartnersCubit(repo));

      // Seed a partner with personal funding
      await ds.savePartner(PartnerEntity(
        id: 'p_ui_1',
        name: 'كريم التاجر',
        percentage: 50.0,
        capital: 5000000,
        deposits: [
          PartnerDeposit(
            id: 'd1',
            amount: 1000000,
            category: 'goods',
            date: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
      ));
    });

    tearDown(() async {
      if (getIt.isRegistered<PartnersCubit>()) {
        getIt.unregister<PartnersCubit>();
      }
      await db.close();
    });

    testWidgets('renders PartnersScreen, shows personal funding banner and opens refund & convert dialogs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PartnersScreen(),
          ),
        ),
      );

      // Allow async loadData to complete
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('الشركاء وحساب وتوزيع الأرباح'), findsOneWidget);
      expect(find.text('كريم التاجر'), findsOneWidget);

      // Verify dedicated personal funding banner is shown prominently
      expect(find.text('تمويل شخصي من الجيب (لك عند المحل):'), findsOneWidget);
      expect(find.text('10000.00 ج.م'), findsWidgets);

      // Verify cash reimbursement and capital conversion buttons exist
      expect(find.text('استرداد كاش'), findsOneWidget);
      expect(find.text('ضمه لرأس المال'), findsOneWidget);

      // Test opening Cash Refund Dialog
      await tester.tap(find.text('استرداد كاش'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('استرداد تمويل شخصي من الجيب: كريم التاجر'), findsOneWidget);
      expect(find.text('تأكيد الاسترداد كاش'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('إلغاء'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Test opening Convert to Capital Dialog
      await tester.tap(find.text('ضمه لرأس المال'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('تحويل تمويل الجيب لرأس مال: كريم التاجر'), findsOneWidget);
      expect(find.text('تأكيد التحويل لرأس المال'), findsOneWidget);
    });

    testWidgets('renders distinct badges for capital share and profit share when configured', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      // Save a partner with 40% capital share and 60% profit share
      await ds.savePartner(PartnerEntity(
        id: 'p_dual_share',
        name: 'شريك مستثمر ومدير',
        percentage: 60.0, // 60% profit share
        capitalPercentage: 40.0, // 40% capital equity share
        capital: 1000000, // 10,000 EGP
        createdAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PartnersScreen(),
          ),
        ),
      );

      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('شريك مستثمر ومدير'), findsOneWidget);
      expect(find.text('حصة رأس المال: 40.0%'), findsOneWidget);
      expect(find.text('نسبة الأرباح: 60.0%'), findsOneWidget);
    });

    testWidgets('renders dedicated temporary advance banner when partner has outstanding advance', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await ds.savePartner(PartnerEntity(
        id: 'p_with_advance',
        name: 'شريك عليه سلفة',
        percentage: 20.0,
        capital: 2000000,
        withdrawals: [
          PartnerWithdrawal(
            id: 'adv1',
            amount: 500000, // 5,000 EGP advance
            type: 'advance',
            date: DateTime.now(),
          ),
        ],
        createdAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PartnersScreen(),
          ),
        ),
      );

      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('شريك عليه سلفة'), findsOneWidget);
      expect(find.text('سلفة شخصية مؤقتة (عليك للمحل):'), findsOneWidget);
      expect(find.text('5000.00 ج.م'), findsOneWidget);
      expect(find.text('رد السلفة للدرج'), findsOneWidget);

      // Tap "رد السلفة للدرج"
      await tester.ensureVisible(find.text('رد السلفة للدرج'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('رد السلفة للدرج'));
      await tester.pumpAndSettle();

      // Verify it opens with pre-selected category and prefilled amount
      expect(find.text('رد سلفة شخصية مؤقتة: شريك عليه سلفة'), findsOneWidget);
      expect(find.text('5000'), findsOneWidget);
      expect(find.text('تأكيد رد السلفة'), findsOneWidget);
    });
  });

  group('Dual Share (Capital Share vs Profit Share) Logic Tests', () {
    test('effectiveCapitalPercentage falls back to percentage when capitalPercentage is null', () {
      final p1 = PartnerEntity(
        id: 'legacy_p',
        name: 'شريك قديم',
        percentage: 35.0,
        createdAt: DateTime.now(),
      );
      expect(p1.capitalPercentage, isNull);
      expect(p1.effectiveCapitalPercentage, 35.0);
    });

    test('partner can have 50% capital share and 60% profit share, profit calculation strictly uses percentage', () {
      final now = DateTime.now();
      final partner = PartnerEntity(
        id: 'p_custom',
        name: 'شريك بنسبة أرباح إضافية للإدارة',
        capital: 1000000, // 10,000 EGP
        capitalPercentage: 50.0, // 50% equity of the store
        percentage: 60.0, // 60% profit distribution
        createdAt: now,
      );

      expect(partner.capitalPercentage, 50.0);
      expect(partner.percentage, 60.0);
      expect(partner.effectiveCapitalPercentage, 50.0);

      // Suppose net profit for the month is 100,000 EGP (10,000,000 piasters)
      const netProfit = 10000000;
      final profitShare = partner.calculateProfitShare(netProfit);

      // Profit share MUST be 60% of 100,000 = 60,000 EGP (6,000,000 piasters), NOT 50%
      expect(profitShare, 6000000);

      // JSON serialization & deserialization preserves capitalPercentage
      final json = partner.toJson();
      expect(json['capitalPercentage'], 50.0);

      final restored = PartnerEntity.fromJson(json);
      expect(restored.capitalPercentage, 50.0);
      expect(restored.percentage, 60.0);
      expect(restored.calculateProfitShare(netProfit), 6000000);
    });
  });

  group('Temporary Partner Advance (السلفة المؤقتة وتسويتها) Tests', () {
    late AppDatabase db;
    late PartnersLocalDataSource ds;
    late PartnerRepositoryImpl repo;
    late PartnersCubit cubit;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ds = PartnersLocalDataSourceImpl(db);
      repo = PartnerRepositoryImpl(ds, _FakeFeatureGate());
      cubit = PartnersCubit(repo);

      await ds.savePartner(PartnerEntity(
        id: 'p_advance_test',
        name: 'شريك تجارب السلفة',
        percentage: 50.0,
        capital: 5000000, // 50,000 EGP
        createdAt: DateTime.now(),
      ));
      await cubit.loadData();
    });

    tearDown(() async {
      await cubit.close();
      await db.close();
    });

    test('withdrawing temporary advance records advance and does NOT affect profit or capital', () async {
      // 1. Withdraw an advance of 5,000 EGP (500,000 piasters)
      final ok = await cubit.recordWithdrawal(
        partnerId: 'p_advance_test',
        amount: 500000,
        type: 'advance',
        note: 'سلفة شخصية طارئة لأيام',
      );
      expect(ok, isTrue);

      final partner = cubit.state.partners.firstWhere((p) => p.id == 'p_advance_test');
      expect(partner.totalAdvanceWithdrawn, 500000);
      expect(partner.totalAdvanceRepaid, 0);
      expect(partner.remainingAdvance, 500000); // Partner owes store 5,000 EGP

      // Crucial: Profit and capital MUST NOT be touched
      expect(partner.totalProfitWithdrawn, 0);
      expect(partner.totalCapitalWithdrawn, 0);
      expect(partner.currentCapital, 5000000);

      // 2. Net balance calculation accounts for the outstanding advance
      // 50,000 (capital) + 10,000 (earned profit) - 5,000 (advance) = 55,000 EGP
      expect(partner.calculateNetBalance(1000000), 5500000);
    });

    test('repaying temporary advance clears remainingAdvance and does NOT increase store debt/totalDeposited', () async {
      // 1. Take advance
      await cubit.recordWithdrawal(
        partnerId: 'p_advance_test',
        amount: 500000,
        type: 'advance',
      );

      // 2. Repay advance into store cash drawer
      final ok = await cubit.recordDeposit(
        partnerId: 'p_advance_test',
        amount: 500000,
        category: 'advance_repayment',
        note: 'رد السلفة الشخصية للدرج بالكامل',
      );
      expect(ok, isTrue);

      final partner = cubit.state.partners.firstWhere((p) => p.id == 'p_advance_test');
      expect(partner.totalAdvanceWithdrawn, 500000);
      expect(partner.totalAdvanceRepaid, 500000);
      expect(partner.remainingAdvance, 0); // Settled!

      // Crucial: Must NOT be treated as funding / debt on store
      expect(partner.totalDeposited, 0);
      expect(partner.remainingDeposited, 0);
      expect(partner.totalProfitWithdrawn, 0);
      expect(partner.currentCapital, 5000000);
    });

    test('deleteWithdrawal and deleteDeposit remove transactions and restore balances', () async {
      // Record a withdrawal
      await cubit.recordWithdrawal(
        partnerId: 'p_advance_test',
        amount: 300000,
        type: 'profit',
      );
      var partner = cubit.state.partners.firstWhere((p) => p.id == 'p_advance_test');
      expect(partner.totalProfitWithdrawn, 300000);
      final withdrawalId = partner.withdrawals.first.id;

      // Delete the withdrawal
      final okDelW = await cubit.deleteWithdrawal(
        partnerId: 'p_advance_test',
        withdrawalId: withdrawalId,
      );
      expect(okDelW, isTrue);

      partner = cubit.state.partners.firstWhere((p) => p.id == 'p_advance_test');
      expect(partner.withdrawals, isEmpty);
      expect(partner.totalProfitWithdrawn, 0);

      // Record a deposit
      await cubit.recordDeposit(
        partnerId: 'p_advance_test',
        amount: 200000,
        category: 'goods',
      );
      partner = cubit.state.partners.firstWhere((p) => p.id == 'p_advance_test');
      expect(partner.totalDeposited, 200000);
      final depositId = partner.deposits.first.id;

      // Delete the deposit
      final okDelD = await cubit.deleteDeposit(
        partnerId: 'p_advance_test',
        depositId: depositId,
      );
      expect(okDelD, isTrue);

      partner = cubit.state.partners.firstWhere((p) => p.id == 'p_advance_test');
      expect(partner.deposits, isEmpty);
      expect(partner.totalDeposited, 0);
    });
  });
}
