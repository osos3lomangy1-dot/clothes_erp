import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/customer_entity.dart';

abstract class CustomerRepository {
  Future<Either<Failure, List<CustomerEntity>>> getCustomers();
  Future<Either<Failure, void>> addCustomer(CustomerEntity customer);
  Future<Either<Failure, void>> updateCustomer(CustomerEntity customer);
}
