import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_entity.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/services/z_report_service.dart';
import 'package:clothes_erp/features/shifts/presentation/widgets/close_shift_dialog.dart';

void main() {
  group('Task 11.3 - Blind Shift Closing in CloseShiftDialog Tests', () {
    late ShiftSummaryEntity dummySummary;

    setUp(() {
      final shift = ShiftEntity(
        id: 'shift_test_01',
        branchId: 'branch_main',
        cashierId: 'cashier_01',
        cashierName: 'محمود كاشير',
        openedAt: DateTime(2026, 11, 22, 9, 0),
        openingBalance: 20000, // 200.00 EGP
        createdAt: DateTime(2026, 11, 22, 9, 0),
        updatedAt: DateTime(2026, 11, 22, 9, 0),
      );

      dummySummary = ShiftSummaryEntity(
        shift: shift,
        cashSales: 50000, // 500.00 EGP
        cardSales: 30000, // 300.00 EGP
        otherSales: 0,
        cashReturns: 5000, // 50.00 EGP
        cashExpenses: 5000, // 50.00 EGP
        cashInstallments: 10000, // 100.00 EGP
        cardInstallments: 0,
        totalSalesCount: 15,
        expectedCashInDrawer: 70000, // 200 + 500 + 100 - 50 - 50 = 700.00 EGP
      );
    });

    testWidgets('blind shift closing starts with empty input and hides expected breakdown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloseShiftDialog(
              summary: dummySummary,
              isBlindClosing: true,
              onClose: (_) async => true,
            ),
          ),
        ),
      );

      // Verify that the blind closing notification is displayed
      expect(find.text('نظام الجرد الأعمى مفعّل'), findsOneWidget);
      // Verify that expected cash breakdown label is hidden
      expect(find.text('المبلغ المتوقع في الدرج:'), findsNothing);

      // Verify that text field is empty
      final textFieldFinder = find.byType(TextFormField);
      expect(textFieldFinder, findsOneWidget);
      final textFormField = tester.widget<TextFormField>(textFieldFinder);
      expect(textFormField.controller?.text, isEmpty);

      // Verify prompt label before input
      expect(find.text('يرجى كتابة رصيد الدرج المعدود لاحتساب المطابقة الرقابية'), findsOneWidget);

      // Enter matching cash: 700
      await tester.enterText(textFieldFinder, '700');
      await tester.pump();
      expect(find.textContaining('[مطابق]'), findsOneWidget);

      // Enter shortage cash: 650 (short by 50)
      await tester.enterText(textFieldFinder, '650');
      await tester.pump();
      expect(find.textContaining('[عجز بالسالب]'), findsOneWidget);

      // Enter surplus cash: 750 (surplus of 50)
      await tester.enterText(textFieldFinder, '750');
      await tester.pump();
      expect(find.textContaining('[فائض بالموجب]'), findsOneWidget);
    });

    testWidgets('standard shift closing prefills expected cash and displays full breakdown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloseShiftDialog(
              summary: dummySummary,
              isBlindClosing: false,
              onClose: (_) async => true,
            ),
          ),
        ),
      );

      // Expected breakdown is visible
      expect(find.text('المبلغ المتوقع في الدرج:'), findsOneWidget);
      expect(find.text('الرصيد الافتتاحي (الفكة):'), findsOneWidget);

      // Prefilled with 700.00
      final textFieldFinder = find.byType(TextFormField);
      final textFormField = tester.widget<TextFormField>(textFieldFinder);
      expect(textFormField.controller?.text, '700.00');

      // Matching status is shown immediately
      expect(find.textContaining('[مطابق]'), findsOneWidget);
    });
  });

  group('Task 11.3 - Thermal Z-Report Service Tests', () {
    test('generateThermalPdf produces valid non-empty byte buffer with all report fields', () async {
      final shift = ShiftEntity(
        id: 'shift_z_001',
        branchId: 'branch_1',
        cashierId: 'cashier_ali',
        cashierName: 'علي حسن',
        openedAt: DateTime(2026, 11, 22, 8, 30),
        closedAt: DateTime(2026, 11, 22, 17, 0),
        openingBalance: 30000, // 300 EGP
        countedBalance: 95000, // 950 EGP
        difference: 0,
        createdAt: DateTime(2026, 11, 22, 8, 30),
        updatedAt: DateTime(2026, 11, 22, 17, 0),
      );

      final summary = ShiftSummaryEntity(
        shift: shift,
        cashSales: 60000,
        cardSales: 40000,
        otherSales: 0,
        cashReturns: 5000,
        cashExpenses: 5000,
        cashInstallments: 15000,
        cardInstallments: 5000,
        totalSalesCount: 22,
        expectedCashInDrawer: 95000,
      );

      final bytes = await ZReportService.generateThermalPdf(summary);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));
    });
  });
}
