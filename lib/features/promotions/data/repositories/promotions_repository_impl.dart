import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/branch_provider.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/features/feature_gate.dart';
import '../../domain/entities/promotion.dart';
import '../../domain/entities/promotion_report_entity.dart';
import '../../domain/repositories/promotions_repository.dart';
import '../datasources/promotions_local_data_source.dart';

@LazySingleton(as: PromotionsRepository)
class PromotionsRepositoryImpl implements PromotionsRepository {
  final PromotionsLocalDataSource _localDataSource;
  final FeatureGate _featureGate;
  final BranchProvider _branchProvider;

  PromotionsRepositoryImpl(
    this._localDataSource,
    this._featureGate,
    this._branchProvider,
  );

  @override
  Future<Either<Failure, List<Promotion>>> getActivePromotions({
    DateTime? now,
  }) async {
    try {
      final branchId = await _branchProvider.getBranchId();
      final list = await _localDataSource.getActivePromotions(
        branchId: branchId,
        now: now,
      );
      return Right(list);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Promotion>>> getAllPromotions({
    bool includeInactive = true,
  }) async {
    try {
      final branchId = await _branchProvider.getBranchId();
      final list = await _localDataSource.getAllPromotions(
        branchId: branchId,
        includeInactive: includeInactive,
      );
      return Right(list);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Promotion>>> listPromotions({
    bool includeInactive = true,
  }) =>
      getAllPromotions(includeInactive: includeInactive);

  @override
  Future<Either<Failure, Promotion?>> getPromotionById(String id) async {
    try {
      final item = await _localDataSource.getPromotionById(id);
      return Right(item);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> createPromotion(Promotion promotion) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.promotions)) {
        return const Left(FeatureDisabledFailure(FeatureKeys.promotions));
      }
      await _localDataSource.createPromotion(promotion);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updatePromotion(Promotion promotion) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.promotions)) {
        return const Left(FeatureDisabledFailure(FeatureKeys.promotions));
      }
      await _localDataSource.updatePromotion(promotion);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deactivatePromotion(String id) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.promotions)) {
        return const Left(FeatureDisabledFailure(FeatureKeys.promotions));
      }
      await _localDataSource.deactivatePromotion(id);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deletePromotion(String id) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.promotions)) {
        return const Left(FeatureDisabledFailure(FeatureKeys.promotions));
      }
      await _localDataSource.deletePromotion(id);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> recordApplications(
    List<AppliedPromotion> applications,
  ) async {
    try {
      await _localDataSource.recordApplications(applications);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, PromotionReportEntity>> getPromotionReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final branchId = await _branchProvider.getBranchId();
      final report = await _localDataSource.getPromotionReport(
        branchId: branchId,
        startDate: startDate,
        endDate: endDate,
      );
      return Right(report);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}

