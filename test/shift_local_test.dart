import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter txWriter;
  late ShiftLocalDataSource dataSource;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    txWriter = TxWriter(db);
    dataSource = ShiftLocalDataSourceImpl(db, branchProvider, txWriter);
  });

  tearDown(() async {
    await db.close();
  });

  group('Shift Lifecycle & Calculations Tests', () {
    test('openShift creates shift row and marks it active', () async {
      final shift = await dataSource.openShift(
        openingBalance: 50000, // 500 EGP
        cashierId: 'cashier_101',
        cashierName: 'أحمد كاشير',
      );

      expect(shift.openingBalance, 50000);
      expect(shift.cashierId, 'cashier_101');
      expect(shift.isOpen, isTrue);
      expect(shift.closedAt, isNull);

      final active = await dataSource.getActiveShift();
      expect(active, isNotNull);
      expect(active!.id, shift.id);
      expect(active.openingBalance, 50000);

      // Verify Drift DB state directly
      final rows = await db.select(db.shifts).get();
      expect(rows.length, 1);
      expect(rows.first.id, shift.id);
      expect(rows.first.openingBalance, 50000);
      expect(rows.first.closedAt, isNull);
    });

    test('openShift prevents opening a second shift while one is active', () async {
      await dataSource.openShift(
        openingBalance: 20000,
        cashierId: 'cashier_1',
      );

      // Attempting to open another shift must throw an Exception
      expect(
        () async => await dataSource.openShift(
          openingBalance: 10000,
          cashierId: 'cashier_2',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('closeShift accurately calculates expectedBalance and difference with cash sales, card sales, returns, and expenses', () async {
      const cashierId = 'cashier_salma';
      final branchId = await branchProvider.getBranchId();

      // 1. Open shift with 100.00 EGP (10,000 piasters)
      final shift = await dataSource.openShift(
        openingBalance: 10000,
        cashierId: cashierId,
        cashierName: 'سلمى',
      );

      // Use the exact openedAt timestamp from the shift to guarantee deterministic time-window queries across all timezones
      final shiftTime = shift.openedAt;

      // 2. Insert Cash Sale: 250.00 EGP (25,000 piasters)
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: 'sale_cash_1',
          branchId: branchId,
          shortRef: 'S901',
          cashierId: cashierId,
          shiftId: Value(shift.id),
          subtotal: 25000,
          discountType: 'none',
          total: 25000,
          paymentMethod: 'cash',
          date: shiftTime,
          createdAt: shiftTime,
          updatedAt: shiftTime,
        ),
      );

      // 3. Insert Card Sale (Visa): 150.00 EGP (15,000 piasters) -> Should NOT add to expected cash in drawer
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: 'sale_card_1',
          branchId: branchId,
          shortRef: 'S902',
          cashierId: cashierId,
          shiftId: Value(shift.id),
          subtotal: 15000,
          discountType: 'none',
          total: 15000,
          paymentMethod: 'card',
          date: shiftTime,
          createdAt: shiftTime,
          updatedAt: shiftTime,
        ),
      );

      // 4. Insert Cash Return: 50.00 EGP (5,000 piasters) -> Reduces cash in drawer
      await db.into(db.returns).insert(
        ReturnsCompanion.insert(
          id: 'return_cash_1',
          branchId: branchId,
          cashierId: cashierId,
          refundAmount: 5000,
          reason: 'مقاس غير مناسب',
          paymentMethod: 'cash',
          date: shiftTime,
          createdAt: shiftTime,
          updatedAt: shiftTime,
        ),
      );

      // 5. Insert Cash Expense from drawer: 20.00 EGP (2,000 piasters) -> Reduces cash in drawer
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: 'exp_1',
          branchId: branchId,
          category: 'بوفيه وضيافة',
          amount: 2000,
          userId: cashierId,
          expenseDate: shiftTime,
          createdAt: shiftTime,
          updatedAt: shiftTime,
        ),
      );

      // Expected Cash = Opening(10,000) + CashSales(25,000) - Returns(5,000) - Expenses(2,000) = 28,000 piasters (280 EGP)
      final summaryBeforeClose = await dataSource.getShiftSummary(shift.id);
      expect(
        summaryBeforeClose.cashSales,
        25000,
        reason: 'Expected cashSales=25000, got ${summaryBeforeClose.cashSales}',
      );
      expect(
        summaryBeforeClose.cardSales,
        15000,
        reason: 'Expected cardSales=15000, got ${summaryBeforeClose.cardSales}',
      );
      expect(
        summaryBeforeClose.cashReturns,
        5000,
        reason: 'Expected cashReturns=5000, got ${summaryBeforeClose.cashReturns}',
      );
      expect(
        summaryBeforeClose.cashExpenses,
        2000,
        reason: 'Expected cashExpenses=2000, got ${summaryBeforeClose.cashExpenses}',
      );
      expect(
        summaryBeforeClose.expectedCashInDrawer,
        28000,
        reason: 'Expected in drawer=28000, got ${summaryBeforeClose.expectedCashInDrawer} (Opening: ${shift.openingBalance}, CashSales: ${summaryBeforeClose.cashSales}, Returns: ${summaryBeforeClose.cashReturns}, Expenses: ${summaryBeforeClose.cashExpenses})',
      );

      // 6. Close Shift with counted cash: 300.00 EGP (30,000 piasters) -> Surplus of +20.00 EGP (+2,000 piasters)
      final closedShift = await dataSource.closeShift(
        countedBalance: 30000,
        shiftId: shift.id,
        userId: cashierId,
      );

      expect(closedShift.isOpen, isFalse, reason: 'Shift should be closed');
      expect(closedShift.closedAt, isNotNull, reason: 'closedAt should be set');
      expect(
        closedShift.expectedBalance,
        28000,
        reason: 'Expected balance=28000, got ${closedShift.expectedBalance}',
      );
      expect(
        closedShift.countedBalance,
        30000,
        reason: 'Counted balance=30000, got ${closedShift.countedBalance}',
      );
      expect(
        closedShift.difference,
        2000,
        reason: 'Expected difference=+2000 (surplus), got ${closedShift.difference}',
      ); // 30,000 - 28,000 = +2,000 (زيادة)

      // Active shift must now be null
      final active = await dataSource.getActiveShift();
      expect(active, isNull, reason: 'Active shift should be null after close');
    });

    test('shifts_enabled toggle persists correctly and defaults to true', () async {
      // Default state when nothing in app_meta
      final defaultEnabled = await dataSource.isShiftsEnabled();
      expect(defaultEnabled, isTrue);

      // Disable shifts
      await dataSource.setShiftsEnabled(false);
      final disabledState = await dataSource.isShiftsEnabled();
      expect(disabledState, isFalse);

      // Re-enable shifts
      await dataSource.setShiftsEnabled(true);
      final enabledState = await dataSource.isShiftsEnabled();
      expect(enabledState, isTrue);
    });
  });
}
