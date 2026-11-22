import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/utils/money.dart';
import 'package:clothes_erp/core/services/crash_logger_service.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/crash_logs/presentation/screens/crash_logs_screen.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Task 12.4: Arabic-Indic Digits Normalization in Money', () {
    test('Money.normalizeDigits converts all Arabic-Indic digits to ASCII', () {
      const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
      expect(Money.normalizeDigits(arabicDigits), equals('0123456789'));
    });

    test('Money.normalizeDigits leaves standard ASCII digits and symbols unchanged', () {
      const asciiText = '12345.6789 LE';
      expect(Money.normalizeDigits(asciiText), equals('12345.6789 LE'));
    });

    test('Money.normalizeDigits correctly converts mixed Arabic digits and text', () {
      const mixedText = 'خصم بقيمة ٥٠.٧٥ جنيه';
      expect(Money.normalizeDigits(mixedText), equals('خصم بقيمة 50.75 جنيه'));
    });

    test('Money.fromString handles Arabic-Indic digits accurately without parsing failure', () {
      final moneyFifty = Money.fromString('٥٠');
      expect(moneyFifty.piasters, equals(5000));
      expect(moneyFifty.toDisplay(), equals('50.00'));

      final moneyDecimal = Money.fromString('١٥.٧٥');
      expect(moneyDecimal.piasters, equals(1575));
      expect(moneyDecimal.toDisplay(), equals('15.75'));

      final moneyZeroHalf = Money.fromString('٠.٥');
      expect(moneyZeroHalf.piasters, equals(50));
      expect(moneyZeroHalf.toDisplay(), equals('0.50'));
    });
  });

  group('Task 12.3: Support Diagnostic Export Service', () {
    test('CrashLoggerService.generateDiagnosticReport generates structured diagnostic info', () async {
      final report = await CrashLoggerService.generateDiagnosticReport();

      expect(report, contains('تقرير الدعم الفني والتشخيص الشامل'));
      expect(report, contains('BAY3AH ERP'));
      expect(report, contains('بيئة التشغيل:'));
      expect(report, contains('Dart/Flutter Runtime:'));
      expect(report, contains('مسار البرنامج:'));
    });

    testWidgets('CrashLogsScreen displays export diagnostic report button for admin', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final adminUser = UserModel(
        id: 'admin_1',
        name: 'System Admin',
        email: 'admin@bay3ah.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>(
            create: (_) => _FakeAuthCubit(adminUser),
            child: const CrashLogsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final exportButtonFinder = find.byKey(const Key('export_diagnostic_report_button'));
      expect(exportButtonFinder, findsOneWidget);
      expect(find.text('تصدير تقرير الدعم الفني'), findsOneWidget);
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    });
  });

  group('Task 12.5: Windows Single-Instance Mutex Enforcement', () {
    test('windows/runner/main.cpp enforces single-instance named mutex and foreground window restore', () {
      final mainCppFile = File('windows/runner/main.cpp');
      expect(mainCppFile.existsSync(), isTrue);

      final content = mainCppFile.readAsStringSync();
      expect(content, contains('Bay3ah_ERP_Single_Instance_Mutex'));
      expect(content, contains('ERROR_ALREADY_EXISTS'));
      expect(content, contains('SW_RESTORE'));
      expect(content, contains('SetForegroundWindow'));
      expect(content, contains('ReleaseMutex'));
    });
  });
}
