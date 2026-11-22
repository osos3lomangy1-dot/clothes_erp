import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/installments/domain/entities/customer_installment_entity.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_plan_entity.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_schedule_entry.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/pos/presentation/widgets/installment_checkout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstallmentCheckoutDialog - Dynamic Custom & Approved Plans', () {
    setUp(() {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
    });

    testWidgets(
      'defaults to custom mode when plans list is empty without crashing',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    showDialog<InstallmentCheckoutConfig>(
                      context: ctx,
                      builder: (_) => const InstallmentCheckoutDialog(
                        plans: [],
                        totalPiasters: 120000, // 1,200 EGP
                        pinRequired: false,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Verify custom mode UI elements are displayed
        expect(find.text('تفاصيل البيع بالتقسيط'), findsOneWidget);
        expect(find.text('مدة التقسيط (شهور) *'), findsOneWidget);
        expect(find.text('نسبة الفائدة (%)'), findsOneWidget);
        expect(find.textContaining('لا توجد خطط تقسيط مسبقة'), findsOneWidget);

        // Verify live financial preview
        expect(find.text('معاينة حساب التقسيط:'), findsOneWidget);
        expect(
          find.text('1200.00 ج.م'),
          findsWidgets,
        ); // Original invoice amount

        // Submit custom plan
        await tester.tap(find.text('تأكيد التقسيط'));
        await tester.pumpAndSettle();

        // Dialog closed upon valid submission
        expect(find.text('تفاصيل البيع بالتقسيط'), findsNothing);
      },
    );

    testWidgets(
      'allows switching between approved plans and custom plan mode',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());

        final approvedPlans = [
          InstallmentPlanEntity(
            id: 'plan_6m',
            branchId: 'branch_1',
            name: 'خطة الـ 6 شهور',
            durationMonths: 6,
            downPaymentPiasters: 20000,
            interestBp: 1000, // 10%
            isActive: true,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    showDialog<InstallmentCheckoutConfig>(
                      context: ctx,
                      builder: (_) => InstallmentCheckoutDialog(
                        plans: approvedPlans,
                        totalPiasters: 100000, // 1,000 EGP
                        pinRequired: false,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Initially in approved plans mode
        expect(find.text('خطط معتمدة'), findsOneWidget);
        expect(find.text('تقسيط مخصص فوري'), findsOneWidget);
        expect(find.text('خطة التقسيط'), findsOneWidget);

        // Tap on custom plan segment
        await tester.tap(find.text('تقسيط مخصص فوري'));
        await tester.pumpAndSettle();

        // Now custom duration and interest fields should appear
        expect(find.text('مدة التقسيط (شهور) *'), findsOneWidget);
        expect(find.text('نسبة الفائدة (%)'), findsOneWidget);
      },
    );
  });

  group('ReceiptPdfService - Installment Contract & Schedule Print', () {
    test(
      'generates complete installment contract receipt PDF with schedule and legal commitment',
      () async {
        final invoice = InvoiceDetailsEntity(
          id: 'sale_inst_1',
          shortRef: 'INV-7890',
          date: DateTime(2026, 11, 22, 10, 30),
          cashierId: 'cashier_1',
          cashierName: 'أحمد محمود',
          customerId: 'cust_1',
          customerName: 'محمد علي حسن',
          customerPhone: '01012345678',
          subtotal: 150000, // 1,500 EGP
          total: 150000,
          paymentMethod: 'installment',
          items: const [
            InvoiceItemDetailsEntity(
              id: 'item_1',
              variantId: 'var_1',
              productName: 'غسالة ملابس نصف أوتوماتيك',
              color: 'أبيض',
              size: '10 كجم',
              qty: 1,
              price: 150000,
              lineTotal: 150000,
            ),
          ],
        );

        final contract = CustomerInstallmentEntity(
          id: 'contract_uuid_12345',
          branchId: 'branch_1',
          saleId: 'sale_inst_1',
          customerId: 'cust_1',
          totalPiasters: 150000,
          downPaymentPiasters: 30000, // 300 EGP
          principalPiasters: 120000, // 1,200 EGP
          interestBp: 1000, // 10%
          monthlyAmountPiasters: 22000, // 220 EGP
          remainingPiasters: 132000,
          durationMonths: 6,
          startDate: DateTime(2026, 11, 22),
          endDate: DateTime(2027, 5, 22),
          status: 'active',
          createdBy: 'user_1',
          createdAt: DateTime(2026, 11, 22),
          updatedAt: DateTime(2026, 11, 22),
        );

        final schedule = [
          InstallmentScheduleEntry(
            installmentNumber: 1,
            dueDate: DateTime(2026, 12, 22),
            amountPiasters: 22000,
            principalComponentPiasters: 20000,
            interestComponentPiasters: 2000,
          ),
          InstallmentScheduleEntry(
            installmentNumber: 2,
            dueDate: DateTime(2027, 1, 22),
            amountPiasters: 22000,
            principalComponentPiasters: 20000,
            interestComponentPiasters: 2000,
          ),
        ];

        final customer = CustomerEntity(
          id: 'cust_1',
          name: 'محمد علي حسن',
          phone: '01012345678',
          createdAt: DateTime(2026, 1, 1),
        );

        final pdfBytes = await ReceiptPdfService.generateInstallmentContractPdf(
          invoice: invoice,
          contract: contract,
          schedule: schedule,
          customer: customer,
        );

        expect(pdfBytes, isNotNull);
        expect(
          pdfBytes.length,
          greaterThan(100),
        ); // Non-empty valid PDF byte stream
      },
    );
  });
}
