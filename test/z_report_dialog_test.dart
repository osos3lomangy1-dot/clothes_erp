import 'package:clothes_erp/features/shifts/domain/entities/shift_entity.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/widgets/z_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testShift = ShiftEntity(
    id: 'shift-abc-12345678',
    branchId: 'branch-1',
    cashierId: 'user-1',
    cashierName: 'كاشير المحل',
    openedAt: DateTime(2026, 11, 19, 9, 0),
    closedAt: DateTime(2026, 11, 19, 21, 0),
    openingBalance: 30000, // 300.00 EGP
    countedBalance: 150000, // 1500.00 EGP
    expectedBalance: 150000, // 1500.00 EGP
    difference: 0,
    createdAt: DateTime(2026, 11, 19, 9, 0),
    updatedAt: DateTime(2026, 11, 19, 21, 0),
  );

  final testSummary = ShiftSummaryEntity(
    shift: testShift,
    cashSales: 120000, // 1200.00 EGP
    cardSales: 40000, // 400.00 EGP
    otherSales: 0,
    cashReturns: 0,
    cashExpenses: 0,
    totalSalesCount: 8,
    expectedCashInDrawer: 150000,
  );

  testWidgets('renders ZReportDialog with full breakdown and action buttons', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZReportDialog(summary: testSummary),
        ),
      ),
    );

    // Verify Title & Header Info
    expect(find.text('تقرير إغلاق الوردية (Z-Report)'), findsOneWidget);
    expect(find.textContaining('كاشير المحل'), findsOneWidget);

    // Verify Sales Breakdown
    expect(find.text('مبيعات كاش'), findsOneWidget);
    expect(find.text('1200.00 ج.م'), findsOneWidget);
    expect(find.text('مبيعات فيزا'), findsOneWidget);
    expect(find.text('400.00 ج.م'), findsOneWidget);
    expect(find.text('1600.00 ج.م'), findsOneWidget); // Total revenue

    // Verify Reconciliation Banner
    expect(find.text('مطابق تماماً 100% (لا يوجد عجز أو زيادة)'), findsOneWidget);

    // Verify 3 Action Buttons
    expect(find.text('بون حراري 🖨️'), findsOneWidget);
    expect(find.text('تقرير A4 📄'), findsOneWidget);
    expect(find.text('واتساب 💬'), findsOneWidget);
  });
}
