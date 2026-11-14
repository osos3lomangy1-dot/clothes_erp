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
        return (principalP * value) ~/ 10000;
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
  });
}
