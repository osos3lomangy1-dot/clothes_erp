import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:clothes_erp/features/customers/data/services/customer_ledger_service.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/customers/presentation/widgets/customer_profile_dialog.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter tx;
  late CustomersLocalDataSourceImpl dataSource;
  late CustomerLedgerService ledgerService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    tx = TxWriter(db);
    dataSource = CustomersLocalDataSourceImpl(db, branchProvider, tx);
    ledgerService = CustomerLedgerService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CustomersLocalDataSource — Validation & Integrity', () {
    test('blocks duplicate active phone and reactivates soft-deleted phone cleanly', () async {
      await dataSource.addCustomer(
        name: 'أحمد حسن',
        phone: '01012345678',
        customerType: 'retail',
        discountPercent: 5,
      );

      // Duplicate active phone should throw clear Arabic error
      await expectLater(
        dataSource.addCustomer(
          name: 'عميل آخر',
          phone: '01012345678',
        ),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains('مسجّل بالفعل'),
          ),
        ),
      );

      // Soft delete customer
      final existing = await dataSource.getCustomerByPhone('01012345678');
      expect(existing, isNotNull);
      await dataSource.softDeleteCustomer(existing!.id);
      expect(await dataSource.getCustomerByPhone('01012345678'), isNull);

      // Re-adding same phone reactivates cleanly instead of UNIQUE crash
      await dataSource.addCustomer(
        name: 'أحمد حسن (مُعاد)',
        phone: '01012345678',
        customerType: 'vip',
        discountPercent: 10,
      );
      final restored = await dataSource.getCustomerByPhone('01012345678');
      expect(restored, isNotNull);
      expect(restored!.name, 'أحمد حسن (مُعاد)');
      expect(restored.customerType, 'vip');
      expect(restored.discountPercent, 10);
    });

    test('rejects invalid discountPercent and negative loyaltyPoints', () async {
      await expectLater(
        dataSource.addCustomer(
          name: 'تجربة',
          phone: '01100001111',
          discountPercent: 150,
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        dataSource.addCustomer(
          name: 'تجربة',
          phone: '01100001111',
          loyaltyPoints: -10,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('blocks deleting customer with active installment contract', () async {
      final now = DateTime(2026, 6, 1);
      await dataSource.addCustomer(
        name: 'عميل تقسيط',
        phone: '01299998888',
      );
      final cust = (await dataSource.getCustomerByPhone('01299998888'))!;

      await db.into(db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: 'inst-1',
              branchId: 'b1',
              saleId: 'sale-1',
              customerId: cust.id,
              totalPiasters: 100000,
              downPaymentPiasters: const drift.Value(20000),
              principalPiasters: 80000,
              interestBp: 0,
              monthlyAmountPiasters: 20000,
              remainingPiasters: 60000,
              durationMonths: 4,
              startDate: now,
              endDate: DateTime(2026, 10, 1),
              status: const drift.Value('active'),
              createdBy: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await expectLater(
        dataSource.softDeleteCustomer(cust.id),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains('عقد تقسيط نشط'),
          ),
        ),
      );
    });
  });

  group('CustomerLedgerService — Summaries, Statement, WhatsApp & Excel', () {
    test('aggregates completed sales, active installments, loyalty logs, and exports Excel', () async {
      final now = DateTime(2026, 6, 10, 12, 0);
      await dataSource.addCustomer(
        name: 'سارة علي',
        phone: '01055556666',
        customerType: 'wholesale',
        loyaltyPoints: 40,
      );
      final cust = (await dataSource.getCustomerByPhone('01055556666'))!;

      // Completed sale + Cancelled sale (should be excluded from spend)
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's1',
              branchId: 'b1',
              shortRef: 'INV-101',
              cashierId: 'admin',
              customerId: drift.Value(cust.id),
              subtotal: 50000,
              discountType: 'none',
              total: 50000,
              paymentMethod: 'cash',
              status: const drift.Value('completed'),
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's2',
              branchId: 'b1',
              shortRef: 'INV-102',
              cashierId: 'admin',
              customerId: drift.Value(cust.id),
              subtotal: 30000,
              discountType: 'none',
              total: 30000,
              paymentMethod: 'cash',
              status: const drift.Value('cancelled'),
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: 'inst-2',
              branchId: 'b1',
              saleId: 's1',
              customerId: cust.id,
              totalPiasters: 100000,
              downPaymentPiasters: const drift.Value(20000),
              principalPiasters: 80000,
              interestBp: 0,
              monthlyAmountPiasters: 20000,
              remainingPiasters: 40000,
              durationMonths: 4,
              startDate: now,
              endDate: DateTime(2026, 10, 10),
              createdBy: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.loyaltyTransactions).insert(
            LoyaltyTransactionsCompanion.insert(
              id: 'l1',
              branchId: 'b1',
              customerId: cust.id,
              pointsDelta: 40,
              reason: 'مكافأة فاتورة INV-101',
              createdAt: now,
            ),
          );

      final summaries = await ledgerService.getAllCustomerSummaries();
      expect(summaries[cust.id]?.invoiceCount, 1);
      expect(summaries[cust.id]?.totalSpentPiasters, 50000);
      expect(summaries[cust.id]?.activeInstallmentsCount, 1);
      expect(summaries[cust.id]?.installmentsRemainingPiasters, 40000);

      final st = await ledgerService.getCustomerStatement(cust.id);
      expect(st.sales.length, 2);
      expect(st.installments.length, 1);
      expect(st.loyaltyLogs.length, 1);

      // WhatsApp normalization for Egyptian phone
      expect(
        CustomerLedgerService.buildWhatsAppUri('01055556666').toString(),
        'https://wa.me/201055556666',
      );

      // Excel export decodes cleanly
      final entity = CustomerEntity(
        id: cust.id,
        name: cust.name,
        phone: cust.phone,
        loyaltyPoints: cust.loyaltyPoints,
        customerType: cust.customerType,
        createdAt: cust.createdAt,
      );
      final bytes = ledgerService.buildCustomersExcelBytes([entity], summaries);
      final decoded = Excel.decodeBytes(bytes);
      expect(decoded.tables.containsKey('سجل_العملاء'), isTrue);
      expect(decoded.tables['سجل_العملاء']!.rows.length, 2);
    });
  });

  group('CustomerProfileDialog Widget Test', () {
    testWidgets('renders customer statement KPIs and 3 tabs cleanly in RTL', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await dataSource.addCustomer(
        name: 'عميل اختبار',
        phone: '01011223344',
        loyaltyPoints: 25,
      );
      final cust = (await dataSource.getCustomerByPhone('01011223344'))!;
      final entity = CustomerEntity(
        id: cust.id,
        name: cust.name,
        phone: cust.phone,
        loyaltyPoints: cust.loyaltyPoints,
        createdAt: cust.createdAt,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showCustomerProfileDialog(
                    context,
                    customer: entity,
                    ledgerOverride: ledgerService,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('عميل اختبار'), findsOneWidget);
      expect(find.text('واتساب'), findsOneWidget);
      expect(find.text('إجمالي المشتريات'), findsOneWidget);
      expect(find.text('الفواتير (0)'), findsOneWidget);
      expect(find.text('سداد الآجل (0)'), findsOneWidget);
      expect(find.text('نقاط الولاء (0)'), findsOneWidget);
    });
  });
}

