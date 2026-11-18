import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/installment_payment_entity.dart';
import '../entities/installment_schedule_entry.dart';

enum InstallmentInterestModel { fixed, percentTotal, percentMonthly }

enum EarlySettlementMode {
  /// Waive 100% of remaining interest (e.g. customer pays cash within grace period).
  fullWaiver,

  /// Charge interest proportionally for actual elapsed/used months only.
  proportionalMonths,

  /// Recalculate interest using another plan's rate (basis points on financed principal).
  alternatePlan,

  /// Manager enters a custom waived interest amount (capped at max waivable interest).
  customWaiver,
}

/// Pure calculation breakdown for early contract settlement (السداد المبكر).
class EarlySettlementCalculation {
  final int financedPrincipalPiasters;
  final int totalContractInterestPiasters;
  final int paidTowardsSchedulePiasters;
  final int currentRemainingPiasters;
  final int maxWaivableInterestPiasters;
  final int applicableInterestPiasters;
  final int waivedInterestPiasters;
  final int settlementAmountPiasters;
  final int elapsedDays;
  final int suggestedUsedMonths;
  final bool isWithinGracePeriod;

  const EarlySettlementCalculation({
    required this.financedPrincipalPiasters,
    required this.totalContractInterestPiasters,
    required this.paidTowardsSchedulePiasters,
    required this.currentRemainingPiasters,
    required this.maxWaivableInterestPiasters,
    required this.applicableInterestPiasters,
    required this.waivedInterestPiasters,
    required this.settlementAmountPiasters,
    required this.elapsedDays,
    required this.suggestedUsedMonths,
    required this.isWithinGracePeriod,
  });
}

/// Allocation state for a single scheduled installment after applying all
/// chronological contract payments.
///
/// Overpayment rule:
/// - Each payment first covers the earliest unpaid installment in chronological order.
/// - Any excess above that installment rolls to the LAST unpaid installment(s)
///   from the end of the schedule backwards, leaving intermediate months intact.
class InstallmentScheduleAllocation {
  final InstallmentScheduleEntry entry;
  final int paidRegularPiasters;
  final int paidFromExcessPiasters;
  final DateTime? paidAt;

  const InstallmentScheduleAllocation({
    required this.entry,
    required this.paidRegularPiasters,
    required this.paidFromExcessPiasters,
    required this.paidAt,
  });

  int get totalPaidPiasters => paidRegularPiasters + paidFromExcessPiasters;

  int get remainingPiasters {
    final rem = entry.amountPiasters - totalPaidPiasters;
    return rem < 0 ? 0 : rem;
  }

  bool get isPaid => remainingPiasters <= 0;

  bool get hasExcessCarryOver => paidFromExcessPiasters > 0;

  bool get isPartiallyPaid => !isPaid && totalPaidPiasters > 0;

  bool get isPaidOnlyFromExcess => isPaid && paidRegularPiasters == 0 && paidFromExcessPiasters > 0;

  /// Day difference between actual payment date and due date (date-only):
  /// negative = paid early, 0 = paid on exact due date, positive = paid late.
  int? get daysFromDueDate {
    if (paidAt == null) return null;
    final paidDay = DateTime(paidAt!.year, paidAt!.month, paidAt!.day);
    final dueDay = DateTime(entry.dueDate.year, entry.dueDate.month, entry.dueDate.day);
    return paidDay.difference(dueDay).inDays;
  }
}

class InstallmentCalculator {
  const InstallmentCalculator();

  /// Safely adds [months] to [date], clamping the day to the last day of the
  /// target month (e.g. Jan 31 + 1 month => Feb 28/29 instead of Mar 3).
  static DateTime addMonths(DateTime date, int months) {
    final totalMonths = date.year * 12 + (date.month - 1) + months;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final lastDayOfMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = date.day <= lastDayOfMonth ? date.day : lastDayOfMonth;
    return DateTime(targetYear, targetMonth, targetDay);
  }

  static Either<Failure, List<InstallmentScheduleEntry>> calculateSchedule({
    required int principalPiasters,
    required int durationMonths,
    required InstallmentInterestModel interestModel,
    required int interestValue,
    required int downPaymentPiasters,
    required DateTime startDate,
  }) {
    if (durationMonths < 1) {
      return const Left(ServerFailure('durationMonths must be >= 1'));
    }
    if (principalPiasters < 0 ||
        downPaymentPiasters < 0 ||
        interestValue < 0 ||
        downPaymentPiasters > principalPiasters) {
      return const Left(ServerFailure('invalid installment calculation inputs'));
    }

    final financedPrincipal = principalPiasters - downPaymentPiasters;
    final totalInterest = _totalInterestPiasters(
      financedPrincipal: financedPrincipal,
      durationMonths: durationMonths,
      interestModel: interestModel,
      interestValue: interestValue,
    );
    if (totalInterest < 0) {
      return const Left(ServerFailure('invalid interest'));
    }

    final baseInterest = totalInterest ~/ durationMonths;
    final basePrincipal = financedPrincipal ~/ durationMonths;

    var allocatedPrincipal = 0;
    var allocatedInterest = 0;
    final entries = <InstallmentScheduleEntry>[];
    for (var i = 1; i <= durationMonths; i++) {
      final isLast = i == durationMonths;
      final interestPart = isLast ? (totalInterest - allocatedInterest) : baseInterest;
      final principalPart = isLast ? (financedPrincipal - allocatedPrincipal) : basePrincipal;
      final amount = principalPart + interestPart;
      allocatedInterest += interestPart;
      allocatedPrincipal += principalPart;
      entries.add(InstallmentScheduleEntry(
        installmentNumber: i,
        dueDate: addMonths(startDate, i),
        amountPiasters: amount,
        principalComponentPiasters: principalPart,
        interestComponentPiasters: interestPart,
      ));
    }
    return Right(entries);
  }

  /// Allocates non-down-payment installment payments onto [schedule]:
  /// 1. Each payment covers the earliest unpaid installment first.
  /// 2. Any excess above that installment is carried over to the LAST unpaid
  ///    installment(s) from the end of the schedule backwards.
  /// 3. The actual [InstallmentPaymentEntity.paidAt] date is recorded on every
  ///    installment affected (whether paid before, on, or after its due date).
  static List<InstallmentScheduleAllocation> allocatePaymentsToSchedule({
    required List<InstallmentScheduleEntry> schedule,
    required List<InstallmentPaymentEntity> payments,
  }) {
    final n = schedule.length;
    if (n == 0) return const [];

    final paidRegular = List<int>.filled(n, 0);
    final paidExcess = List<int>.filled(n, 0);
    final lastPaidAt = List<DateTime?>.filled(n, null);

    int remainingFor(int idx) =>
        schedule[idx].amountPiasters - (paidRegular[idx] + paidExcess[idx]);

    final installmentPayments = payments
        .where((p) => p.receiptNumber != 'DOWN_PAYMENT' && p.amountPiasters > 0)
        .toList()
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt));

    for (final payment in installmentPayments) {
      var left = payment.amountPiasters;
      if (left <= 0) continue;

      // 1. Cover the earliest unpaid installment in chronological order
      var firstUnpaid = -1;
      for (var i = 0; i < n; i++) {
        if (remainingFor(i) > 0) {
          firstUnpaid = i;
          break;
        }
      }
      if (firstUnpaid == -1) break;

      final neededCurrent = remainingFor(firstUnpaid);
      final applyCurrent = left < neededCurrent ? left : neededCurrent;
      paidRegular[firstUnpaid] += applyCurrent;
      lastPaidAt[firstUnpaid] = payment.paidAt;
      left -= applyCurrent;

      // 2. Roll any excess to the LAST unpaid installment(s) backwards
      for (var j = n - 1; j > firstUnpaid && left > 0; j--) {
        final neededTail = remainingFor(j);
        if (neededTail <= 0) continue;
        final applyTail = left < neededTail ? left : neededTail;
        paidExcess[j] += applyTail;
        lastPaidAt[j] = payment.paidAt;
        left -= applyTail;
      }
    }

    return List<InstallmentScheduleAllocation>.generate(
      n,
      (i) => InstallmentScheduleAllocation(
        entry: schedule[i],
        paidRegularPiasters: paidRegular[i],
        paidFromExcessPiasters: paidExcess[i],
        paidAt: lastPaidAt[i],
      ),
    );
  }

  /// Computes early settlement payoff & interest waiver without dropping below
  /// the original financed principal (cash price minus down payment).
  static EarlySettlementCalculation calculateEarlySettlement({
    required int financedPrincipalPiasters,
    required int totalContractInterestPiasters,
    required int paidTowardsSchedulePiasters,
    required int currentRemainingPiasters,
    required int durationMonths,
    required DateTime startDate,
    required DateTime settlementDate,
    required EarlySettlementMode mode,
    int? usedMonthsOverride,
    int? alternatePlanInterestBp,
    int? customWaiverPiasters,
    int gracePeriodDays = 14,
  }) {
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final settleDay = DateTime(settlementDate.year, settlementDate.month, settlementDate.day);
    final elapsedDays = settleDay.difference(startDay).inDays.clamp(0, 100000);
    final isWithinGrace = elapsedDays <= gracePeriodDays;

    // Suggested elapsed months (at least 1 if past grace period, clamped to durationMonths)
    int rawMonths = (settleDay.year - startDay.year) * 12 + (settleDay.month - startDay.month);
    if (settleDay.day > startDay.day) {
      rawMonths += 1;
    }
    final safeDuration = durationMonths < 1 ? 1 : durationMonths;
    final suggestedUsedMonths = isWithinGrace
        ? 0
        : rawMonths.clamp(1, safeDuration);

    // Minimum cash required so total paid never drops below financedPrincipal (original cash balance)
    final minCashForPrincipal =
        (financedPrincipalPiasters - paidTowardsSchedulePiasters).clamp(0, currentRemainingPiasters);
    final maxWaivableInterest =
        (currentRemainingPiasters - minCashForPrincipal).clamp(0, currentRemainingPiasters);

    int applicableInterest;
    int settlementAmount;
    int waivedInterest;

    switch (mode) {
      case EarlySettlementMode.fullWaiver:
        applicableInterest = 0;
        waivedInterest = maxWaivableInterest;
        settlementAmount = currentRemainingPiasters - waivedInterest;
        break;

      case EarlySettlementMode.proportionalMonths:
        final months = (usedMonthsOverride ?? (suggestedUsedMonths > 0 ? suggestedUsedMonths : 1))
            .clamp(0, safeDuration);
        applicableInterest = (totalContractInterestPiasters * months) ~/ safeDuration;
        final desiredTotal = financedPrincipalPiasters + applicableInterest;
        settlementAmount = (desiredTotal - paidTowardsSchedulePiasters)
            .clamp(minCashForPrincipal, currentRemainingPiasters);
        waivedInterest = currentRemainingPiasters - settlementAmount;
        break;

      case EarlySettlementMode.alternatePlan:
        final bp = (alternatePlanInterestBp ?? 0).clamp(0, 10000);
        applicableInterest = (financedPrincipalPiasters * bp) ~/ 10000;
        final desiredTotal = financedPrincipalPiasters + applicableInterest;
        settlementAmount = (desiredTotal - paidTowardsSchedulePiasters)
            .clamp(minCashForPrincipal, currentRemainingPiasters);
        waivedInterest = currentRemainingPiasters - settlementAmount;
        break;

      case EarlySettlementMode.customWaiver:
        waivedInterest = (customWaiverPiasters ?? 0).clamp(0, maxWaivableInterest);
        settlementAmount = currentRemainingPiasters - waivedInterest;
        applicableInterest = (totalContractInterestPiasters - waivedInterest)
            .clamp(0, totalContractInterestPiasters);
        break;
    }

    return EarlySettlementCalculation(
      financedPrincipalPiasters: financedPrincipalPiasters,
      totalContractInterestPiasters: totalContractInterestPiasters,
      paidTowardsSchedulePiasters: paidTowardsSchedulePiasters,
      currentRemainingPiasters: currentRemainingPiasters,
      maxWaivableInterestPiasters: maxWaivableInterest,
      applicableInterestPiasters: applicableInterest,
      waivedInterestPiasters: waivedInterest,
      settlementAmountPiasters: settlementAmount,
      elapsedDays: elapsedDays,
      suggestedUsedMonths: suggestedUsedMonths,
      isWithinGracePeriod: isWithinGrace,
    );
  }

  static int _totalInterestPiasters({
    required int financedPrincipal,
    required int durationMonths,
    required InstallmentInterestModel interestModel,
    required int interestValue,
  }) {
    switch (interestModel) {
      case InstallmentInterestModel.fixed:
        return interestValue;
      case InstallmentInterestModel.percentTotal:
        // interestValue = basis points of financed remaining amount (e.g. 1000 = 10%)
        return (financedPrincipal * interestValue) ~/ 10000;
      case InstallmentInterestModel.percentMonthly:
        // interestValue = basis points per month applied to financed principal over duration
        return (financedPrincipal * interestValue * durationMonths) ~/ 10000;
    }
  }
}
