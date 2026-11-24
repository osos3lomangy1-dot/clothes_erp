import 'package:equatable/equatable.dart';
import '../../../dashboard/domain/entities/sales_chart_point_entity.dart';
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

  // Task 31: Period-over-Period & Executive KPIs
  final int previousTotalRevenue;
  final int previousNetProfit;
  final int previousTotalTransactions;
  final int inventoryCostCapitalPiasters;

  // Task 32: Advanced Visual Analytics
  final List<DailySalesPointEntity> dailySalesTrend;
  final List<HourlySalesPointEntity> hourlySalesDistribution;
  final Map<String, int> categoryRevenueBreakdown;
  final List<TopProductReportEntity> mostProfitableProducts;

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
    this.previousTotalRevenue = 0,
    this.previousNetProfit = 0,
    this.previousTotalTransactions = 0,
    this.inventoryCostCapitalPiasters = 0,
    this.dailySalesTrend = const [],
    this.hourlySalesDistribution = const [],
    this.categoryRevenueBreakdown = const {},
    this.mostProfitableProducts = const [],
  });

  int get netProfit => totalProfit - totalExpenses;
  int get netCashFlow => cashFlowIn - cashFlowOut;
  int get netRevenue => totalRevenue - totalReturns;

  double get profitMarginPercent =>
      netRevenue > 0 ? (netProfit / netRevenue) * 100 : 0.0;

  int get averageOrderValuePiasters =>
      totalTransactions > 0 ? netRevenue ~/ totalTransactions : 0;

  double? get revenueGrowthPercent {
    if (previousTotalRevenue <= 0) return null;
    return ((totalRevenue - previousTotalRevenue) / previousTotalRevenue) * 100;
  }

  double? get netProfitGrowthPercent {
    if (previousNetProfit == 0) return null;
    return ((netProfit - previousNetProfit) / previousNetProfit.abs()) * 100;
  }

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
        previousTotalRevenue,
        previousNetProfit,
        previousTotalTransactions,
        inventoryCostCapitalPiasters,
        dailySalesTrend,
        hourlySalesDistribution,
        categoryRevenueBreakdown,
        mostProfitableProducts,
      ];
}
