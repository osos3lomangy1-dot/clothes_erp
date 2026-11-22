import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_entity.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:clothes_erp/features/shifts/presentation/widgets/close_shift_dialog.dart';
import 'package:clothes_erp/features/shifts/presentation/widgets/z_report_dialog.dart';

class _FakeLocalBackupService extends Fake implements LocalBackupService {
  int backupCalls = 0;
  String? lastUserId;
  bool shouldThrow = false;

  @override
  Future<BackupResult> createBackup({
    String? targetFilePath,
    String userId = 'system',
    bool updateMetadata = true,
  }) async {
    backupCalls++;
    lastUserId = userId;
    if (shouldThrow) {
      throw Exception('Simulated disk error');
    }
    return BackupResult(
      filePath: '/backups/sales_erp_test.sqlite',
      sizeBytes: 2048,
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  late ShiftSummaryEntity dummySummary;
  late _FakeLocalBackupService fakeBackupService;

  setUp(() {
    final shift = ShiftEntity(
      id: 'shift_test_12_1',
      branchId: 'branch_main',
      cashierId: 'cashier_test_user',
      cashierName: 'أحمد كاشير',
      openedAt: DateTime(2026, 11, 22, 9, 0),
      openingBalance: 10000, // 100.00 EGP
      expectedBalance: 30000,
      countedBalance: 30000,
      difference: 0,
      createdAt: DateTime(2026, 11, 22, 9, 0),
      updatedAt: DateTime(2026, 11, 22, 9, 0),
    );

    dummySummary = ShiftSummaryEntity(
      shift: shift,
      cashSales: 20000, // 200.00 EGP
      cardSales: 5000,
      otherSales: 0,
      cashReturns: 0,
      cashExpenses: 0,
      cashInstallments: 0,
      cardInstallments: 0,
      totalSalesCount: 10,
      expectedCashInDrawer: 30000, // 300.00 EGP
    );

    fakeBackupService = _FakeLocalBackupService();
    if (getIt.isRegistered<LocalBackupService>()) {
      getIt.unregister<LocalBackupService>();
    }
  });

  tearDown(() {
    if (getIt.isRegistered<LocalBackupService>()) {
      getIt.unregister<LocalBackupService>();
    }
  });

  group('Task 12.1 - Auto-Backup on Shift Close Tests', () {
    testWidgets('closing shift successfully calls LocalBackupService.createBackup asynchronously', (tester) async {
      getIt.registerSingleton<LocalBackupService>(fakeBackupService);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloseShiftDialog(
              summary: dummySummary,
              isBlindClosing: false,
              onClose: (_) async => null, // null indicates success
            ),
          ),
        ),
      );

      // Verify button is present
      final confirmButtonFinder = find.widgetWithText(ElevatedButton, 'إغلاق الوردية نهائياً');
      expect(confirmButtonFinder, findsOneWidget);

      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      // Verify backup was called with the cashier ID
      expect(fakeBackupService.backupCalls, 1);
      expect(fakeBackupService.lastUserId, 'cashier_test_user');
    });

    testWidgets('backup failure does not block shift closing', (tester) async {
      fakeBackupService.shouldThrow = true;
      getIt.registerSingleton<LocalBackupService>(fakeBackupService);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloseShiftDialog(
              summary: dummySummary,
              isBlindClosing: false,
              onClose: (_) async => null,
            ),
          ),
        ),
      );

      final confirmButtonFinder = find.widgetWithText(ElevatedButton, 'إغلاق الوردية نهائياً');
      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      // Even with throw, backup was invoked and catchError handled it safely
      expect(fakeBackupService.backupCalls, 1);
      // Dialog closed without unhandled exception
      expect(find.byType(CloseShiftDialog), findsNothing);
    });

    testWidgets('shift closes normally when LocalBackupService is not registered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloseShiftDialog(
              summary: dummySummary,
              isBlindClosing: false,
              onClose: (_) async => null,
            ),
          ),
        ),
      );

      final confirmButtonFinder = find.widgetWithText(ElevatedButton, 'إغلاق الوردية نهائياً');
      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(find.byType(CloseShiftDialog), findsNothing);
    });
  });

  group('Task 12.1 - Z-Report Dialog Auto-Backup Badge Tests', () {
    testWidgets('renders security badge confirming automatic database backup', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZReportDialog(summary: dummySummary),
          ),
        ),
      );

      // Verify badge text
      expect(find.text('تم إنشاء نسخة احتياطية آمنة لقاعدة البيانات تلقائياً'), findsOneWidget);

      // Verify shield icon
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });
  });
}
