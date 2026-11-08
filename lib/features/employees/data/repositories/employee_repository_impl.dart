import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';
import '../datasources/employee_local_data_source.dart';

@LazySingleton(as: EmployeeRepository)
class EmployeeRepositoryImpl implements EmployeeRepository {
  final EmployeeLocalDataSource _localDataSource;

  EmployeeRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<EmployeeEntity>>> getEmployees({String? search}) async {
    try {
      final list = await _localDataSource.getEmployees(search: search);
      return Right(list);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, EmployeeEntity?>> getEmployeeById(String id) async {
    try {
      final employee = await _localDataSource.getEmployeeById(id);
      return Right(employee);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, EmployeeEntity>> addEmployee(EmployeeEntity employee, {String? password}) async {
    try {
      final created = await _localDataSource.addEmployee(employee, password: password);
      return Right(created);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, EmployeeEntity>> updateEmployee(EmployeeEntity employee) async {
    try {
      final updated = await _localDataSource.updateEmployee(employee);
      return Right(updated);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateEmployeeStatus(String id, bool isActive) async {
    try {
      await _localDataSource.updateEmployeeStatus(id, isActive);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteEmployee(String id) async {
    try {
      await _localDataSource.deleteEmployee(id);
      return const Right(unit);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
