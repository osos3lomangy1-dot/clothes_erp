import 'package:clothes_erp/features/installments/domain/entities/customer_installment_entity.dart';
import 'package:clothes_erp/features/installments/domain/entities/customer_installments_summary.dart';
import 'package:clothes_erp/features/installments/presentation/screens/installments_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('8. CustomerInstallmentsCard expands to show contracts on tap', (tester) async {
    final now = DateTime.now();
    final contract1 = CustomerInstallmentEntity(
      id: 'cont-11111111',
      branchId: 'b1',
      saleId: 's1',
      customerId: 'c1',
      totalPiasters: 60000,
      downPaymentPiasters: 10000,
      principalPiasters: 50000,
      interestBp: 0,
      monthlyAmountPiasters: 10000,
      remainingPiasters: 30000,
      durationMonths: 6,
      startDate: now,
      endDate: now.add(const Duration(days: 180)),
      status: 'active',
      createdBy: 'admin',
      createdAt: now,
      updatedAt: now,
    );

    final contract2 = CustomerInstallmentEntity(
      id: 'cont-22222222',
      branchId: 'b1',
      saleId: 's2',
      customerId: 'c1',
      totalPiasters: 40000,
      downPaymentPiasters: 0,
      principalPiasters: 40000,
      interestBp: 0,
      monthlyAmountPiasters: 5000,
      remainingPiasters: 20000,
      durationMonths: 8,
      startDate: now,
      endDate: now.add(const Duration(days: 240)),
      status: 'active',
      createdBy: 'admin',
      createdAt: now,
      updatedAt: now,
    );

    final summary = CustomerInstallmentsSummary(
      customerId: 'c1',
      customerName: 'محمود أحمد',
      contractsCount: 2,
      totalRemainingPiasters: 50000,
      totalMonthlyAmountPiasters: 15000,
      currentMonthDuePiasters: 15000,
      contracts: [contract1, contract2],
    );

    CustomerInstallmentEntity? tappedContract;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerInstallmentsCard(
            summary: summary,
            onContractTap: (c) => tappedContract = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial collapsed state: customer header visible, individual contracts not visible
    expect(find.text('محمود أحمد'), findsOneWidget);
    expect(find.text('2 عقود'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_rounded), findsNothing);

    // Tap on card or customer name to expand
    await tester.tap(find.text('محمود أحمد'));
    await tester.pumpAndSettle();

    // Verify expanded state: 2 contract rows appear
    expect(find.byIcon(Icons.receipt_long_rounded), findsNWidgets(2));
    expect(find.text('عقد #cont-111'), findsOneWidget);
    expect(find.text('عقد #cont-222'), findsOneWidget);

    // Tap on the first contract
    await tester.tap(find.text('عقد #cont-111'));
    await tester.pumpAndSettle();

    expect(tappedContract, isNotNull);
    expect(tappedContract!.id, 'cont-11111111');
  });
}

