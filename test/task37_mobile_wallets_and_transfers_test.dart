import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
import 'package:clothes_erp/features/wallets/data/services/mobile_wallets_service.dart';
import 'package:clothes_erp/features/wallets/presentation/screens/wallets_screen.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  @override
  Future<void> cacheUser(UserModel user) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<UserModel?> getCachedUser() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late FeatureGate featureGate;
  late MobileWalletsService walletsService;
  late ShiftLocalDataSourceImpl shiftDs;
  late DashboardLocalDataSourceImpl dashboardDs;

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    featureGate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, bp);
    walletsService = MobileWalletsService(db, bp, tx);
    shiftDs = ShiftLocalDataSourceImpl(db, bp, tx, featureGate);
    dashboardDs = DashboardLocalDataSourceImpl(db);

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<BranchProvider>(bp);
    getIt.registerSingleton<TxWriter>(tx);
    getIt.registerSingleton<FeatureGate>(featureGate);
    getIt.registerSingleton<MobileWalletsService>(walletsService);
  });

  tearDown(() async {
    featureGate.dispose();
    await db.close();
    await getIt.reset();
  });

  group('Task 37: FeatureGate Isolation & Schema v13', () {
    test('FeatureKeys.mobileWallets defaults to false', () async {
      expect(await featureGate.isEnabled(FeatureKeys.mobileWallets), isFalse);
      await featureGate.setFeatureEnabled(
        FeatureKeys.mobileWallets,
        true,
        userId: 'system',
      );
      expect(await featureGate.isEnabled(FeatureKeys.mobileWallets), isTrue);
    });

    test('AppDatabase schemaVersion is >= 13 and migrateToV13 creates wallet tables', () async {
      expect(db.schemaVersion, greaterThanOrEqualTo(13));

      final raw = sq.sqlite3.openInMemory();
      final v12Db = AppDatabase(NativeDatabase.opened(raw));
      final m = v12Db.createMigrator();
      await v12Db.migrateToV13(m);

      final walletCols = raw.select('PRAGMA table_info(cash_wallets);');
      expect(walletCols.any((r) => r['name'] == 'monthly_limit'), isTrue);
      expect(walletCols.any((r) => r['name'] == 'monthly_used'), isTrue);

      final txCols = raw.select('PRAGMA table_info(wallet_transactions);');
      expect(txCols.any((r) => r['name'] == 'commission'), isTrue);
      expect(txCols.any((r) => r['name'] == 'shift_id'), isTrue);

      await v12Db.close();
    });
  });

  group('Task 37: Exact Accounting, ShiftSummary & Dashboard Profit', () {
    test('Deposit out, withdraw in, topup, monthly limit, ShiftSummary & Dashboard profit', () async {
      // Open a shift with 1,000.00 EGP (100,000 piasters)
      final shift = await shiftDs.openShift(
        openingBalance: 100000,
        cashierId: 'admin',
      );

      final wallet = await walletsService.createWallet(
        name: 'فودافون كاش 1',
        providerType: 'vodafone_cash',
        phoneOrTerminal: '01000000001',
        initialBalancePiasters: 500000, // 5,000 EGP
        monthlyLimitPiasters: 250000, // 2,500 EGP limit
      );

      // 1. Outgoing transfer: 1,000 EGP + 10 EGP commission
      // Wallet: 5000 - 1000 = 4000 EGP
      // Drawer: +1010 EGP
      // Profit: 10 EGP
      final res1 = await walletsService.executeTransaction(
        walletId: wallet.id,
        type: 'deposit_out_transfer',
        amountPiasters: 100000,
        commissionPiasters: 1000,
        customerPhone: '01099998888',
      );
      expect(res1.newWalletBalancePiasters, 400000);
      expect(res1.drawerDeltaPiasters, 101000);
      expect(res1.profitPiasters, 1000);

      // 2. Cash withdrawal for customer: 500 EGP + 10 EGP commission
      // Wallet: 4000 + 500 = 4500 EGP
      // Drawer: -(500 - 10) = -490 EGP
      // Profit: 10 EGP
      final res2 = await walletsService.executeTransaction(
        walletId: wallet.id,
        type: 'withdraw_in_cash',
        amountPiasters: 50000,
        commissionPiasters: 1000,
      );
      expect(res2.newWalletBalancePiasters, 450000);
      expect(res2.drawerDeltaPiasters, -49000);
      expect(res2.profitPiasters, 1000);

      // 3. Topup from drawer: 200 EGP (commission forced to 0)
      // Wallet: 4500 + 200 = 4700 EGP
      // Drawer: -200 EGP
      // Profit: 0 EGP
      final res3 = await walletsService.executeTransaction(
        walletId: wallet.id,
        type: 'topup_from_drawer',
        amountPiasters: 20000,
        commissionPiasters: 999, // must be ignored -> 0 profit
      );
      expect(res3.newWalletBalancePiasters, 470000);
      expect(res3.drawerDeltaPiasters, -20000);
      expect(res3.profitPiasters, 0);

      // Monthly limit check: used 1000 + 500 = 1500 EGP out of 2500 EGP -> 1000 remaining
      // Attempting 1200 EGP transfer must fail
      await expectLater(
        walletsService.executeTransaction(
          walletId: wallet.id,
          type: 'deposit_out_transfer',
          amountPiasters: 120000,
          commissionPiasters: 1000,
        ),
        throwsException,
      );

      // Verify ShiftSummary:
      // Net drawer delta = +101000 - 49000 - 20000 = +32000 (320 EGP)
      // Expected cash in drawer = 100000 + 32000 = 132000 (1320 EGP)
      // Wallet commissions = 1000 + 1000 = 2000 (20 EGP)
      final summary = await shiftDs.getShiftSummary(shift.id);
      expect(summary.walletNetCash, 32000);
      expect(summary.walletCommissions, 2000);
      expect(summary.expectedCashInDrawer, 132000);

      // Verify Dashboard todayEstimatedNetProfit includes ONLY commission profit (20 EGP)
      final stats = await dashboardDs.getDashboardStats();
      expect(stats.todayEstimatedNetProfit, 2000);
    });
  });

  group('Task 37: WalletsScreen Widget & 6-Shortcut Constitution', () {
    testWidgets('F2 focuses search, F3 opens operation dialog, F12 executes transaction', (tester) async {
      await walletsService.createWallet(
        name: 'إنستا باي',
        providerType: 'instapay',
        phoneOrTerminal: 'store@instapay',
        initialBalancePiasters: 300000,
        monthlyLimitPiasters: 500000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: WalletsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إنستا باي'), findsOneWidget);
      expect(find.textContaining('المتبقي من الحد الشهري'), findsOneWidget);

      // F2 focuses search field
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('wallets_search_field')), 'إنستا');
      await tester.pump();

      // Esc clears search
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('wallets_search_field'))).controller?.text,
        isEmpty,
      );

      // F3 opens operation dialog
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.text('تنفيذ عملية محفظة إلكترونية'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('wallet_tx_amount_field')), '500');
      await tester.enterText(find.byKey(const Key('wallet_tx_commission_field')), '5');
      await tester.pump();

      // F12 executes transaction
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();

      final wallets = await walletsService.getWallets();
      expect(wallets.first.currentBalance, 250000); // 3000 - 500 = 2500 EGP
      expect(wallets.first.monthlyUsed, 50000);
    });
  });
}
