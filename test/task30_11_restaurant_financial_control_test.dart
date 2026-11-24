import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/inventory/presentation/widgets/kitchen_waste_audit_dialog.dart';
import 'package:clothes_erp/features/pos/presentation/widgets/petty_cash_dialog.dart';
import 'package:clothes_erp/features/reports/domain/services/kitchen_waste_audit_service.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_entity.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:clothes_erp/features/shifts/presentation/services/z_report_service.dart';
import 'package:clothes_erp/features/shifts/presentation/widgets/z_report_dialog.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'b1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  @override
  Future<UserModel?> getCachedUser() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShiftCubit extends Cubit<ShiftState> implements ShiftCubit {
  bool loadShiftDataCalled = false;

  _FakeShiftCubit(ShiftEntity activeShift)
      : super(ShiftState(status: ShiftStatus.loaded, activeShift: activeShift));

  @override
  Future<void> loadShiftData() async {
    loadShiftDataCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late _FakeBranchProvider branchProvider;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = _FakeBranchProvider();

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<BranchProvider>(branchProvider);
    getIt.registerSingleton<KitchenWasteAuditService>(KitchenWasteAuditService(db));
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  group('Addendum 30.11: Restaurant Financial Control Suite', () {
    testWidgets('1. PettyCashDialog renders presets, reasons and registers withdrawal in CashMovements', (tester) async {
      final now = DateTime.now();
      const shiftId = 'test_shift_petty_1';
      await db.into(db.shifts).insertOnConflictUpdate(
        ShiftsCompanion.insert(
          id: shiftId,
          cashierId: 'c1',
          branchId: 'b1',
          openedAt: now,
          openingBalance: 100000, // 1000 EGP
          createdAt: now,
          updatedAt: now,
        ),
      );

      final fakeShiftCubit = _FakeShiftCubit(
        ShiftEntity(
          id: shiftId,
          branchId: 'b1',
          cashierId: 'c1',
          openingBalance: 100000,
          openedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(
        BlocProvider<ShiftCubit>.value(
          value: fakeShiftCubit,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: ElevatedButton(
                      onPressed: () => PettyCashDialog.show(ctx),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify preset chips exist
      expect(find.byKey(const Key('petty_cash_preset_20')), findsOneWidget);
      expect(find.byKey(const Key('petty_cash_preset_50')), findsOneWidget);
      expect(find.byKey(const Key('petty_cash_preset_100')), findsOneWidget);
      expect(find.byKey(const Key('petty_cash_preset_200')), findsOneWidget);

      // Tap preset 50
      await tester.tap(find.byKey(const Key('petty_cash_preset_50')));
      await tester.pumpAndSettle();
      expect(find.text('50'), findsOneWidget);

      // Tap 'خامات طارئة'
      await tester.tap(find.byKey(const Key('petty_cash_reason_خامات طارئة')));
      await tester.pumpAndSettle();

      // Enter notes
      final notesField = find.byKey(const Key('petty_cash_notes_input'));
      expect(notesField, findsOneWidget);
      await tester.enterText(notesField, 'طماطم للسلطة');
      await tester.pumpAndSettle();

      // Tap confirm button
      final confirmBtn = find.byKey(const Key('confirm_petty_cash_btn'));
      expect(confirmBtn, findsOneWidget);
      await tester.ensureVisible(confirmBtn);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(confirmBtn);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // Verify row inserted in CashMovements
      final movements = await tester.runAsync(
        () => (db.select(db.cashMovements)
              ..where((m) => m.notes.like('%خامات طارئة%')))
            .get(),
      );
      expect(movements, isNotNull);
      expect(movements!.isNotEmpty, isTrue);
      final m = movements.last;
      expect(m.type, equals('withdrawal'));
      expect(m.direction, equals('out'));
      expect(m.amountPiasters, equals(5000));
      expect(m.shiftId, equals(shiftId));
      expect(m.notes, contains('طماطم للسلطة'));
      expect(fakeShiftCubit.loadShiftDataCalled, isTrue);
    });

    test('2. Staff Tips Pool & Petty Cash reflect accurately in ShiftSummaryEntity & ZReport thermal PDF', () async {
      final now = DateTime.now();
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      const shiftId = 'test_shift_tips_1';

      await db.into(db.shifts).insertOnConflictUpdate(
        ShiftsCompanion.insert(
          id: shiftId,
          cashierId: 'cashier_tip_1',
          branchId: 'b1',
          openedAt: now.subtract(const Duration(hours: 2)),
          openingBalance: 50000, // 500 EGP
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Record tip cash movement (20 EGP)
      await db.into(db.cashMovements).insert(
        CashMovementsCompanion.insert(
          id: 'cm_tip_test_1',
          branchId: 'b1',
          shiftId: const drift.Value(shiftId),
          type: 'deposit',
          method: 'cash',
          direction: 'in',
          amountPiasters: 2000,
          notes: const drift.Value('إكرامية عاملين (Tips): فاتورة #101'),
          createdAt: nowSec,
          updatedAt: nowSec,
        ),
      );

      // Record petty cash withdrawal (15 EGP)
      await db.into(db.cashMovements).insert(
        CashMovementsCompanion.insert(
          id: 'cm_pc_test_1',
          branchId: 'b1',
          shiftId: const drift.Value(shiftId),
          type: 'withdrawal',
          method: 'cash',
          direction: 'out',
          amountPiasters: 1500,
          notes: const drift.Value('نثريات كاشير: شراء ثلج'),
          createdAt: nowSec,
          updatedAt: nowSec,
        ),
      );

      final tx = TxWriter(db);
      final featureGate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, branchProvider);
      final dataSource = ShiftLocalDataSourceImpl(db, branchProvider, tx, featureGate);
      final summary = await dataSource.getShiftSummary(shiftId);

      expect(summary.tipsPool, equals(2000));
      expect(summary.cashExpenses, equals(1500));
      // expected = 50000 opening + 2000 tip - 1500 withdrawal = 50500
      expect(summary.expectedCashInDrawer, equals(50500));

      // Test Z-Report thermal PDF generation runs cleanly
      final pdfBytes = await ZReportService.generateThermalPdf(summary);
      expect(pdfBytes.isNotEmpty, isTrue);
    });

    testWidgets('3. ZReportDialog displays Tips Pool when tipsPool > 0', (tester) async {
      final now = DateTime.now();
      final summary = ShiftSummaryEntity(
        shift: ShiftEntity(
          id: 's1',
          branchId: 'b1',
          cashierId: 'c1',
          cashierName: 'أحمد',
          openingBalance: 20000,
          openedAt: now.subtract(const Duration(hours: 4)),
          createdAt: now,
          updatedAt: now,
        ),
        cashSales: 100000,
        cardSales: 50000,
        otherSales: 0,
        cashReturns: 0,
        cashExpenses: 5000,
        totalSalesCount: 10,
        expectedCashInDrawer: 120000,
        tipsPool: 3500, // 35 EGP tips
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ZReportDialog(summary: summary),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('صندوق إكراميات العاملين (Tips Pool):'), findsOneWidget);
      expect(find.text('35.00 ج.م'), findsOneWidget);
    });

    test('4. KitchenWasteAuditService computes financial loss and aggregates by reason', () async {
      final now = DateTime.now();

      const prodId = 'prod_waste_test_1';
      const varId = 'var_waste_test_1';
      await db.into(db.products).insertOnConflictUpdate(
        ProductsCompanion.insert(
          id: prodId,
          branchId: 'b1',
          categoryId: 'cat_waste_1',
          name: 'لحم بقري مفروم',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.productVariants).insertOnConflictUpdate(
        ProductVariantsCompanion.insert(
          id: varId,
          branchId: 'b1',
          productId: prodId,
          sku: 'RAW-BEEF-01',
          size: '1 كجم',
          color: 'طازج',
          costPrice: 40000, // 400 EGP per kg
          sellPrice: 50000,
          quantity: const drift.Value(20),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.into(db.inventoryLogs).insert(
        InventoryLogsCompanion.insert(
          id: 'log_waste_1',
          branchId: 'b1',
          variantId: varId,
          type: 'waste',
          qtyDelta: -2, // 2 kg wasted
          refType: 'kitchen_waste',
          reason: const drift.Value('احتراق طهي - هالك مطبخ'),
          userId: 'u1',
          createdAt: now,
        ),
      );

      await db.into(db.inventoryLogs).insert(
        InventoryLogsCompanion.insert(
          id: 'log_waste_2',
          branchId: 'b1',
          variantId: varId,
          type: 'waste',
          qtyDelta: -1, // 1 kg wasted
          refType: 'kitchen_waste',
          reason: const drift.Value('سوء تخزين وتبريد - هالك مطبخ'),
          userId: 'u1',
          createdAt: now,
        ),
      );

      final service = KitchenWasteAuditService(db);
      final report = await service.auditKitchenWaste();

      // Total loss: (2 kg * 400 EGP) + (1 kg * 400 EGP) = 1200 EGP = 120000 piasters
      expect(report.totalLossPiasters, equals(120000));
      expect(report.totalQuantityWasted, equals(3));

      final cookingBurn = report.breakdown.firstWhere((b) => b.reason == 'احتراق طهي');
      expect(cookingBurn.totalLossPiasters, equals(80000));
      expect(cookingBurn.percentage, closeTo(66.6, 0.5));

      final storageIssue = report.breakdown.firstWhere((b) => b.reason == 'سوء تخزين وتبريد');
      expect(storageIssue.totalLossPiasters, equals(40000));
      expect(storageIssue.percentage, closeTo(33.3, 0.5));
    });

    testWidgets('5. KitchenWasteAuditDialog renders financial loss KPI card and breakdown bars', (tester) async {
      final now = DateTime.now();
      await tester.runAsync(() async {
        await db.into(db.products).insertOnConflictUpdate(
          ProductsCompanion.insert(
            id: 'p_dlg_1',
            branchId: 'b1',
            categoryId: 'c1',
            name: 'خبز برجر',
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.into(db.productVariants).insertOnConflictUpdate(
          ProductVariantsCompanion.insert(
            id: 'v_dlg_1',
            branchId: 'b1',
            productId: 'p_dlg_1',
            sku: 'RAW-BUN-01',
            size: 'قطعة',
            color: 'طازج',
            costPrice: 500, // 5 EGP
            sellPrice: 1000,
            quantity: const drift.Value(50),
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.into(db.inventoryLogs).insert(
          InventoryLogsCompanion.insert(
            id: 'log_dlg_1',
            branchId: 'b1',
            variantId: 'v_dlg_1',
            type: 'waste',
            qtyDelta: -10,
            refType: 'kitchen_waste',
            reason: const drift.Value('انتهاء صلاحية - هالك مطبخ'),
            userId: 'u1',
            createdAt: now,
          ),
        );
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: KitchenWasteAuditDialog(),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('تقرير وتدقيق تكلفة هالك المطبخ'), findsOneWidget);
      expect(find.text('إجمالي الخسائر المالية للهالك'), findsOneWidget);
      expect(find.text('50.00 ج.م'), findsOneWidget);
    });
  });
}
