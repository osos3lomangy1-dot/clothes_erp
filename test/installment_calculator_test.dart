import 'package:clothes_erp/features/installments/domain/entities/installment_payment_entity.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_schedule_entry.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 1, 15);
  const principal = 100000; // 1000.00
  const months = 6;

  int expectedInterest(InstallmentInterestModel model, int principalP, int down, int monthsN, int value) {
    final financed = principalP - down;
    switch (model) {
      case InstallmentInterestModel.fixed:
        return value;
      case InstallmentInterestModel.percentTotal:
        return (financed * value) ~/ 10000;
      case InstallmentInterestModel.percentMonthly:
        return (financed * value * monthsN) ~/ 10000;
    }
  }

  void assertInvariants(List<InstallmentScheduleEntry> entries, int financed, int totalInterest, int n) {
    expect(entries.length, n);
    final sumInterest = entries.fold<int>(0, (s, e) => s + e.interestComponentPiasters);
    final sumPrincipal = entries.fold<int>(0, (s, e) => s + e.principalComponentPiasters);
    final sumAmount = entries.fold<int>(0, (s, e) => s + e.amountPiasters);
    expect(sumInterest, totalInterest, reason: 'sum of installment interest must equal plan total interest exactly');
    expect(sumPrincipal, financed, reason: 'sum of principal components must equal financed principal');
    expect(sumAmount, financed + totalInterest, reason: 'sum of amounts must equal financed + interest');
    for (final e in entries) {
      expect(e.amountPiasters, e.principalComponentPiasters + e.interestComponentPiasters);
    }
  }

  group('InstallmentCalculator 5 scenarios x 3 interest models (sum interest invariant)', () {
    final scenarios = <String, Map<String, int>>{
      '0% interest': {'down': 0, 'value': 0},
      '10% interest': {'down': 0, 'value': 1000}, // 10% = 1000bp or 10000 fixed
      '0 down payment': {'down': 0, 'value': 1000},
      '50% down payment': {'down': 50000, 'value': 1000},
      'rounding behavior': {'down': 0, 'value': 333}, // induces remainder
    };

    for (final model in InstallmentInterestModel.values) {
      for (final s in scenarios.entries) {
        test('${s.key} | ${model.name}', () {
          final down = s.value['down']!;
          var value = s.value['value']!;
          if (model == InstallmentInterestModel.fixed) {
            // for fixed model, value is piasters; use 0 for 0% scenario else derive 10% or rounding amount
            if (s.key == '0% interest') {
              value = 0;
            } else if (s.key == 'rounding behavior') {
              value = 1003; // odd amount to force remainder over 6 months
            } else {
              value = 10000; // fixed 100.00 interest
            }
          }
          final res = InstallmentCalculator.calculateSchedule(
            principalPiasters: principal,
            durationMonths: months,
            interestModel: model,
            interestValue: value,
            downPaymentPiasters: down,
            startDate: start,
          );
          expect(res.isRight(), isTrue, reason: 'calculation should succeed for ${s.key}/${model.name}');
          res.fold((l) => fail(l.message), (entries) {
            final financed = principal - down;
            final totalInterest = expectedInterest(model, principal, down, months, value);
            assertInvariants(entries, financed, totalInterest, months);
            for (var i = 0; i < entries.length; i++) {
              expect(entries[i].installmentNumber, i + 1);
              expect(entries[i].dueDate, DateTime(start.year, start.month + i + 1, start.day));
            }
          });
        });
      }
    }

    test('percentTotal computes interest on remaining financed amount after down payment', () {
      // Invoice = 1,000 EGP (100,000 piasters), down = 200 EGP (20,000), remaining = 800 EGP (80,000)
      // 10% interest on remaining 800 EGP = 80 EGP (8,000 piasters), NOT 100 EGP (10,000)
      final res = InstallmentCalculator.calculateSchedule(
        principalPiasters: 100000,
        durationMonths: 4,
        interestModel: InstallmentInterestModel.percentTotal,
        interestValue: 1000,
        downPaymentPiasters: 20000,
        startDate: DateTime(2026, 1, 1),
      );
      res.fold((l) => fail(l.message), (entries) {
        expect(entries.fold<int>(0, (s, e) => s + e.principalComponentPiasters), 80000);
        expect(entries.fold<int>(0, (s, e) => s + e.interestComponentPiasters), 8000);
        expect(entries.fold<int>(0, (s, e) => s + e.amountPiasters), 88000);
        expect(entries.map((e) => e.amountPiasters).toList(), [22000, 22000, 22000, 22000]);
      });
    });

    test('last installment absorbs piaster remainder explicitly', () {
      // 1000 over 3 months = 333,333,334
      final res = InstallmentCalculator.calculateSchedule(
        principalPiasters: 1000,
        durationMonths: 3,
        interestModel: InstallmentInterestModel.fixed,
        interestValue: 0,
        downPaymentPiasters: 0,
        startDate: DateTime(2026, 1, 1),
      );
      res.fold((l) => fail(l.message), (entries) {
        expect(entries.map((e) => e.amountPiasters).toList(), [333, 333, 334]);
        expect(entries.map((e) => e.principalComponentPiasters).toList(), [333, 333, 334]);
        expect(entries.fold<int>(0, (s, e) => s + e.amountPiasters), 1000);
        expect(entries.fold<int>(0, (s, e) => s + e.interestComponentPiasters), 0);
      });
    });

    test('first installment due date is next month after purchase with safe month-end clamping', () {
      final purchaseDate = DateTime(2026, 1, 31);
      final res = InstallmentCalculator.calculateSchedule(
        principalPiasters: 100000,
        durationMonths: 4,
        interestModel: InstallmentInterestModel.percentTotal,
        interestValue: 0,
        downPaymentPiasters: 20000,
        startDate: purchaseDate,
      );
      res.fold((l) => fail(l.message), (entries) {
        expect(entries[0].dueDate, DateTime(2026, 2, 28)); // next month, NOT Jan 31 and NOT Mar 3
        expect(entries[1].dueDate, DateTime(2026, 3, 31));
        expect(entries[2].dueDate, DateTime(2026, 4, 30));
        expect(entries[3].dueDate, DateTime(2026, 5, 31));
      });
    });

    test('overpayment rolls excess to LAST month(s) and keeps intermediate months full, preserving actual paidAt dates', () {
      // Invoice 1000, down 200 -> remaining 800 + 10% (80) = 880 over 4 months = 220/month
      final purchaseDate = DateTime(2026, 11, 18);
      final schedule = InstallmentCalculator.calculateSchedule(
        principalPiasters: 100000,
        durationMonths: 4,
        interestModel: InstallmentInterestModel.percentTotal,
        interestValue: 1000,
        downPaymentPiasters: 20000,
        startDate: purchaseDate,
      ).getOrElse(() => throw Exception());

      InstallmentPaymentEntity makePayment(String id, int amount, DateTime paidAt, {String? receipt}) =>
          InstallmentPaymentEntity(
            id: id,
            branchId: 'b1',
            customerInstallmentId: 'c1',
            amountPiasters: amount,
            paymentMethod: 'cash',
            paidAt: paidAt,
            receiptNumber: receipt,
            recordedBy: 'cashier',
            createdAt: paidAt,
            updatedAt: paidAt,
          );

      final earlyDate = DateTime(2026, 12, 15); // 3 days before 2026/12/18
      final lateDate = DateTime(2027, 1, 22); // 4 days after 2027/01/18

      final allocations = InstallmentCalculator.allocatePaymentsToSchedule(
        schedule: schedule,
        payments: [
          // Down payment should be ignored in schedule allocation
          makePayment('p0', 20000, purchaseDate, receipt: 'DOWN_PAYMENT'),
          // Month 1: pays 300 EGP (220 regular + 80 excess -> rolls to Month 4!)
          makePayment('p1', 30000, earlyDate),
          // Month 2: pays 400 EGP (220 regular + 180 excess -> 140 finishes Month 4, 40 rolls to Month 3!)
          makePayment('p2', 40000, lateDate),
        ],
      );

      // Month 1 (due 2026/12/18): paid 220 on 2026/12/15 (3 days early)
      expect(allocations[0].isPaid, isTrue);
      expect(allocations[0].paidRegularPiasters, 22000);
      expect(allocations[0].paidFromExcessPiasters, 0);
      expect(allocations[0].remainingPiasters, 0);
      expect(allocations[0].paidAt, earlyDate);
      expect(allocations[0].daysFromDueDate, -3);

      // Month 2 (due 2027/01/18): paid 220 on 2027/01/22 (4 days late)
      expect(allocations[1].isPaid, isTrue);
      expect(allocations[1].paidRegularPiasters, 22000);
      expect(allocations[1].paidFromExcessPiasters, 0);
      expect(allocations[1].remainingPiasters, 0);
      expect(allocations[1].paidAt, lateDate);
      expect(allocations[1].daysFromDueDate, 4);

      // Month 3 (due 2027/02/18): received 40 EGP overflow from Month 2's excess after Month 4 completed
      expect(allocations[2].isPaid, isFalse);
      expect(allocations[2].paidRegularPiasters, 0);
      expect(allocations[2].paidFromExcessPiasters, 4000);
      expect(allocations[2].remainingPiasters, 18000);
      expect(allocations[2].paidAt, lateDate);

      // Month 4 (due 2027/03/18): received 80 + 140 = 220 EGP entirely from excess -> fully paid!
      expect(allocations[3].isPaid, isTrue);
      expect(allocations[3].isPaidOnlyFromExcess, isTrue);
      expect(allocations[3].paidRegularPiasters, 0);
      expect(allocations[3].paidFromExcessPiasters, 22000);
      expect(allocations[3].remainingPiasters, 0);
      expect(allocations[3].paidAt, lateDate);
    });
  });

  group('Early Settlement Calculation', () {
    test('full waiver within 7 days removes 100% of interest and leaves only financed principal', () {
      // Invoice 1000, down 200 -> financed 800, 10 months @ 25% = 200 interest -> remaining 1000
      final calc = InstallmentCalculator.calculateEarlySettlement(
        financedPrincipalPiasters: 80000,
        totalContractInterestPiasters: 20000,
        paidTowardsSchedulePiasters: 0,
        currentRemainingPiasters: 100000,
        durationMonths: 10,
        startDate: DateTime(2026, 1, 1),
        settlementDate: DateTime(2026, 1, 8), // 7 days later
        mode: EarlySettlementMode.fullWaiver,
      );

      expect(calc.isWithinGracePeriod, isTrue);
      expect(calc.elapsedDays, 7);
      expect(calc.maxWaivableInterestPiasters, 20000);
      expect(calc.waivedInterestPiasters, 20000);
      expect(calc.settlementAmountPiasters, 80000);
      expect(calc.applicableInterestPiasters, 0);
    });

    test('proportional months (3 of 10 months after 2 paid installments) charges only 3 months interest', () {
      // Financed 800, total interest 200 (20/month), paid 200 (2 installments), remaining 800
      final calc = InstallmentCalculator.calculateEarlySettlement(
        financedPrincipalPiasters: 80000,
        totalContractInterestPiasters: 20000,
        paidTowardsSchedulePiasters: 20000,
        currentRemainingPiasters: 80000,
        durationMonths: 10,
        startDate: DateTime(2026, 1, 1),
        settlementDate: DateTime(2026, 4, 1), // 3 months later
        mode: EarlySettlementMode.proportionalMonths,
      );

      expect(calc.isWithinGracePeriod, isFalse);
      expect(calc.suggestedUsedMonths, 3);
      expect(calc.applicableInterestPiasters, 6000); // 200 * 3 / 10 = 60 EGP
      expect(calc.waivedInterestPiasters, 14000); // 140 EGP waived
      expect(calc.settlementAmountPiasters, 66000); // (800 + 60) - 200 = 660 EGP
    });

    test('alternate plan mode applies another plan interest rate on financed principal', () {
      // Financed 800, original 25% (200), switched to 3-month plan @ 5% (40), 0 paid yet
      final calc = InstallmentCalculator.calculateEarlySettlement(
        financedPrincipalPiasters: 80000,
        totalContractInterestPiasters: 20000,
        paidTowardsSchedulePiasters: 0,
        currentRemainingPiasters: 100000,
        durationMonths: 10,
        startDate: DateTime(2026, 1, 1),
        settlementDate: DateTime(2026, 3, 15),
        mode: EarlySettlementMode.alternatePlan,
        alternatePlanInterestBp: 500, // 5%
      );

      expect(calc.applicableInterestPiasters, 4000); // 5% of 800 = 40 EGP
      expect(calc.waivedInterestPiasters, 16000); // 160 EGP waived
      expect(calc.settlementAmountPiasters, 84000); // 840 EGP
    });

    test('custom waiver is clamped so settlement never drops below financed principal', () {
      final calc = InstallmentCalculator.calculateEarlySettlement(
        financedPrincipalPiasters: 80000,
        totalContractInterestPiasters: 20000,
        paidTowardsSchedulePiasters: 0,
        currentRemainingPiasters: 100000,
        durationMonths: 10,
        startDate: DateTime(2026, 1, 1),
        settlementDate: DateTime(2026, 2, 1),
        mode: EarlySettlementMode.customWaiver,
        customWaiverPiasters: 50000, // exceeds 20,000 interest!
      );

      expect(calc.maxWaivableInterestPiasters, 20000);
      expect(calc.waivedInterestPiasters, 20000);
      expect(calc.settlementAmountPiasters, 80000);
    });
  });
}
