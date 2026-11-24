import 'package:equatable/equatable.dart';
import 'top_product_report_entity.dart';

class SalesReportEntity extends Equatable {
  final DateTime startDate;
  final DateTime endDate;
  final int totalRevenue;
  final int totalCost;
  final int totalProfit; // إجمالي أرباح البضاعة
  final int totalExpenses; // إجمالي المصروفات
  final int totalTransactions;
  final Map<String, int> paymentMethodBreakdown;
  final List<TopProductReportEntity> topSellingProducts;

  // Two-Section Financial Report: Cash Flow section
  final int cashFlowIn;
  final int cashFlowOut;
  final Map<String, int> cashFlowInByMethod;
  final Map<String, int> cashFlowOutByMethod;

  // Returns in period
  final int totalReturns;

  const SalesReportEntity({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalProfit,
    this.totalExpenses = 0,
    this.totalReturns = 0,
    required this.totalTransactions,
    required this.paymentMethodBreakdown,
    this.topSellingProducts = const [],
    this.cashFlowIn = 0,
    this.cashFlowOut = 0,
    this.cashFlowInByMethod = const {},
    this.cashFlowOutByMethod = const {},
  });

  int get netProfit => totalProfit - totalExpenses;
  int get netCashFlow => cashFlowIn - cashFlowOut;
  int get netRevenue => totalRevenue - totalReturns;

  @override
  List<Object?> get props => [
        startDate,
        endDate,
        totalRevenue,
        totalCost,
        totalProfit,
        totalExpenses,
        totalReturns,
        totalTransactions,
        paymentMethodBreakdown,
        topSellingProducts,
        cashFlowIn,
        cashFlowOut,
        cashFlowInByMethod,
        cashFlowOutByMethod,
      ];
}
