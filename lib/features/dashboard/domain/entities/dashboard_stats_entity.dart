import 'package:equatable/equatable.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../reports/domain/entities/top_product_report_entity.dart';
import 'sales_chart_point_entity.dart';

class DashboardStatsEntity extends Equatable {
  final int todaySales; // in piasters
  final int todayTransactions;
  final int todayCost; // in piasters
  final int todayExpenses; // in piasters
  final int todayEstimatedNetProfit; // in piasters (Sales - Cost - Expenses)
  final int todayReturnsTotal; // in piasters
  final int todayReturnsCount;

  // Shift & Live Cash
  final bool hasActiveShift;
  final String? activeCashierName;
  final int activeShiftOpeningBalance; // in piasters
  final int liveDrawerCash; // in piasters

  // Alerts & Debts
  final int lowStockCount;
  final List<VariantEntity> lowStockVariants;
  final int overdueInstallmentsCount;
  final int overdueInstallmentsAmount; // in piasters
  final int totalSupplierDebts; // in piasters
  final int totalCustomerCreditDebts; // in piasters

  // Charts & Breakdowns
  final List<DailySalesPointEntity> last7DaysSales;
  final List<HourlySalesPointEntity> todayHourlySales;
  final Map<String, int> todayPaymentBreakdown;
  final List<TopProductReportEntity> todayTopProducts;

  const DashboardStatsEntity({
    this.todaySales = 0,
    this.todayTransactions = 0,
    this.todayCost = 0,
    this.todayExpenses = 0,
    this.todayEstimatedNetProfit = 0,
    this.todayReturnsTotal = 0,
    this.todayReturnsCount = 0,
    this.hasActiveShift = false,
    this.activeCashierName,
    this.activeShiftOpeningBalance = 0,
    this.liveDrawerCash = 0,
    this.lowStockCount = 0,
    this.lowStockVariants = const [],
    this.overdueInstallmentsCount = 0,
    this.overdueInstallmentsAmount = 0,
    this.totalSupplierDebts = 0,
    this.totalCustomerCreditDebts = 0,
    this.last7DaysSales = const [],
    this.todayHourlySales = const [],
    this.todayPaymentBreakdown = const {},
    this.todayTopProducts = const [],
  });

  @override
  List<Object?> get props => [
        todaySales,
        todayTransactions,
        todayCost,
        todayExpenses,
        todayEstimatedNetProfit,
        todayReturnsTotal,
        todayReturnsCount,
        hasActiveShift,
        activeCashierName,
        activeShiftOpeningBalance,
        liveDrawerCash,
        lowStockCount,
        lowStockVariants,
        overdueInstallmentsCount,
        overdueInstallmentsAmount,
        totalSupplierDebts,
        totalCustomerCreditDebts,
        last7DaysSales,
        todayHourlySales,
        todayPaymentBreakdown,
        todayTopProducts,
      ];
}
