// ignore_for_file: avoid_print
import 'dart:io';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dbPath = r'E:\flutter projects\erp systems\clothes_erp\clothes_erp_test.sqlite';

  test(
    'pre-verification v7 on store DB copy',
    () async {
      final file = File(dbPath);

      // Guard requirement: must contain "_test" to protect original
      if (!file.path.contains('_test')) {
        fail('CRITICAL SAFETY CHECK FAILED: dbPath does not contain "_test"!');
      }

      if (!await file.exists()) {
        fail('DB copy not found at $dbPath');
      }

    print('');
    print('=' * 70);
    print('DB COPY: $dbPath');
    print('FILE SIZE: ${await file.length()} bytes');

    // Instantiating AppDatabase with NativeDatabase(file) triggers Drift's onUpgrade automatically
    final db = AppDatabase(NativeDatabase(file));

    // Running a query triggers open + onUpgrade to schemaVersion 7
    await db.customSelect('SELECT 1').getSingle();

    final vAfter = await db.customSelect('PRAGMA user_version;').getSingle();
    print('SCHEMA_VERSION_AFTER: ${vAfter.data['user_version']}');

    Future<int> queryInt(String sql) async {
      final row = await db.customSelect(sql).getSingle();
      return (row.data.values.first ?? 0) as int;
    }

    final cmCount = await queryInt('SELECT COUNT(*) AS v FROM cash_movements');
    final cmSalesSum = await queryInt(
      "SELECT COALESCE(SUM(amount_piasters), 0) AS v FROM cash_movements WHERE type = 'sale' AND direction = 'in'",
    );
    final cmSupplierPaymentsSum = await queryInt(
      "SELECT COALESCE(SUM(amount_piasters), 0) AS v FROM cash_movements WHERE type = 'supplier_payment' AND direction = 'out'",
    );
    final cmPurchasePaymentsSum = await queryInt(
      "SELECT COALESCE(SUM(amount_piasters), 0) AS v FROM cash_movements WHERE type = 'purchase_payment' AND direction = 'out'",
    );
    final cmExpensesSum = await queryInt(
      "SELECT COALESCE(SUM(amount_piasters), 0) AS v FROM cash_movements WHERE type = 'expense' AND direction = 'out'",
    );
    final cmRefundsSum = await queryInt(
      "SELECT COALESCE(SUM(amount_piasters), 0) AS v FROM cash_movements WHERE type = 'refund' AND direction = 'out'",
    );
    final cmDownPaymentSum = await queryInt(
      "SELECT COALESCE(SUM(amount_piasters), 0) AS v FROM cash_movements WHERE type = 'installment_down' AND direction = 'in'",
    );

    print('AFTER CASH_MOVEMENTS_ROWS: $cmCount');
    print('AFTER CASH_MOVEMENTS_SALES_SUM: $cmSalesSum');
    print('AFTER CASH_MOVEMENTS_SUPPLIER_PAYMENTS_SUM: $cmSupplierPaymentsSum');
    print('AFTER CASH_MOVEMENTS_PURCHASE_PAYMENTS_SUM: $cmPurchasePaymentsSum');
    print('AFTER CASH_MOVEMENTS_EXPENSES_SUM: $cmExpensesSum');
    print('AFTER CASH_MOVEMENTS_REFUNDS_SUM: $cmRefundsSum');
    print('AFTER CASH_MOVEMENTS_DOWN_PAYMENT_SUM: $cmDownPaymentSum');

    // Banner check for open shift
    final banner = await getMigrationOpenShiftBannerMessage(db);
    print('MIGRATION_BANNER_MESSAGE: $banner');

    // Baseline numbers from pre-migration Python inspection:
    // Sales: 303000
    // Supplier Payments: 160000
    // Refunds: 66000
    // Operating Expenses: 10000
    // Installment Down: 5000
    print('');
    print('RECONCILIATION:');
    print('  Sales match (303000 == $cmSalesSum): ${cmSalesSum == 303000}');
    print('  Supplier payments match (160000 == $cmSupplierPaymentsSum): ${cmSupplierPaymentsSum == 160000}');
    print('  Refunds match (66000 == $cmRefundsSum): ${cmRefundsSum == 66000}');
    print('  Operating expenses match (10000 == $cmExpensesSum): ${cmExpensesSum == 10000}');
    print('  Installment down match (5000 == $cmDownPaymentSum): ${cmDownPaymentSum == 5000}');
    print('=' * 70);

    expect(vAfter.data['user_version'], isIn([7, 8]));
    expect(cmSalesSum, equals(303000));
    expect(cmSupplierPaymentsSum, equals(160000));
    expect(cmRefundsSum, equals(66000));
    expect(cmExpensesSum, equals(10000));
    expect(cmDownPaymentSum, equals(5000));
    expect(banner, isNotNull);

    await db.close();
  }, skip: !File(dbPath).existsSync());
}

