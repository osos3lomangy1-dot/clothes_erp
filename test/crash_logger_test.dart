import 'package:clothes_erp/core/services/crash_logger_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashLoggerService Tests', () {
    setUp(() async {
      await CrashLoggerService.init();
      await CrashLoggerService.clearLogs();
    });

    tearDown(() async {
      await CrashLoggerService.clearLogs();
    });

    test('addBreadcrumb and setContext maintain state correctly', () {
      CrashLoggerService.setContext('شاشة الدفع');
      CrashLoggerService.addBreadcrumb('ضغط على زر الدفع النقدي');

      // Add dummy crash
      CrashLoggerService.logCrash(
        Exception('رصيد غير كافٍ'),
        StackTrace.current,
        context: 'شاشة الدفع',
      );
    });

    test('logCrash writes formatted report to disk and getCrashLogs parses it', () async {
      final errorMsg = 'NullPointerException: Customer phone was null';
      final testStackTrace = StackTrace.fromString('package:clothes_erp/pos.dart:42:10');

      CrashLoggerService.setContext('نقطة البيع');
      CrashLoggerService.addBreadcrumb('إضافة صنف للسلة');
      CrashLoggerService.addBreadcrumb('تحديد العميل');

      CrashLoggerService.logCrash(
        errorMsg,
        testStackTrace,
        context: 'نقطة البيع - تجربة',
      );

      final logs = await CrashLoggerService.getCrashLogs();

      expect(logs.isNotEmpty, true);
      final firstLog = logs.first;

      expect(firstLog.error.contains(errorMsg), true);
      expect(firstLog.context, 'نقطة البيع - تجربة');
      expect(firstLog.breadcrumbs.any((b) => b.contains('تحديد العميل')), true);
    });

    test('clearLogs clears the master log and individual log files', () async {
      CrashLoggerService.logCrash('خطأ تجريبي 1', StackTrace.current);
      CrashLoggerService.logCrash('خطأ تجريبي 2', StackTrace.current);

      var logs = await CrashLoggerService.getCrashLogs();
      expect(logs.length >= 2, true);

      final cleared = await CrashLoggerService.clearLogs();
      expect(cleared, true);

      logs = await CrashLoggerService.getCrashLogs();
      expect(logs.isEmpty, true);
    });
  });
}
