import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';
import '../datasources/employee_remote_data_source.dart';
import '../models/employee_model.dart';

@LazySingleton(as: EmployeeRepository)
class EmployeeRepositoryImpl implements EmployeeRepository {
  final EmployeeRemoteDataSource _remoteDataSource;

  EmployeeRepositoryImpl(this._remoteDataSource);

  @override
  Stream<List<EmployeeEntity>> getEmployees() {
    return _remoteDataSource.getEmployees();
  }

  @override
  Future<Either<Failure, Unit>> addEmployee(EmployeeEntity employee) async {
    try {
      await _remoteDataSource.addEmployee(EmployeeModel.fromEntity(employee));
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateEmployeeStatus(String id, bool isActive) async {
    try {
      await _remoteDataSource.updateEmployeeStatus(id, isActive);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteEmployee(String id) async {
    try {
      await _remoteDataSource.deleteEmployee(id);
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
