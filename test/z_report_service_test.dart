import 'package:clothes_erp/features/shifts/domain/entities/shift_entity.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/services/z_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testShift = ShiftEntity(
    id: 'test-shift-12345678',
    branchId: 'branch-1',
    cashierId: 'user-1',
    cashierName: 'أحمد محمود',
    openedAt: DateTime(2026, 11, 19, 10, 0),
    closedAt: DateTime(2026, 11, 19, 22, 0),
    openingBalance: 50000, // 500.00 EGP
    countedBalance: 250000, // 2500.00 EGP
    expectedBalance: 250000, // 2500.00 EGP
    difference: 0,
    createdAt: DateTime(2026, 11, 19, 10, 0),
    updatedAt: DateTime(2026, 11, 19, 22, 0),
  );

  final testSummary = ShiftSummaryEntity(
    shift: testShift,
    cashSales: 180000, // 1800.00 EGP
    cardSales: 70000, // 700.00 EGP
    otherSales: 0,
    cashReturns: 10000, // 100.00 EGP
    cashExpenses: 20000, // 200.00 EGP
    cashInstallments: 50000, // 500.00 EGP
    cardInstallments: 0,
    totalSalesCount: 15,
    expectedCashInDrawer: 250000, // 500 + 1800 + 500 - 100 - 200 = 2500 EGP
  );

  group('ZReportService', () {
    test('generateWhatsAppText produces accurate pre-formatted text', () {
      final text = ZReportService.generateWhatsAppText(testSummary);

      expect(text, contains('تقرير إغلاق الوردية (Z-Report)'));
      expect(text, contains('أحمد محمود'));
      expect(text, contains('1800.00 ج.م')); // Cash sales
      expect(text, contains('700.00 ج.م')); // Card sales
      expect(text, contains('2500.00 ج.م')); // Total revenue
      expect(text, contains('15 فاتورة')); // Sales count
      expect(text, contains('500.00 ج.م')); // Opening balance
      expect(text, contains('2500.00 ج.م')); // Expected & counted
      expect(text, contains('مطابق تماماً 100%'));
    });

    test('generateWhatsAppText handles cash deficit correctly', () {
      final deficitShift = ShiftEntity(
        id: testShift.id,
        branchId: testShift.branchId,
        cashierId: testShift.cashierId,
        cashierName: testShift.cashierName,
        openedAt: testShift.openedAt,
        closedAt: testShift.closedAt,
        openingBalance: testShift.openingBalance,
        countedBalance: 240000, // 100 EGP short
        expectedBalance: 250000,
        difference: -10000,
        createdAt: testShift.createdAt,
        updatedAt: testShift.updatedAt,
      );
      final deficitSummary = ShiftSummaryEntity(
        shift: deficitShift,
        cashSales: testSummary.cashSales,
        cardSales: testSummary.cardSales,
        otherSales: 0,
        cashReturns: testSummary.cashReturns,
        cashExpenses: testSummary.cashExpenses,
        totalSalesCount: 10,
        expectedCashInDrawer: 250000,
      );

      final text = ZReportService.generateWhatsAppText(deficitSummary);
      expect(text, contains('عجز'));
      expect(text, contains('100.00 ج.م'));
    });

    test('generateThermalPdf produces valid non-empty byte buffer', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await ZReportService.generateThermalPdf(testSummary);
      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // Valid PDF begins with %PDF-
      expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
    });

    test('generateA4Pdf produces valid non-empty byte buffer', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await ZReportService.generateA4Pdf(testSummary);
      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
    });
  });
}
