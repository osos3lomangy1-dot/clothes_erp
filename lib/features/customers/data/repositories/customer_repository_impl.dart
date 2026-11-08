import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/customer_entity.dart';
import '../../domain/repositories/customer_repository.dart';
import '../datasources/customers_local_data_source.dart';

@LazySingleton(as: CustomerRepository)
class CustomerRepositoryImpl implements CustomerRepository {
  final CustomersLocalDataSource _localDataSource;

  CustomerRepositoryImpl(this._localDataSource);

  @override
  Future<Either<Failure, List<CustomerEntity>>> getCustomers({String? search}) async {
    try {
      final rows = await _localDataSource.getCustomers(search: search);
      final entities = rows
          .map((r) => CustomerEntity(
                id: r.id,
                name: r.name,
                phone: r.phone,
                loyaltyPoints: r.loyaltyPoints,
                discountPercent: r.discountPercent,
                customerType: r.customerType,
                createdAt: r.createdAt,
              ))
          .toList();
      return Right(entities);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> addCustomer(CustomerEntity customer) async {
    try {
      await _localDataSource.addCustomer(
        name: customer.name,
        phone: customer.phone,
        loyaltyPoints: customer.loyaltyPoints,
        discountPercent: customer.discountPercent,
        customerType: customer.customerType,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateCustomer(CustomerEntity customer) async {
    try {
      await _localDataSource.updateCustomer(
        id: customer.id,
        name: customer.name,
        phone: customer.phone,
        loyaltyPoints: customer.loyaltyPoints,
        discountPercent: customer.discountPercent,
        customerType: customer.customerType,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCustomer(String id) async {
    try {
      await _localDataSource.softDeleteCustomer(id);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, CustomerEntity?>> getCustomerById(String id) async {
    try {
      final row = await _localDataSource.getCustomerById(id);
      if (row == null) return const Right(null);
      return Right(CustomerEntity(
        id: row.id,
        name: row.name,
        phone: row.phone,
        loyaltyPoints: row.loyaltyPoints,
        discountPercent: row.discountPercent,
        customerType: row.customerType,
        createdAt: row.createdAt,
      ));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
