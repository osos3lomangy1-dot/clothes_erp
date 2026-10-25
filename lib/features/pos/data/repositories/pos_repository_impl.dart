import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/pos_repository.dart';
import '../datasources/pos_remote_data_source.dart';
import '../models/sale_model.dart';

@LazySingleton(as: PosRepository)
class PosRepositoryImpl implements PosRepository {
  final PosRemoteDataSource _remoteDataSource;

  PosRepositoryImpl(this._remoteDataSource);

  @override
  Future<Either<Failure, SaleEntity>> createSale(SaleEntity sale) async {
    try {
      final model = SaleModel.fromEntity(sale);
      final result = await _remoteDataSource.createSale(model);
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
