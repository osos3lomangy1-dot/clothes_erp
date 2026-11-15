import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/promotion.dart';
import '../entities/promotion_report_entity.dart';

abstract class PromotionsRepository {
  Future<Either<Failure, List<Promotion>>> getActivePromotions({DateTime? now});
  Future<Either<Failure, List<Promotion>>> getAllPromotions({bool includeInactive = true});
  Future<Either<Failure, List<Promotion>>> listPromotions({bool includeInactive = true});
  Future<Either<Failure, Promotion?>> getPromotionById(String id);
  Future<Either<Failure, void>> createPromotion(Promotion promotion);
  Future<Either<Failure, void>> updatePromotion(Promotion promotion);
  Future<Either<Failure, void>> deactivatePromotion(String id);
  Future<Either<Failure, void>> deletePromotion(String id);
  Future<Either<Failure, void>> recordApplications(List<AppliedPromotion> applications);
  Future<Either<Failure, PromotionReportEntity>> getPromotionReport({
    DateTime? startDate,
    DateTime? endDate,
  });
}
