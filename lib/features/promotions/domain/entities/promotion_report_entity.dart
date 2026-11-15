import 'package:equatable/equatable.dart';

class PromotionUsageItem extends Equatable {
  final String promotionId;
  final String promotionName;
  final int count;
  final int totalDiscountPiasters;

  const PromotionUsageItem({
    required this.promotionId,
    required this.promotionName,
    required this.count,
    required this.totalDiscountPiasters,
  });

  @override
  List<Object?> get props => [promotionId, promotionName, count, totalDiscountPiasters];
}

class PromotionReportEntity extends Equatable {
  final int totalDiscountPiasters;
  final int totalApplications;
  final int totalSalesWithPromotions;
  final List<PromotionUsageItem> topPromotions;

  const PromotionReportEntity({
    required this.totalDiscountPiasters,
    required this.totalApplications,
    required this.totalSalesWithPromotions,
    required this.topPromotions,
  });

  @override
  List<Object?> get props => [
        totalDiscountPiasters,
        totalApplications,
        totalSalesWithPromotions,
        topPromotions,
      ];
}

