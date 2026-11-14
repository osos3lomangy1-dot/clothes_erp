import 'package:clothes_erp/features/installments/domain/entities/customer_installment_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomerInstallmentEntity.statusAt(now)', () {
    final start = DateTime(2026, 1, 1);
    final end = DateTime(2026, 7, 1);
    CustomerInstallmentEntity base({String status = 'active', int remaining = 1000}) =>
        CustomerInstallmentEntity(
          id: 'ci-1',
          branchId: 'b1',
          saleId: 's1',
          customerId: 'c1',
          planId: 'p1',
          totalPiasters: 1000,
          downPaymentPiasters: 0,
          principalPiasters: 1000,
          interestBp: 0,
          monthlyAmountPiasters: 200,
          remainingPiasters: remaining,
          durationMonths: 6,
          startDate: start,
          endDate: end,
          status: status,
          createdBy: 'u1',
          createdAt: start,
          updatedAt: start,
        );

    test('returns completed when status is completed regardless of now', () {
      final e = base(status: 'completed', remaining: 0);
      expect(e.statusAt(DateTime(2030, 1, 1)), 'completed');
      expect(e.statusAt(DateTime(2020, 1, 1)), 'completed');
    });

    test('returns cancelled when status is cancelled regardless of now', () {
      final e = base(status: 'cancelled', remaining: 500);
      expect(e.statusAt(DateTime(2030, 1, 1)), 'cancelled');
    });

    test('returns completed when remaining is zero', () {
      final e = base(status: 'active', remaining: 0);
      expect(e.statusAt(DateTime(2026, 3, 1)), 'completed');
    });

    test('returns overdue when now is after endDate and not completed/cancelled', () {
      final e = base(status: 'active', remaining: 200);
      expect(e.statusAt(DateTime(2026, 7, 2)), 'overdue');
    });

    test('returns active when now is on or before endDate and has remaining', () {
      final e = base(status: 'active', remaining: 200);
      expect(e.statusAt(DateTime(2026, 7, 1)), 'active');
      expect(e.statusAt(DateTime(2026, 3, 1)), 'active');
    });

    test('deterministic with fixed now (no DateTime.now())', () {
      final e = base(status: 'active', remaining: 200);
      final fixedNow = DateTime(2026, 8, 1);
      expect(e.statusAt(fixedNow), 'overdue');
      expect(e.statusAt(fixedNow), 'overdue');
    });
  });
}
