import 'package:equatable/equatable.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

class DashboardStatsEntity extends Equatable {
  final int todaySales;
  final int todayTransactions;
  final int lowStockCount;
  final List<VariantEntity> lowStockVariants;

  const DashboardStatsEntity({
    this.todaySales = 0,
    this.todayTransactions = 0,
    this.lowStockCount = 0,
    this.lowStockVariants = const [],
  });

  @override
  List<Object?> get props => [todaySales, todayTransactions, lowStockCount, lowStockVariants];
}
