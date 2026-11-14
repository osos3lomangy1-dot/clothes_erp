import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/entities/employee_payroll_summary.dart';
import '../../domain/repositories/employee_repository.dart';
import '../datasources/employee_local_data_source.dart';

@LazySingleton(as: EmployeeRepository)
class EmployeeRepositoryImpl implements EmployeeRepository {
  final EmployeeLocalDataSource _localDataSource;
  final FeatureGate _featureGate;

  EmployeeRepositoryImpl(this._localDataSource, this._featureGate);

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
      if (!await _featureGate.isEnabled(FeatureKeys.employees)) {
        return const Left(CacheFailure('ميزة الموظفين غير مفعّلة'));
      }
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

  @override
  Future<Either<Failure, EmployeePayrollSummary>> getPayrollSummary(String employeeId, {DateTime? monthDate}) async {
    try {
      final summary = await _localDataSource.getPayrollSummary(employeeId, monthDate: monthDate);
      return Right(summary);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> recordPayrollTransaction({
    required String employeeId,
    required String type,
    required int amount,
    String? note,
    required DateTime date,
    required String currentUserId,
  }) async {
    try {
      if (!await _featureGate.isEnabled(FeatureKeys.payroll)) {
        return const Left(CacheFailure('ميزة الرواتب غير مفعّلة'));
      }
      final tx = await _localDataSource.recordPayrollTransaction(
        employeeId: employeeId,
        type: type,
        amount: amount,
        note: note,
        date: date,
        currentUserId: currentUserId,
      );
      return Right(tx);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
