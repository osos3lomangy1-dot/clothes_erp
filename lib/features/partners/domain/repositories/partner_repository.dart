import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../data/datasources/partners_local_data_source.dart';
import '../entities/partner_entity.dart';

abstract class PartnerRepository {
  Future<Either<Failure, List<PartnerEntity>>> getPartners();
  Future<Either<Failure, void>> savePartner(PartnerEntity partner);
  Future<Either<Failure, void>> deletePartner(String id);
  Future<Either<Failure, ProfitSummary>> getProfitSummary({DateTime? from, DateTime? to});
}

