import 'package:equatable/equatable.dart';

class SalesReportEntity extends Equatable {
  final DateTime startDate;
  final DateTime endDate;
  final int totalRevenue;
  final int totalCost;
  final int totalProfit;
  final int totalTransactions;
  final Map<String, int> paymentMethodBreakdown;

  const SalesReportEntity({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalProfit,
    required this.totalTransactions,
    required this.paymentMethodBreakdown,
  });

  @override
  List<Object?> get props => [
        startDate,
        endDate,
        totalRevenue,
        totalCost,
        totalProfit,
        totalTransactions,
        paymentMethodBreakdown,
      ];
}

