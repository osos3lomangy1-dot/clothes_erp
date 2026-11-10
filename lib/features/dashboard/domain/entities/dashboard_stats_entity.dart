import 'package:equatable/equatable.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import 'sales_chart_point_entity.dart';

class DashboardStatsEntity extends Equatable {
  final int todaySales;
  final int todayTransactions;
  final int lowStockCount;
  final List<VariantEntity> lowStockVariants;
  final List<DailySalesPointEntity> last7DaysSales;
  final List<HourlySalesPointEntity> todayHourlySales;

  const DashboardStatsEntity({
    this.todaySales = 0,
    this.todayTransactions = 0,
    this.lowStockCount = 0,
    this.lowStockVariants = const [],
    this.last7DaysSales = const [],
    this.todayHourlySales = const [],
  });

  @override
  List<Object?> get props => [
        todaySales,
        todayTransactions,
        lowStockCount,
        lowStockVariants,
        last7DaysSales,
        todayHourlySales,
      ];
}
