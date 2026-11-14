import 'package:equatable/equatable.dart';

class InstallmentSummary extends Equatable {
  final int totalOutstanding; // sum of remaining where status = active
  final int monthlyCollected; // sum of payments this month
  final int overdueTotal; // sum of remaining where statusAt(now) = overdue
  final int overdueCount; // count of overdue contracts

  const InstallmentSummary({
    required this.totalOutstanding,
    required this.monthlyCollected,
    required this.overdueTotal,
    required this.overdueCount,
  });

  const InstallmentSummary.empty()
      : totalOutstanding = 0,
        monthlyCollected = 0,
        overdueTotal = 0,
        overdueCount = 0;

  @override
  List<Object?> get props => [
        totalOutstanding,
        monthlyCollected,
        overdueTotal,
        overdueCount,
      ];
}

