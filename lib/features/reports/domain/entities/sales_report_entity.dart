import 'package:equatable/equatable.dart';

class SalesReportEntity extends Equatable {
  final DateTime startDate;
  final DateTime endDate;
  final int totalRevenue;
  final int totalCost;
  final int totalProfit; // إجمالي أرباح البضاعة
  final int totalExpenses; // إجمالي المصروفات
  final int totalTransactions;
  final Map<String, int> paymentMethodBreakdown;

  const SalesReportEntity({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalProfit,
    this.totalExpenses = 0,
    required this.totalTransactions,
    required this.paymentMethodBreakdown,
  });

  int get netProfit => totalProfit - totalExpenses;

  @override
  List<Object?> get props => [
        startDate,
        endDate,
        totalRevenue,
        totalCost,
        totalProfit,
        totalExpenses,
        totalTransactions,
        paymentMethodBreakdown,
      ];
}
