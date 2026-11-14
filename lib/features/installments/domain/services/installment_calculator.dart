import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/installment_schedule_entry.dart';

enum InstallmentInterestModel { fixed, percentTotal, percentMonthly }

class InstallmentCalculator {
  const InstallmentCalculator();

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
      principalPiasters: principalPiasters,
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
        dueDate: DateTime(startDate.year, startDate.month + i, startDate.day),
        amountPiasters: amount,
        principalComponentPiasters: principalPart,
        interestComponentPiasters: interestPart,
      ));
    }
    return Right(entries);
  }

  static int _totalInterestPiasters({
    required int principalPiasters,
    required int financedPrincipal,
    required int durationMonths,
    required InstallmentInterestModel interestModel,
    required int interestValue,
  }) {
    switch (interestModel) {
      case InstallmentInterestModel.fixed:
        return interestValue;
      case InstallmentInterestModel.percentTotal:
        // interestValue = basis points of principal (e.g. 1000 = 10%)
        return (principalPiasters * interestValue) ~/ 10000;
      case InstallmentInterestModel.percentMonthly:
        // interestValue = basis points per month applied to financed principal over duration
        return (financedPrincipal * interestValue * durationMonths) ~/ 10000;
    }
  }
}
