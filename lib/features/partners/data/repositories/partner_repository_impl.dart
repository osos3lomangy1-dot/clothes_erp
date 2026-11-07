import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/partner_entity.dart';
import '../../domain/repositories/partner_repository.dart';
import '../datasources/partners_local_data_source.dart';

@LazySingleton(as: PartnerRepository)
class PartnerRepositoryImpl implements PartnerRepository {
  final PartnersLocalDataSource localDataSource;

  PartnerRepositoryImpl(this.localDataSource);

  @override
  Future<Either<Failure, List<PartnerEntity>>> getPartners() async {
    try {
      final list = await localDataSource.getPartners();
      return Right(list);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> savePartner(PartnerEntity partner) async {
    try {
      await localDataSource.savePartner(partner);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deletePartner(String id) async {
    try {
      await localDataSource.deletePartner(id);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ProfitSummary>> getProfitSummary({DateTime? from, DateTime? to}) async {
    try {
      final summary = await localDataSource.getProfitSummary(from: from, to: to);
      return Right(summary);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
