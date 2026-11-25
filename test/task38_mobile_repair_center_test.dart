import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:clothes_erp/features/repair/data/services/mobile_repair_service.dart';
import 'package:clothes_erp/features/repair/presentation/screens/repair_center_screen.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';

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
  late MobileRepairService repairService;
  late ShiftLocalDataSourceImpl shiftDs;
  late DashboardLocalDataSourceImpl dashboardDs;
  late ReportsLocalDataSourceImpl reportsDs;
  const branchId = 'branch_main';

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    featureGate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, bp);
    repairService = MobileRepairService(db, bp, tx);
    shiftDs = ShiftLocalDataSourceImpl(db, bp, tx, featureGate);
    dashboardDs = DashboardLocalDataSourceImpl(db);
    reportsDs = ReportsLocalDataSourceImpl(db);

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<BranchProvider>(bp);
    getIt.registerSingleton<TxWriter>(tx);
    getIt.registerSingleton<FeatureGate>(featureGate);
    getIt.registerSingleton<MobileRepairService>(repairService);
  });

  tearDown(() async {
    featureGate.dispose();
    await db.close();
    await getIt.reset();
  });

  Future<void> seedSparePart({int qty = 3, int costPrice = 15000}) async {
    final now = DateTime.now();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat_parts',
            branchId: branchId,
            name: 'قطع غيار',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod_bat',
            branchId: branchId,
            name: 'بطارية أصلية',
            categoryId: 'cat_parts',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var_bat',
            branchId: branchId,
            productId: 'prod_bat',
            sku: 'BAT-IP14',
            color: 'أسود',
            size: 'قياسي',
            quantity: Value(qty),
            costPrice: costPrice,
            sellPrice: 30000,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('Task 38: FeatureGate Isolation & Schema v14', () {
    test('FeatureKeys.mobileRepair defaults to false', () async {
      expect(await featureGate.isEnabled(FeatureKeys.mobileRepair), isFalse);
      await featureGate.setFeatureEnabled(
        FeatureKeys.mobileRepair,
        true,
        userId: 'system',
      );
      expect(await featureGate.isEnabled(FeatureKeys.mobileRepair), isTrue);
    });

    test('AppDatabase schemaVersion is 14 and migrateToV14 creates repair tables', () async {
      expect(db.schemaVersion, 14);

      final raw = sq.sqlite3.openInMemory();
      final v13Db = AppDatabase(NativeDatabase.opened(raw));
      final m = v13Db.createMigrator();
      await v13Db.migrateToV14(m);

      final ticketCols = raw.select('PRAGMA table_info(repair_tickets);');
      expect(ticketCols.any((r) => r['name'] == 'ticket_number'), isTrue);
      expect(ticketCols.any((r) => r['name'] == 'parts_cost'), isTrue);

      final partsCols = raw.select('PRAGMA table_info(repair_ticket_parts);');
      expect(partsCols.any((r) => r['name'] == 'variant_id'), isTrue);
      expect(partsCols.any((r) => r['name'] == 'unit_cost'), isTrue);

      await v13Db.close();
    });
  });

  group('Task 38: Full Repair Lifecycle, Receipt, Drawer & Profit', () {
    test('Intake with deposit -> spare part deduction -> delivery -> Shift, Dashboard & Reports', () async {
      await seedSparePart(qty: 3, costPrice: 15000); // 150 EGP cost

      // Open shift with 1,000 EGP (100,000 piasters)
      final shift = await shiftDs.openShift(
        openingBalance: 100000,
        cashierId: 'admin',
      );

      // 1. Intake with 200 EGP deposit (20,000 piasters)
      final ticket = await repairService.createTicket(
        customerName: 'كريم حسن',
        customerPhone: '01022334455',
        deviceModel: 'iPhone 14',
        imei: '351234567890123',
        issueDescription: 'تغيير بطارية',
        intakeCondition: 'شاشة سليمة',
        passcodeOrPattern: '1234',
        estimatedCostPiasters: 60000, // 600 EGP
        depositPaidPiasters: 20000, // 200 EGP
        technicianName: 'م. طارق',
      );
      expect(ticket.status, 'pending');
      expect(ticket.depositPaid, 20000);

      // Verify thermal receipt PDF generates cleanly
      final pdfBytes = await MobileRepairService.generateRepairReceiptPdf(ticket);
      expect(pdfBytes.length, greaterThan(500));

      // 2. Status updates + dispense 1 spare part (cost 150 EGP)
      await repairService.updateStatus(ticketId: ticket.id, status: 'in_progress');
      await repairService.addPartToTicket(
        ticketId: ticket.id,
        variantId: 'var_bat',
        qty: 1,
      );

      final updatedVariant = await (db.select(db.productVariants)
            ..where((t) => t.id.equals('var_bat')))
          .getSingle();
      expect(updatedVariant.quantity, 2);

      await repairService.updateStatus(ticketId: ticket.id, status: 'ready');

      // 3. Deliver & collect remaining (600 - 200 = 400 EGP)
      final delivery = await repairService.deliverAndCollect(
        ticketId: ticket.id,
        finalCostPiasters: 60000,
      );
      expect(delivery.remainingCollectedPiasters, 40000);
      expect(delivery.partsCostPiasters, 15000);
      expect(delivery.netProfitPiasters, 45000); // 600 - 150 = 450 EGP

      // Verify ShiftSummary: 1000 opening + 200 deposit + 400 remaining = 1600 EGP
      final summary = await shiftDs.getShiftSummary(shift.id);
      expect(summary.repairCollectedCash, 60000);
      expect(summary.expectedCashInDrawer, 160000);

      // Verify Dashboard & Reports net profit = 450 EGP (45,000 piasters)
      final dashStats = await dashboardDs.getDashboardStats();
      expect(dashStats.todayEstimatedNetProfit, 45000);

      final now = DateTime.now();
      final report = await reportsDs.getSalesReport(
        startDate: DateTime(now.year, now.month, now.day),
        endDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
      expect(report.totalRevenue, 60000);
      expect(report.totalCost, 15000);
      expect(report.netProfit, 45000);
    });
  });

  group('Task 38: RepairCenterScreen Widget & 6-Shortcut Constitution', () {
    testWidgets('F2 focuses search, F3 opens new ticket dialog, F12 saves ticket', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RepairCenterScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // F2 focuses search
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('repair_search_field')), 'iPhone');
      await tester.pump();

      // Esc clears search
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('repair_search_field'))).controller?.text,
        isEmpty,
      );

      // F3 opens new ticket dialog
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.text('استلام جهاز صيانة جديد'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('repair_customer_field')), 'سعيد');
      await tester.enterText(find.byKey(const Key('repair_model_field')), 'Samsung S24');
      await tester.enterText(find.byKey(const Key('repair_issue_field')), 'شاشة مكسورة');
      await tester.pump();

      // F12 saves ticket
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();

      final tickets = await repairService.getTickets();
      expect(tickets.length, 1);
      expect(tickets.first.deviceModel, 'Samsung S24');
    });
  });
}

